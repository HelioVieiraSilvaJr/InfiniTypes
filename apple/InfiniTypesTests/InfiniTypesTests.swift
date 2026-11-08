import AppKit
import Testing
@testable import InfiniTypes

struct EvalExporterTests {
    @Test func writesOneSortedLinePerCaseWithSnakeCaseKeys() throws {
        let newer = EvalCase(id: "2026-11-06T14:25:16Z", mode: "revision", app: "Pages", windowTitle: nil,
                             project: nil, rawTranscript: "adicione a ordem", originalText: "- Darth Vader",
                             deliveredText: "- Darth Vader (1)", modelID: "claude-sonnet-5-5", refined: true)
        var older = newer
        older.id = "2026-11-06T13:02:57Z"
        older.mode = "prompt"
        older.originalText = nil

        let lines = try EvalExporter.jsonl([newer, older]).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("\"id\":\"2026-11-06T13:02:57Z\""))
        #expect(lines[1].contains("\"original_text\":\"- Darth Vader\""))
        #expect(lines[1].contains("\"raw_transcript\":\"adicione a ordem\""))
        let decoded = try JSONDecoder().decode(EvalCase.self, from: Data(lines[1].utf8))
        #expect(decoded == newer)
    }
}

struct HallucinationFilterTests {
    @Test(arguments: ["Obrigado.", "  obrigada!  ", "[Música]", "[BLANK_AUDIO]", "Legendas pela comunidade Amara.org",
                      "Obrigado por assistir!", "Thank you.", "", "...",
                      "Sous-titres réalisés par la communauté d'Amara.org"])
    func removesKnownHallucinations(_ text: String) {
        #expect(HallucinationFilter.clean(text) == "")
    }

    @Test func stripsSubtitleCreditsFromRealSpeech() {
        let text = "Crie um endpoint de login. Legendas pela comunidade Amara.org"
        #expect(HallucinationFilter.clean(text) == "Crie um endpoint de login.")
    }

    @Test func keepsRealSpeech() {
        let speech = "Refatore o serviço de pagamentos e obrigado pela ajuda"
        #expect(HallucinationFilter.clean(speech) == speech)
    }
}

struct RefinementRequestTests {
    private let context = DictationContext(appName: "Terminal", bundleID: "com.apple.Terminal", windowTitle: "api — zsh")

