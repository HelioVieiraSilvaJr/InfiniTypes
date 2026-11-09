import AppIntents
import Observation

/// Modo do ditado nos Atalhos, no Botão de Ação e na Central de Controle.
nonisolated enum DictationTrigger: String, AppEnum {
    case prompt, literal, revision

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modo"
    static let caseDisplayRepresentations: [DictationTrigger: DisplayRepresentation] = [
        .prompt: "Prompt",
        .literal: "Literal",
        .revision: "Revisão",
    ]
}

/// Abre o app já gravando. Compilado também na extensão dos controles, que só dispara a intenção.
struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Ditar no InfiniTypes"
    static let description = IntentDescription("Abre o InfiniTypes e começa a gravar. Toque em parar e o resultado vai para a área de transferência.")
    // A gravação precisa do app em primeiro plano.
    static let openAppWhenRun = true

    @Parameter(title: "Modo", default: .prompt)
    var mode: DictationTrigger

    init() {}

    init(mode: DictationTrigger) {
        self.mode = mode
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingDictation.shared.request(mode)
        return .result()
    }
}

/// Pedido de ditado vindo de fora do app, lido pela tela de ditado quando ela aparece.
@MainActor
@Observable
final class PendingDictation {
    static let shared = PendingDictation()

    private(set) var mode: DictationTrigger?

    func request(_ mode: DictationTrigger) {
        self.mode = mode
    }

    func take() -> DictationTrigger? {
        defer { mode = nil }
        return mode
    }
}
