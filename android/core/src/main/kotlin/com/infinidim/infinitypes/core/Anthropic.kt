package com.infinidim.infinitypes.core

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URI
import java.net.URLEncoder
import java.util.Locale

/** Quanto o modelo raciocina antes de responder (`output_config.effort`). */
enum class Effort(val rawValue: String, val label: String) {
    LOW("low", "Baixa"),
    MEDIUM("medium", "Média"),
    HIGH("high", "Alta");

    companion object {
        fun parse(raw: String?): Effort = entries.firstOrNull { it.rawValue == raw } ?: LOW
    }
}

/**
 * Modelo da Anthropic que pode fazer o refinamento.
 *
 * @property pricing preço em US$ por milhão de tokens (entrada, saída); `null` para modelos que o app não conhece.
 * @property supportsEffort aceita `output_config.effort`. Modelos desconhecidos recebem a requisição mínima.
 * @property supportsServerFallback aceita `fallbacks: "default"` (nova tentativa do lado do servidor quando o modelo recusa).
 */
data class RefinementModel(
    val id: String,
    val displayName: String,
    val pricing: Pair<Double, Double>?,
    val supportsEffort: Boolean,
    val supportsServerFallback: Boolean,
) {
    val priceLabel: String?
        get() = pricing?.let { (input, output) -> "US$ ${format(input)} / ${format(output)} por milhão de tokens" }

    /** "4", "0,10": centavos só quando o preço não é inteiro. */
    private fun format(price: Double): String =
        if (price == Math.rint(price)) price.toLong().toString()
        else String.format(Locale.forLanguageTag("pt-BR"), "%.2f", price)
}

object ModelCatalog {
    const val DEFAULT_MODEL_ID = "claude-opus-5-5"

    /** Modelos atuais da Anthropic, para os quais o app monta a requisição completa. */
    val known = listOf(
        RefinementModel("claude-opus-5-5", "Claude Opus 5.5", 4.0 to 20.0, supportsEffort = true, supportsServerFallback = true),
        RefinementModel("claude-sonnet-5-5", "Claude Sonnet 5.5", 2.0 to 10.0, supportsEffort = true, supportsServerFallback = true),
        RefinementModel("claude-haiku-5-5", "Claude Haiku 5.5", 0.10 to 0.50, supportsEffort = true, supportsServerFallback = false),
        RefinementModel("claude-fable-5-1", "Claude Fable 5.1", 10.0 to 50.0, supportsEffort = true, supportsServerFallback = true),
    )

    fun model(id: String): RefinementModel = known.firstOrNull { it.id == id } ?: unknown(id, id)

    /** Modelos conhecidos primeiro, seguidos dos demais que a Models API devolveu para a conta. */
    fun merge(available: List<Pair<String, String>>): List<RefinementModel> {
        val knownIds = known.map { it.id }.toSet()
        return known + available.filter { it.first !in knownIds }.map { unknown(it.first, it.second) }
    }

    private fun unknown(id: String, name: String) =
        RefinementModel(id, name, null, supportsEffort = false, supportsServerFallback = false)
}

class AnthropicException(val kind: Kind, val status: Int = 0, apiMessage: String? = null) :
    Exception(describe(kind, status, apiMessage)) {
    enum class Kind { MISSING_API_KEY, HTTP, REFUSAL, TRUNCATED, EMPTY_RESPONSE }

    val isRetryable: Boolean get() = kind == Kind.HTTP && (status == 429 || status >= 500)

    private companion object {
        fun describe(kind: Kind, status: Int, message: String?) = when (kind) {
            Kind.MISSING_API_KEY -> "Configure a chave da API nos Ajustes"
            Kind.REFUSAL -> "O modelo recusou o pedido"
            Kind.TRUNCATED -> "A resposta do modelo veio incompleta"
            Kind.EMPTY_RESPONSE -> "O modelo não devolveu texto"
            Kind.HTTP -> when (status) {
                401 -> "Chave da API inválida"
                403 -> "A chave não tem permissão para usar este modelo"
                404 -> "Modelo indisponível para a sua conta"
                429 -> "Limite de uso da API atingido"
                529 -> "API da Anthropic sobrecarregada"
                0 -> "Sem conexão com a API da Anthropic"
                else -> if (message == null) "Erro da API ($status)" else "Erro da API ($status): $message"
            }
        }
    }
}

