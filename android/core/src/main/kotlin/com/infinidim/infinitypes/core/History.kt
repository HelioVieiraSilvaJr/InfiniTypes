package com.infinidim.infinitypes.core

import org.json.JSONObject
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Um ditado salvo no histórico. */
data class DictationRecord(
    val id: Long = 0,
    val createdAt: Long = System.currentTimeMillis(),
    /** Texto entregue: o prompt refinado ou, se o refinamento falhou, a transcrição bruta. */
    val text: String,
    val rawTranscript: String,
    val appName: String? = null,
    val appId: String? = null,
    val projectName: String? = null,
    val mode: DictationMode,
    /** Na revisão: o texto que estava selecionado antes de ser substituído. */
    val originalText: String? = null,
    val modelId: String? = null,
    val refined: Boolean,
    val pasted: Boolean = false,
    val errorMessage: String? = null,
    val audioSeconds: Double,
    val transcriptionSeconds: Double,
    val refinementSeconds: Double? = null,
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    /** Marcado no histórico para entrar no conjunto de avaliação do refinador. */
    val inEvalSet: Boolean = false,
)

/** Título das seções do histórico: "Hoje", "Ontem" ou a data por extenso. */
object DayGrouping {
    private val longDate = DateTimeFormatter.ofPattern("d 'de' MMMM 'de' yyyy", Locale.forLanguageTag("pt-BR"))

    fun title(day: LocalDate, today: LocalDate): String = when (day) {
        today -> "Hoje"
        today.minusDays(1) -> "Ontem"
        else -> day.format(longDate)
    }
}

/** Ditados marcados no formato do conjunto de avaliação do refinador, igual ao do Mac e do Windows. */
object EvalExporter {
    fun case(record: DictationRecord, id: String): JSONObject = JSONObject()
        .put("id", id)
        .put("mode", record.mode.rawValue)
        .putOpt("app", record.appName)
        .putOpt("project", record.projectName)
        .put("raw_transcript", record.rawTranscript)
        .putOpt("original_text", record.originalText)
        .put("delivered_text", record.text)
        .putOpt("model_id", record.modelId)
        .put("refined", record.refined)

    /** Uma linha JSON por caso, do mais antigo para o mais novo. Cada par traz a data e hora ISO 8601 e o ditado. */
    fun jsonl(records: List<Pair<String, DictationRecord>>): String =
        records.sortedBy { it.first }.joinToString("") { (id, record) -> case(record, id).toString() + "\n" }
}
