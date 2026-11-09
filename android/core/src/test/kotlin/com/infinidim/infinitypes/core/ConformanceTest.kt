package com.infinidim.infinitypes.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** Casos de `shared/conformance/`. Os testes das outras plataformas leem os mesmos arquivos. */
class ConformanceTest {
    private fun file(name: String) = JSONObject(File(System.getProperty("conformance.dir"), "$name.json").readText())

    private fun cases(name: String): List<JSONObject> = file(name).getJSONArray("cases").let { array ->
        (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun strings(array: JSONArray): List<String> = (0 until array.length()).map { array.getString(it) }

    private fun JSONObject.optionalString(key: String): String? = if (isNull(key)) null else optString(key)

    @Test
    fun findsTheSameSecrets() = cases("secrets").forEach { case ->
        // Pedaços juntados sem separador: assim as chaves falsas não disparam os detectores de segredos.
        val text = strings(case.getJSONArray("text")).joinToString("")
        assertEquals(case.getString("name"), strings(case.getJSONArray("findings")), SecretScanner.findings(text))
    }

    @Test
    fun cleansTheSameWay() = cases("hallucinations").forEach { case ->
        assertEquals(case.getString("name"), case.getString("output"), HallucinationFilter.clean(case.getString("input")))
    }

    @Test
    fun picksTheSameProject() {
        val input = file("projects").getJSONObject("glossary")
        val projects = input.getJSONArray("projects")
        val glossary = Glossary(
            input.getString("global_terms"),
            (0 until projects.length()).map { projects.getJSONObject(it).let { p -> GlossaryProject(p.getString("name"), p.getString("terms")) } },
        )
        cases("projects").forEach { case ->
            val match = glossary.match(case.optionalString("window_title"))
            assertEquals(case.getString("name"), case.optionalString("project"), match.projectName)
            assertEquals(case.getString("name"), strings(case.getJSONArray("terms")), match.terms)
        }
    }

    @Test
    fun appliesTheSameEdits() = cases("revision-edits").forEach { case ->
        val name = case.getString("name")
        val edits = case.getJSONArray("edits").let { array ->
            (0 until array.length()).map { array.getJSONObject(it).let { e -> RevisionEdit(e.getString("original"), e.getString("revised")) } }
        }
        val error = case.optionalString("error")
        try {
            val revised = RevisionPatcher.apply(edits, case.getString("text"))
            if (error != null) fail("$name: deveria falhar com $error")
            assertEquals(name, case.getString("result"), revised)
        } catch (failure: RevisionPatchException) {
            assertEquals(name, error, failure.error.name.lowercase())
        }
    }

    @Test
    fun usesTheSameEndpointAndVersion() {
        val api = file("requests").getJSONObject("api")
        assertEquals("${AnthropicClient.BASE_URL}/messages", api.getString("messages_url"))
        assertEquals(AnthropicClient.API_VERSION, api.getString("anthropic_version"))
    }

    @Test
    fun buildsTheSameRequest() = cases("requests").forEach { case ->
        val name = case.getString("name")
        val contextJson = case.getJSONObject("context")
        val context = DictationContext(
            appName = contextJson.optionalString("app"),
            windowTitle = contextJson.optionalString("window_title"),
            projectName = contextJson.optionalString("project"),
        )
        val model = ModelCatalog.model(case.getString("model"))
        val effort = Effort.parse(case.getString("effort"))
        val vocabulary = strings(case.getJSONArray("vocabulary"))
        val request = when (case.getString("kind")) {
            "refinement" -> ClaudeRefiner.makeRequest(model, effort, case.getString("system_prompt"), case.getString("transcript"),
                context, vocabulary)
            "revision" -> ClaudeRefiner.makeRevisionRequest(model, effort, case.getString("system_prompt"),
                if (case.getString("format") == "edits") RevisionFormat.EDITS else RevisionFormat.FULL_TEXT,
                case.getString("selection"), case.getString("transcript"), context, vocabulary)
            else -> error("tipo de caso desconhecido")
        }
        val expected = case.getJSONObject("expected_body")
        assertTrue("$name\nesperado: $expected\nrecebido: ${request.body}", expected.similar(JSONObject(request.body.toString())))
        assertEquals(name, case.optionalString("expected_beta"), request.betaHeader)
    }
}

class CoreTest {
    @Test
    fun priceLabelUsesBrazilianFormat() {
        assertEquals("US$ 4 / 20 por milhão de tokens", ModelCatalog.model("claude-opus-5-5").priceLabel)
        assertEquals("US$ 0,10 / 0,50 por milhão de tokens", ModelCatalog.model("claude-haiku-5-5").priceLabel)
        assertNull(ModelCatalog.model("claude-desconhecido").priceLabel)
    }

    @Test
    fun mergeKeepsKnownModelsFirstWithoutDuplicates() {
        val merged = ModelCatalog.merge(listOf("claude-sonnet-5-5" to "Claude Sonnet 5.5", "claude-haiku-4-5" to "Claude Haiku 4.5"))
        assertEquals(ModelCatalog.known.map { it.id }, merged.take(ModelCatalog.known.size).map { it.id })
        assertEquals(ModelCatalog.known.size + 1, merged.size)
        assertEquals("claude-haiku-4-5", merged.last().id)
    }

    @Test
    fun promptsAreBundled() {
        mapOf(
            "SystemPrompt" to "<transcricao>", "LiteralPrompt" to "<transcricao>", "RevisionPrompt" to "{{formato}}",
            "RevisionFormatEdits" to "`original`", "RevisionFormatFullText" to "texto completo",
        ).forEach { (resource, marker) -> assertTrue(resource, Prompts.load(resource).contains(marker)) }
        assertEquals("Regras.\n\nResponda em JSON.\n", ClaudeRefiner.revisionPrompt("Regras.\n\n{{formato}}\n", "\nResponda em JSON.\n"))
        ClaudeRefiner({ null }, { ModelCatalog.DEFAULT_MODEL_ID to Effort.LOW })
    }

    @Test
    fun retriesOnlyTransientErrors() {
        assertTrue(AnthropicException(AnthropicException.Kind.HTTP, 429).isRetryable)
        assertTrue(AnthropicException(AnthropicException.Kind.HTTP, 529).isRetryable)
        assertEquals(false, AnthropicException(AnthropicException.Kind.HTTP, 401).isRetryable)
        assertEquals(false, AnthropicException(AnthropicException.Kind.REFUSAL).isRetryable)
    }
}

class HistoryTest {
    @Test
    fun titlesTodayYesterdayAndOlderDays() {
        val today = java.time.LocalDate.of(2026, 11, 6)
        assertEquals("Hoje", DayGrouping.title(today, today))
        assertEquals("Ontem", DayGrouping.title(today.minusDays(1), today))
        assertEquals("31 de outubro de 2026", DayGrouping.title(java.time.LocalDate.of(2026, 10, 31), today))
    }

    @Test
    fun exportsOneSortedLinePerCaseWithSnakeCaseKeys() {
        val newer = DictationRecord(text = "- Darth Vader (1)", rawTranscript = "adicione a ordem", originalText = "- Darth Vader",
            mode = DictationMode.REVISION, modelId = "claude-sonnet-5-5", refined = true, audioSeconds = 2.0, transcriptionSeconds = 1.0)
        val older = newer.copy(mode = DictationMode.PROMPT, originalText = null)
        val lines = EvalExporter.jsonl(listOf("2026-11-06T14:25:16Z" to newer, "2026-11-06T13:02:57Z" to older)).trim().lines()
        assertEquals(2, lines.size)
        assertEquals("2026-11-06T13:02:57Z", JSONObject(lines[0]).getString("id"))
        assertEquals("- Darth Vader", JSONObject(lines[1]).getString("original_text"))
        assertEquals("adicione a ordem", JSONObject(lines[1]).getString("raw_transcript"))
    }
}
