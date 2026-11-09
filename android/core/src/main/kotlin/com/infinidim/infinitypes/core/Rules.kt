package com.infinidim.infinitypes.core

import java.text.Normalizer

/** O que o refinamento faz com a fala. */
enum class DictationMode(val rawValue: String, val label: String, val systemPromptResource: String) {
    /** Reorganiza a fala em um prompt estruturado para a IA de codificação. */
    PROMPT("prompt", "Prompt", "SystemPrompt"),

    /** Só limpa: tira vícios e resolve autocorreções, mantendo a ordem e as palavras. */
    LITERAL("literal", "Literal", "LiteralPrompt"),

    /** Incorpora a fala ao texto selecionado. */
    REVISION("revision", "Revisão", "RevisionPrompt");

    companion object {
        fun parse(raw: String?): DictationMode = entries.firstOrNull { it.rawValue == raw } ?: PROMPT
    }
}

/** Onde o ditado aconteceu: o app e, quando escolhido, o projeto do glossário. */
data class DictationContext(
    val appName: String? = null,
    val appId: String? = null,
    val windowTitle: String? = null,
    val projectName: String? = null,
) {
    companion object {
        val EMPTY = DictationContext()
    }
}

/** Procura chaves e segredos conhecidos antes de mandar um texto selecionado para a API. */
object SecretScanner {
    private val patterns = listOf(
        "chave da Anthropic" to Regex("""sk-ant-[A-Za-z0-9_\-]{20,}"""),
        // Sem o `(?!ant-)`, toda chave da Anthropic também seria apontada como da OpenAI.
        "chave da OpenAI" to Regex("""sk-(?!ant-)(?:proj-)?[A-Za-z0-9_\-]{32,}"""),
        "chave da AWS" to Regex("""\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"""),
        "token do GitHub" to Regex("""\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})"""),
        "token do Slack" to Regex("""\bxox[abprs]-[A-Za-z0-9\-]{10,}"""),
        "chave do Google" to Regex("""\bAIza[0-9A-Za-z_\-]{35}\b"""),
        "chave do Stripe" to Regex("""\b(?:sk|rk)_live_[0-9A-Za-z]{20,}"""),
        "chave privada" to Regex("""-----BEGIN [A-Z ]*PRIVATE KEY-----"""),
        "token JWT" to Regex("""\beyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"""),
        // Sem `\b` antes do nome: em DATABASE_PASSWORD, o "_" não marca fronteira de palavra.
        "senha ou token em configuração" to
            Regex("""(?i)(?:password|passwd|senha|secret|api[_\-]?key|access[_\-]?token)\s*[:=]\s*["']?[^\s"'`]{8,}"""),
    )

    /** Os tipos de segredo encontrados, sem repetir. */
    fun findings(text: String): List<String> = patterns.filter { it.second.containsMatchIn(text) }.map { it.first }
}

/**
 * Remove frases que o reconhecimento inventa em trechos de silêncio, comuns em português
 * por causa das legendas usadas no treino do Whisper.
 */
object HallucinationFilter {
    /** Frases que, sozinhas, quase sempre são alucinação. */
    private val standalonePhrases = setOf(
        "obrigado", "obrigada", "obrigado por assistir", "obrigada por assistir", "muito obrigado",
        "tchau", "tchau tchau", "até a próxima", "até o próximo vídeo", "inscreva-se", "inscreva-se no canal",
        "deixe seu like", "e aí", "música", "legendas pela comunidade amara.org",
        // Mesmo com o idioma fixo em português, às vezes saem as alucinações clássicas em inglês.
        "thank you", "thanks for watching", "you",
    )

    /** Créditos de legenda removidos mesmo no meio de uma fala real. */
    private val embeddedPhrases = listOf(
        "legendas pela comunidade amara.org",
        "subtítulos realizados por la comunidad de amara.org",
        "sous-titres réalisés par la communauté d'amara.org",
        "legenda adriana zanotto",
    )

    private val brackets = Regex("""\[[^\]]*]""")
    private val repeatedSpaces = Regex("""\s{2,}""")

    /** Recebe os nomes das regras aplicadas, nunca o texto ditado. */
    var log: ((String) -> Unit)? = null

    fun clean(text: String): String {
        val removed = mutableListOf<String>()

        // Marcações de trechos sem fala, como "[Música]" ou "[BLANK_AUDIO]".
        var cleaned = brackets.replace(text, "")
        if (cleaned != text) removed += "marcação entre colchetes"

        for (phrase in embeddedPhrases) {
            if (!cleaned.contains(phrase, ignoreCase = true)) continue
            cleaned = cleaned.replace(phrase, "", ignoreCase = true)
            removed += "crédito de legenda"
        }
        cleaned = repeatedSpaces.replace(cleaned, " ").trim()

        val normalized = cleaned.lowercase().trim { it.isWhitespace() || isPunctuation(it) }
        if (normalized.isNotEmpty() && normalized in standalonePhrases) {
            removed += "frase isolada “$normalized”"
            cleaned = ""
        }

        if (removed.isNotEmpty()) log?.invoke("Filtro de alucinações: ${removed.joinToString(", ")}")
        return if (normalized.isEmpty()) "" else cleaned
    }

    private fun isPunctuation(char: Char) = when (Character.getType(char).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }
}

/** Termos com a grafia correta, que ajudam o reconhecimento e o Claude a corrigir. */
data class Glossary(
    /** Um termo por linha. Guardado como texto para a edição livre nas preferências. */
    val globalTerms: String = "",
    val projects: List<GlossaryProject> = emptyList(),
) {
    /** Termos globais mais os do projeto cujo nome aparece no título (no Android, o projeto escolhido). */
    fun match(windowTitle: String?): GlossaryMatch {
        val project = windowTitle?.let { title ->
            projects
                .filter { it.name.isNotBlank() }
                // O nome mais longo vence, para "api-admin" não ser confundido com "api".
                .sortedByDescending { it.name.trim().length }
                .firstOrNull { fold(title).contains(fold(it.name.trim())) }
        }
        val seen = mutableSetOf<String>()
        val terms = (lines(globalTerms) + lines(project?.terms.orEmpty())).filter { seen.add(it.lowercase()) }
        return GlossaryMatch(project?.name?.trim(), terms)
    }

    companion object {
        fun lines(text: String): List<String> = text.lines().map { it.trim() }.filter { it.isNotEmpty() }

        /** Sem acentos e em minúsculas, para "configuracao" achar "configuração". */
        private fun fold(text: String): String =
            Normalizer.normalize(text, Normalizer.Form.NFD).replace(Regex("""\p{Mn}+"""), "").lowercase()
    }
}

data class GlossaryProject(val name: String = "", val terms: String = "")

data class GlossaryMatch(val projectName: String?, val terms: List<String>)
