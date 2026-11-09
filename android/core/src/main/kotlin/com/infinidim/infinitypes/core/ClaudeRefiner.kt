package com.infinidim.infinitypes.core

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

data class RefinementResult(val text: String, val modelId: String, val inputTokens: Int?, val outputTokens: Int?)

/** @property editCount quantas alterações foram aplicadas; `null` quando o modelo reescreveu o texto inteiro. */
data class RevisionResult(val text: String, val modelId: String, val editCount: Int?, val inputTokens: Int, val outputTokens: Int)

enum class RevisionFormat {
    /** Lista de alterações aplicadas localmente: rápida, e o resto do texto fica intacto. */
    EDITS,

    /** Texto completo reescrito, a reserva quando as alterações não casam com o original. */
    FULL_TEXT,
}

/** Prompts de `shared/prompts/`, empacotados como recursos. */
object Prompts {
    fun load(resource: String): String =
        Prompts::class.java.getResourceAsStream("/$resource.md")?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
            ?: error("$resource.md não foi empacotado")
}

/** Transforma a transcrição bruta no texto final usando o modelo escolhido nos ajustes. */
class ClaudeRefiner(
    private val apiKey: () -> String?,
    private val settings: () -> Pair<String, Effort>,
) {
    private val systemPrompts = mapOf(
        DictationMode.PROMPT to Prompts.load(DictationMode.PROMPT.systemPromptResource),
        DictationMode.LITERAL to Prompts.load(DictationMode.LITERAL.systemPromptResource),
    )
    private val revisionPrompts = Prompts.load(DictationMode.REVISION.systemPromptResource).let { template ->
        mapOf(
            RevisionFormat.EDITS to revisionPrompt(template, Prompts.load("RevisionFormatEdits")),
            RevisionFormat.FULL_TEXT to revisionPrompt(template, Prompts.load("RevisionFormatFullText")),
        )
    }

    /** Recebe os motivos das falhas, nunca o texto do usuário. */
    var log: ((String) -> Unit)? = null

    fun refine(transcript: String, context: DictationContext, mode: DictationMode, vocabulary: List<String>): RefinementResult {
        val (client, model, effort) = prepare()
        val request = makeRequest(model, effort, systemPrompts.getValue(mode), transcript, context, vocabulary)
        val response = text(client.createMessage(request))
        return RefinementResult(response.text, model.id, response.inputTokens, response.outputTokens)
    }

    /** Incorpora a fala ao texto selecionado. */
    fun revise(selection: String, dictation: String, context: DictationContext, vocabulary: List<String>): RevisionResult {
        val (client, model, effort) = prepare()
        var inputTokens = 0
        var outputTokens = 0

        if (model.supportsEffort) {
            val request = makeRevisionRequest(model, effort, revisionPrompts.getValue(RevisionFormat.EDITS), RevisionFormat.EDITS,
                selection, dictation, context, vocabulary)
            val response = text(client.createMessage(request, timeoutMillis = 60_000))
            inputTokens += response.inputTokens ?: 0
            outputTokens += response.outputTokens ?: 0
            try {
                val edits = RevisionPatcher.parse(response.text)
                return RevisionResult(RevisionPatcher.apply(edits, selection), model.id, edits.size, inputTokens, outputTokens)
            } catch (error: RevisionPatchException) {
                log?.invoke("Alterações não casaram com o original (${error.error.reason}); reescrevendo o texto inteiro")
            } catch (error: JSONException) {
                log?.invoke("Alterações não casaram com o original (resposta fora do esquema); reescrevendo o texto inteiro")
            }
        }

        val request = makeRevisionRequest(model, effort, revisionPrompts.getValue(RevisionFormat.FULL_TEXT), RevisionFormat.FULL_TEXT,
            selection, dictation, context, vocabulary)
        val response = text(client.createMessage(request, timeoutMillis = 120_000))
        // A resposta vem sem espaços nas pontas; mantém os da seleção, como uma quebra de linha final.
        val leading = selection.takeWhile { it.isWhitespace() }
        val trailing = selection.takeLastWhile { it.isWhitespace() }
        return RevisionResult(leading + response.text + trailing, model.id, null,
            inputTokens + (response.inputTokens ?: 0), outputTokens + (response.outputTokens ?: 0))
    }

    private fun prepare(): Triple<AnthropicClient, RefinementModel, Effort> {
        val key = apiKey()?.takeIf { it.isNotBlank() } ?: throw AnthropicException(AnthropicException.Kind.MISSING_API_KEY)
        val (modelId, effort) = settings()
        return Triple(AnthropicClient(key), ModelCatalog.model(modelId), effort)
    }

    private fun text(response: MessageResponse): MessageResponse {
        when (response.stopReason) {
            "refusal" -> throw AnthropicException(AnthropicException.Kind.REFUSAL)
            "max_tokens" -> throw AnthropicException(AnthropicException.Kind.TRUNCATED)
        }
        val text = response.text.trim()
        if (text.isEmpty()) throw AnthropicException(AnthropicException.Kind.EMPTY_RESPONSE)
        return response.copy(text = text)
    }

    companion object {
        // O raciocínio também conta neste limite; o texto final costuma ter poucas centenas de tokens.
        private const val MAX_TOKENS = 16_000

        fun makeRequest(model: RefinementModel, effort: Effort, systemPrompt: String, transcript: String,
                        context: DictationContext, vocabulary: List<String> = emptyList()): MessageRequest =
            request(model, systemPrompt, userMessage(transcript, context, vocabulary),
                if (model.supportsEffort) JSONObject().put("effort", effort.rawValue) else null)

        fun makeRevisionRequest(model: RefinementModel, effort: Effort, systemPrompt: String, format: RevisionFormat,
                                selection: String, dictation: String, context: DictationContext,
                                vocabulary: List<String>): MessageRequest {
            val outputConfig = if (model.supportsEffort) {
                JSONObject().put("effort", effort.rawValue).apply {
                    if (format == RevisionFormat.EDITS) {
                        put("format", JSONObject().put("type", "json_schema").put("schema", RevisionPatcher.schema()))
                    }
                }
            } else null
            val message = contextBlock(context, vocabulary) +
                "\n\n<texto_original>\n$selection\n</texto_original>\n\n<fala>\n$dictation\n</fala>"
            return request(model, systemPrompt, message, outputConfig)
        }

        fun userMessage(transcript: String, context: DictationContext, vocabulary: List<String>): String =
            contextBlock(context, vocabulary) + "\n\n<transcricao>\n$transcript\n</transcricao>"

        /** `{{formato}}` no prompt da revisão vira as instruções do formato pedido. */
        fun revisionPrompt(template: String, instructions: String): String =
            template.replace("{{formato}}", instructions.trim())

        private fun request(model: RefinementModel, systemPrompt: String, message: String, outputConfig: JSONObject?): MessageRequest {
            val body = JSONObject()
                .put("model", model.id)
                .put("max_tokens", MAX_TOKENS)
                .put("system", JSONArray().put(JSONObject()
                    .put("type", "text")
                    .put("text", systemPrompt)
                    .put("cache_control", JSONObject().put("type", "ephemeral"))))
                .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", message)))
            outputConfig?.let { body.put("output_config", it) }
            if (model.supportsServerFallback) body.put("fallbacks", "default")
            return MessageRequest(body, AnthropicClient.betaHeader(body))
        }

        private fun contextBlock(context: DictationContext, vocabulary: List<String>): String {
            val lines = listOfNotNull(
                context.appName?.let { "App: $it" },
                context.windowTitle?.let { "Janela: $it" },
                context.projectName?.let { "Projeto: $it" },
            )
            var block = "<contexto>\n${if (lines.isEmpty()) "(desconhecido)" else lines.joinToString("\n")}\n</contexto>"
            if (vocabulary.isNotEmpty()) block += "\n\n<glossario>\n${vocabulary.joinToString("\n")}\n</glossario>"
            return block
        }
    }
}
