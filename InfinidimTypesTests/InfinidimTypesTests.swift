import Foundation
import Testing
@testable import InfinidimTypes

struct HallucinationFilterTests {
    @Test(arguments: ["Obrigado.", "  obrigada!  ", "[Música]", "[BLANK_AUDIO]", "Legendas pela comunidade Amara.org", ""])
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

    @Test func systemPromptIsBundled() throws {
        let url = try #require(Bundle.main.url(forResource: "SystemPrompt", withExtension: "md"))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("<transcricao>"))
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