    private func body(for modelID: String, effort: Effort = .low) throws -> [String: Any] {
        let request = ClaudeRefiner.makeRequest(model: ModelCatalog.model(id: modelID), effort: effort,
                                                systemPrompt: "SISTEMA", transcript: "crie um teste", context: context)
        let data = try AnthropicClient.encoder.encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func opusUsesEffortCacheAndServerFallback() throws {
        let json = try body(for: "claude-opus-5-5")
        #expect(json["model"] as? String == "claude-opus-5-5")
        #expect(json["max_tokens"] as? Int == 16_000)
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(json["fallbacks"] as? String == "default")
        let system = try #require((json["system"] as? [[String: Any]])?.first)
        #expect(system["type"] as? String == "text")
        #expect(system["text"] as? String == "SISTEMA")
        #expect((system["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
    }

    @Test func haikuHasNoServerFallback() throws {
        let json = try body(for: "claude-haiku-5-5", effort: .medium)
        #expect(json["fallbacks"] == nil)
        #expect((json["output_config"] as? [String: Any])?["effort"] as? String == "medium")
    }

    @Test func unknownModelGetsMinimalRequest() throws {
        let json = try body(for: "claude-modelo-futuro")
        #expect(json["output_config"] == nil)
        #expect(json["fallbacks"] == nil)
        #expect(json["thinking"] == nil)
        #expect(json["temperature"] == nil)
    }

    @Test func userMessageWrapsContextAndTranscript() {
        let message = ClaudeRefiner.userMessage(
            transcript: "crie um teste",
            context: DictationContext(appName: "Cursor", bundleID: nil, windowTitle: "auth.ts — api")
        )
        #expect(message.contains("<contexto>\nApp: Cursor\nJanela: auth.ts — api\n</contexto>"))
        #expect(message.contains("<transcricao>\ncrie um teste\n</transcricao>"))
    }

    @Test(arguments: [DictationMode.prompt, .literal, .revision])
    func systemPromptsAreBundled(_ mode: DictationMode) throws {
        let url = try #require(Bundle.main.url(forResource: mode.systemPromptResource, withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(mode == .revision ? "{{formato}}" : "<transcricao>"))
    }

    @Test func userMessageCarriesProjectAndGlossary() {
        let message = ClaudeRefiner.userMessage(
            transcript: "use o supa base",
            context: DictationContext(appName: "Cursor", windowTitle: "db.ts — minha-api", projectName: "minha-api"),
            vocabulary: ["Supabase", "Drizzle"]
        )
        #expect(message.contains("Projeto: minha-api"))
        #expect(message.contains("<glossario>\nSupabase\nDrizzle\n</glossario>"))
        #expect(!ClaudeRefiner.userMessage(transcript: "x", context: .empty).contains("<glossario>"))
    }

    private func revisionBody(for modelID: String, format: ClaudeRefiner.RevisionFormat) throws -> [String: Any] {
        let request = ClaudeRefiner.makeRevisionRequest(
            model: ModelCatalog.model(id: modelID), effort: .low, template: "Regras.\n\n{{formato}}", format: format,
            selection: "Crie um endpoint.", dictation: "valide com zod", context: .empty, vocabulary: []
        )
        let data = try AnthropicClient.encoder.encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func revisionAsksForStructuredEdits() throws {
        let json = try revisionBody(for: "claude-sonnet-5-5", format: .edits)
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        #expect(outputConfig["effort"] as? String == "low")
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        // O esquema mantém as chaves em camelCase.
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)

        let system = try #require((json["system"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(system.contains("`original`"))
        #expect(!system.contains("{{formato}}"))
        let message = try #require((json["messages"] as? [[String: Any]])?.first?["content"] as? String)
        #expect(message.contains("<texto_original>\nCrie um endpoint.\n</texto_original>"))
        #expect(message.contains("<fala>\nvalide com zod\n</fala>"))
    }

    @Test func revisionFallbackAsksForFullText() throws {
        let json = try revisionBody(for: "claude-opus-5-5", format: .fullText)
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        #expect(outputConfig["format"] == nil)
        let system = try #require((json["system"] as? [[String: Any]])?.first?["text"] as? String)
        #expect(system.contains("texto completo já revisado"))
    }

    @Test func unknownModelRevisionHasNoOutputConfig() throws {
        let json = try revisionBody(for: "claude-modelo-futuro", format: .fullText)
        #expect(json["output_config"] == nil)
    }
}

struct RevisionPatcherTests {
    private let original = """
    Crie um endpoint de login em `auth.routes.ts`.

    - Recebe e-mail e senha.
    - Retorna um JWT.
    """

