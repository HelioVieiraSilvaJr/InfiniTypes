import Foundation
import Observation

/// Modelo da Anthropic que pode fazer o refinamento.
nonisolated struct RefinementModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    /// Preço em US$ por milhão de tokens; `nil` para modelos que o app não conhece.
    let pricing: Pricing?
    /// Aceita `output_config.effort`. Modelos desconhecidos recebem a requisição mínima, sem ele.
    let supportsEffort: Bool
    /// Aceita `fallbacks: "default"` (nova tentativa do lado do servidor quando o modelo recusa).
    let supportsServerFallback: Bool

    struct Pricing: Hashable, Sendable {
        let input: Double
        let output: Double
    }

    var priceLabel: String? {
        guard let pricing else { return nil }
        return "US$ \(Self.format(pricing.input)) / \(Self.format(pricing.output)) por milhão de tokens"
    }

    /// "4", "0,10": centavos só quando o preço não é inteiro.
    private static func format(_ price: Double) -> String {
        let digits = price.rounded() == price ? 0 : 2
        return price.formatted(.number.precision(.fractionLength(digits)).locale(Locale(identifier: "pt_BR")))
    }
}

enum ModelCatalog {
    static let defaultModelID = "claude-opus-5-5"

    /// Modelos atuais da Anthropic, para os quais o app monta a requisição completa.
    static let known: [RefinementModel] = [
        RefinementModel(id: "claude-opus-5-5", displayName: "Claude Opus 5.5",
                        pricing: .init(input: 4, output: 20), supportsEffort: true, supportsServerFallback: true),
        RefinementModel(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5",
                        pricing: .init(input: 2, output: 10), supportsEffort: true, supportsServerFallback: true),
        RefinementModel(id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5",
                        pricing: .init(input: 0.10, output: 0.50), supportsEffort: true, supportsServerFallback: false),
        RefinementModel(id: "claude-fable-5-1", displayName: "Claude Fable 5.1",
                        pricing: .init(input: 10, output: 50), supportsEffort: true, supportsServerFallback: true),
    ]

    static func model(id: String) -> RefinementModel {
        known.first { $0.id == id }
            ?? RefinementModel(id: id, displayName: id, pricing: nil, supportsEffort: false, supportsServerFallback: false)
    }

    /// Modelos conhecidos primeiro, seguidos dos demais que a Models API devolveu para a conta.
    static func merge(available: [AnthropicClient.ModelInfo]) -> [RefinementModel] {
        let knownIDs = Set(known.map(\.id))
        let others = available
            .filter { !knownIDs.contains($0.id) }
            .map { RefinementModel(id: $0.id, displayName: $0.displayName, pricing: nil,
                                   supportsEffort: false, supportsServerFallback: false) }
        return known + others
    }
}

/// Lista de modelos exibida nas preferências e no menu.
@Observable
final class AvailableModels {
    private(set) var models: [RefinementModel] = ModelCatalog.known
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// Quantos modelos a conta tem, segundo a última consulta à Models API.
    private(set) var accountModelCount: Int?

    func refresh() async {
        guard let apiKey = KeychainStore.apiKey() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let available = try await AnthropicClient(apiKey: apiKey).listModels()
            models = ModelCatalog.merge(available: available)
            accountModelCount = available.count
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