/** Requisição para `POST /v1/messages`, já com o cabeçalho de beta quando necessário. */
data class MessageRequest(val body: JSONObject, val betaHeader: String?)

data class MessageResponse(val text: String, val stopReason: String?, val inputTokens: Int?, val outputTokens: Int?)

/** Cliente HTTP mínimo da API da Anthropic, com o mesmo comportamento dos outros apps. */
class AnthropicClient(private val apiKey: String) {
    fun createMessage(request: MessageRequest, timeoutMillis: Int = 45_000): MessageResponse {
        val json = send("messages", "POST", request.body.toString(), request.betaHeader, timeoutMillis, retryOnce = true)
        val content = json.optJSONArray("content") ?: JSONArray()
        // Só os blocos de texto; os de raciocínio (`thinking`) e de fallback ficam de fora.
        val text = buildString {
            for (i in 0 until content.length()) {
                val block = content.getJSONObject(i)
                if (block.optString("type") == "text") append(block.optString("text"))
            }
        }
        val usage = json.optJSONObject("usage")
        return MessageResponse(
            text,
            json.optString("stop_reason").ifEmpty { null },
            usage?.optInt("input_tokens"),
            usage?.optInt("output_tokens"),
        )
    }

    /** (id, nome de exibição) de cada modelo disponível para a conta. */
    fun listModels(): List<Pair<String, String>> {
        val models = mutableListOf<Pair<String, String>>()
        var afterId: String? = null
        do {
            val path = "models?limit=100" + (afterId?.let { "&after_id=${URLEncoder.encode(it, "UTF-8")}" } ?: "")
            val page = send(path, "GET", null, null, 30_000, retryOnce = false)
            val data = page.getJSONArray("data")
            for (i in 0 until data.length()) {
                val model = data.getJSONObject(i)
                models += model.getString("id") to model.optString("display_name", model.getString("id"))
            }
            afterId = if (page.optBoolean("has_more")) page.optString("last_id").ifEmpty { null } else null
        } while (afterId != null)
        return models
    }

    private fun send(path: String, method: String, body: String?, beta: String?, timeoutMillis: Int, retryOnce: Boolean): JSONObject {
        try {
            val connection = URI("$BASE_URL/$path").toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = timeoutMillis
                connection.setRequestProperty("x-api-key", apiKey)
                connection.setRequestProperty("anthropic-version", API_VERSION)
                connection.setRequestProperty("content-type", "application/json")
                beta?.let { connection.setRequestProperty("anthropic-beta", it) }
                if (body != null) {
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
                if (status !in 200..299) {
                    val message = runCatching { JSONObject(text).getJSONObject("error").optString("message") }.getOrNull()
                    throw AnthropicException(AnthropicException.Kind.HTTP, status, message?.ifEmpty { null })
                }
                return JSONObject(text)
            } finally {
                connection.disconnect()
            }
        } catch (error: AnthropicException) {
            if (!retryOnce || !error.isRetryable) throw error
        } catch (error: SocketTimeoutException) {
            throw AnthropicException(AnthropicException.Kind.HTTP, 408, "tempo esgotado")
        } catch (error: IOException) {
            if (!retryOnce) throw AnthropicException(AnthropicException.Kind.HTTP, 0, error.message)
        }
        Thread.sleep(1_000)
        return send(path, method, body, beta, timeoutMillis, retryOnce = false)
    }

    companion object {
        const val BASE_URL = "https://api.anthropic.com/v1"
        const val API_VERSION = "2026-10-21"
        private const val FALLBACK_BETA = "server-side-fallback-2026-07-01"

        /** Valor do cabeçalho `anthropic-beta`, quando a requisição usa um recurso em beta. */
        fun betaHeader(body: JSONObject): String? = if (body.has("fallbacks")) FALLBACK_BETA else null
    }
}