    @Test func appliesEditsAndKeepsTheRestIntact() throws {
        let revised = try RevisionPatcher.apply([
            .init(original: "- Retorna um JWT.", revised: "- Retorna um JWT com expiração de 15 minutos.\n- Inclua testes."),
            .init(original: "e-mail e senha", revised: "e-mail ou nome de usuário, e senha"),
        ], to: original)
        #expect(revised == """
        Crie um endpoint de login em `auth.routes.ts`.

        - Recebe e-mail ou nome de usuário, e senha.
        - Retorna um JWT com expiração de 15 minutos.
        - Inclua testes.
        """)
    }

    @Test func noEditsKeepsTheText() throws {
        #expect(try RevisionPatcher.apply([], to: original) == original)
    }

    @Test func rejectsEditsThatDoNotMatchExactly() {
        #expect(throws: RevisionPatcher.Failure.notFound("Retorna um token")) {
            try RevisionPatcher.apply([.init(original: "Retorna um token", revised: "x")], to: original)
        }
        #expect(throws: RevisionPatcher.Failure.ambiguous("- R")) {
            try RevisionPatcher.apply([.init(original: "- R", revised: "x")], to: original)
        }
        #expect(throws: RevisionPatcher.Failure.overlapping) {
            try RevisionPatcher.apply([
                .init(original: "e-mail e senha", revised: "a"),
                .init(original: "senha.", revised: "b"),
            ], to: original)
        }
    }
}

struct SecretScannerTests {
    // Chaves falsas montadas por partes, para não disparar os detectores de segredos do GitHub e afins.
    @Test(arguments: [
        "export ANTHROPIC_API_KEY=" + "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz012345",
        "aws_access_key_id = " + "AKIA" + "IOSFODNN7EXAMPLE",
        "token: " + "ghp_" + "abcdefghijklmnopqrstuvwxyz0123456789",
        "-----BEGIN OPENSSH " + "PRIVATE KEY-----",
        "DATABASE_PASSWORD=\"hunter2hunter2\"",
        "Authorization: Bearer " + "eyJhbGciOiJIUzI1NiJ9." + "eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
    ])
    func detectsSecrets(_ text: String) {
        #expect(!SecretScanner.findings(in: text).isEmpty)
    }

    @Test func ignoresOrdinaryPrompts() {
        let prompt = "Leia a variável ANTHROPIC_API_KEY do ambiente e valide o token JWT recebido no header."
        #expect(SecretScanner.findings(in: prompt).isEmpty)
    }
}

struct GlossaryTests {
    private let glossary = Glossary(
        globalTerms: "Supabase\nuseEffect\n\n",
        projects: [
            .init(name: "api", terms: "Fastify"),
            .init(name: "api-admin", terms: "Prisma\nsupabase"),
        ]
    )

    @Test func longestMatchingProjectWins() {
        let match = glossary.match(windowTitle: "users.ts — API-Admin — Cursor")
        #expect(match.projectName == "api-admin")
        #expect(match.terms == ["Supabase", "useEffect", "Prisma"])
    }

    @Test func withoutProjectOnlyGlobalTerms() {
        #expect(glossary.match(windowTitle: "Notas").terms == ["Supabase", "useEffect"])
        #expect(glossary.match(windowTitle: nil).projectName == nil)
    }
}

struct HotkeyLogicTests {
    private let rightOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x40)
    private let leftOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)
    private let rightCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 0x10)

    @Test func holdingRightOptionDictatesAPrompt() {
        var logic = HotkeyLogic()
        #expect(logic.flagsChanged(keyCode: 61, flags: rightOption, time: 0) == .press(.prompt))
        #expect(logic.flagsChanged(keyCode: 61, flags: [], time: 3) == .release)
    }

    @Test func holdingRightCommandDictatesLiterally() {
        var logic = HotkeyLogic()
        #expect(logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0) == .press(.literal))
    }

    @Test func anotherKeyCancels() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0)
        #expect(logic.keyDown() == .cancel)
        #expect(logic.flagsChanged(keyCode: 54, flags: [], time: 0.1) == nil)
    }

    @Test func leftOptionIsIgnored() {
        var logic = HotkeyLogic()
        #expect(logic.flagsChanged(keyCode: 58, flags: leftOption, time: 0) == nil)
    }

    @Test func tapThenHoldRevisesTheSelection() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 61, flags: rightOption, time: 0)
        _ = logic.flagsChanged(keyCode: 61, flags: [], time: 0.15)
        #expect(logic.flagsChanged(keyCode: 61, flags: rightOption, time: 0.35) == .press(.revision))
    }

    @Test func slowSecondPressIsAPrompt() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 61, flags: rightOption, time: 0)
        _ = logic.flagsChanged(keyCode: 61, flags: [], time: 0.15)
        #expect(logic.flagsChanged(keyCode: 61, flags: rightOption, time: 1.0) == .press(.prompt))
    }

    @Test func longFirstHoldIsNotATap() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 61, flags: rightOption, time: 0)
        _ = logic.flagsChanged(keyCode: 61, flags: [], time: 2)
        #expect(logic.flagsChanged(keyCode: 61, flags: rightOption, time: 2.2) == .press(.prompt))
    }
}

struct ModelCatalogTests {
    @Test func mergeKeepsKnownModelsFirstWithoutDuplicates() {
        let merged = ModelCatalog.merge(available: [
            .init(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5"),
            .init(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
        ])
        #expect(merged.prefix(ModelCatalog.known.count).map(\.id) == ModelCatalog.known.map(\.id))
        #expect(merged.count == ModelCatalog.known.count + 1)
        #expect(merged.last?.id == "claude-haiku-4-5")
        #expect(merged.last?.supportsEffort == false)
    }

    @Test func priceLabelUsesBrazilianFormat() {
        #expect(ModelCatalog.model(id: "claude-opus-5-5").priceLabel == "US$ 4 / 20 por milhão de tokens")
        #expect(ModelCatalog.model(id: "claude-haiku-5-5").priceLabel == "US$ 0,10 / 0,50 por milhão de tokens")
        #expect(ModelCatalog.model(id: "claude-desconhecido").priceLabel == nil)
    }

    @Test func retriesOnlyTransientErrors() {
        #expect(AnthropicError.http(status: 429, type: nil, message: nil).isRetryable)
        #expect(AnthropicError.http(status: 529, type: nil, message: nil).isRetryable)
        #expect(!AnthropicError.http(status: 401, type: nil, message: nil).isRetryable)
        #expect(!AnthropicError.refusal.isRetryable)
    }
}

struct FocusDetectorTests {
    @Test func terminalsAreAlwaysEditableButNeverReplaceSelections() {
        #expect(FocusDetector.terminalBundleIDs.contains("com.apple.Terminal"))
        #expect(FocusDetector.terminalBundleIDs.isSubset(of: FocusDetector.alwaysEditableBundleIDs))
        #expect(!FocusDetector.terminalBundleIDs.contains("com.microsoft.VSCode"))
    }

    @Test func classifiesFocusedElements() {
        #expect(FocusDetector.classify(role: "AXTextArea", hasTextSelection: false, bundleID: "com.apple.Notes") == .editable)
        #expect(FocusDetector.classify(role: "AXGroup", hasTextSelection: true, bundleID: "com.google.Chrome") == .editable)
        #expect(FocusDetector.classify(role: nil, hasTextSelection: false, bundleID: nil) == .unknown)
    }

    @Test func discardsPasteOnlyWhereThereIsNowhereToType() {
        // Área de trabalho e listas do Finder.
        #expect(FocusDetector.classify(role: "AXList", hasTextSelection: false, bundleID: "com.apple.finder") == .notEditable)
        // Renomear um arquivo no Finder é um campo de texto.
        #expect(FocusDetector.classify(role: "AXTextField", hasTextSelection: true, bundleID: "com.apple.finder") == .editable)
        // O Pages informa o documento como área de rolagem.
        #expect(FocusDetector.classify(role: "AXScrollArea", hasTextSelection: false, bundleID: "com.apple.iWork.Pages") == .unknown)
    }
}

struct DayGroupingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    private func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func groupsByDayNewestFirst() {
        let items = [date(11, 6, 9), date(10, 31, 8), date(11, 6, 14), date(11, 5, 22)]
        let sections = DayGrouping.sections(items, date: { $0 }, calendar: calendar, now: date(11, 6, 15))
        #expect(sections.map(\.title) == ["Hoje", "Ontem", "31 de outubro de 2026"])
        #expect(sections[0].items == [date(11, 6, 14), date(11, 6, 9)])
    }
}
