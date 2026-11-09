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

// Detector de segredos, filtro de alucinações, escolha do projeto, revisão e requisições:
// casos em `shared/conformance/`, testados em ConformanceTests.swift.

struct BundledPromptTests {
    @Test(arguments: zip(["SystemPrompt", "LiteralPrompt", "RevisionPrompt", "RevisionFormatEdits", "RevisionFormatFullText"],
                         ["<transcricao>", "<transcricao>", "{{formato}}", "`original`", "texto completo"]))
    func promptsAreBundled(_ resource: String, marker: String) throws {
        let url = try #require(Bundle.main.url(forResource: resource, withExtension: "md"))
        #expect(try String(contentsOf: url, encoding: .utf8).contains(marker))
    }

    @Test func revisionPromptTakesTheFormatInstructions() {
        let prompt = ClaudeRefiner.revisionPrompt(template: "Regras.\n\n{{formato}}\n", instructions: "\nResponda em JSON.\n")
        #expect(prompt == "Regras.\n\nResponda em JSON.\n")
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

    @Test func doubleTapOnRightCommandStartsHandsFreeUntilTheNextTap() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0)
        _ = logic.flagsChanged(keyCode: 54, flags: [], time: 0.1)
        #expect(logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0.3) == .handsFree)
        // Soltar a tecla não termina, e digitar no meio da fala também não.
        #expect(logic.flagsChanged(keyCode: 54, flags: [], time: 0.4) == nil)
        #expect(logic.keyDown(keyCode: 0) == nil)
        // ⌘C com o ⌘ direito também não.
        #expect(logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 2) == nil)
        #expect(logic.keyDown(keyCode: 8) == nil)
        #expect(logic.flagsChanged(keyCode: 54, flags: [], time: 2.2) == nil)
        #expect(logic.handsFree)
        // Um toque isolado termina.
        #expect(logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 5) == nil)
        #expect(logic.flagsChanged(keyCode: 54, flags: [], time: 5.1) == .release)
        #expect(!logic.handsFree)
    }

    @Test func escapeCancelsHandsFree() {
        var logic = HotkeyLogic()
        _ = logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0)
        _ = logic.flagsChanged(keyCode: 54, flags: [], time: 0.1)
        _ = logic.flagsChanged(keyCode: 54, flags: rightCommand, time: 0.3)
        _ = logic.flagsChanged(keyCode: 54, flags: [], time: 0.4)
        #expect(logic.keyDown(keyCode: 53) == .cancel)
        #expect(logic.flagsChanged(keyCode: 61, flags: rightOption, time: 2) == .press(.prompt))
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
