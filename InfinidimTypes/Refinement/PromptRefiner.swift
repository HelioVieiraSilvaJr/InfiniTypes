import Foundation

struct RefinementResult {
    let text: String
    let modelID: String
    let inputTokens: Int?
    let outputTokens: Int?
}

protocol PromptRefiner {
    func refine(transcript: String, context: DictationContext) async throws -> RefinementResult
}

/// Transforma a transcrição bruta em um prompt de codificação usando o modelo escolhido nas preferências.
final class ClaudeRefiner: PromptRefiner {
    private let settings: AppSettings
    private let systemPrompt: String

    init(settings: AppSettings) {
        self.settings = settings
        let url = Bundle.main.url(forResource: "SystemPrompt", withExtension: "md")
        systemPrompt = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        assert(!systemPrompt.isEmpty, "SystemPrompt.md não foi incluído no bundle")
    }

    func refine(transcript: String, context: DictationContext) async throws -> RefinementResult {
        guard let apiKey = KeychainStore.apiKey() else { throw AnthropicError.missingAPIKey }
        let model = ModelCatalog.model(id: settings.modelID)
        let request = Self.makeRequest(model: model, effort: settings.effort, systemPrompt: systemPrompt,
                                       transcript: transcript, context: context)
        let response = try await AnthropicClient(apiKey: apiKey).createMessage(request)

        switch response.stopReason {
        case "refusal": throw AnthropicError.refusal
        case "max_tokens": throw AnthropicError.truncated
        default: break
        }
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AnthropicError.emptyResponse }
        return RefinementResult(text: text, modelID: model.id,
                                inputTokens: response.usage?.inputTokens, outputTokens: response.usage?.outputTokens)
    }

    static func makeRequest(model: RefinementModel, effort: Effort, systemPrompt: String,
                            transcript: String, context: DictationContext) -> AnthropicClient.MessageRequest {
        AnthropicClient.MessageRequest(
            model: model.id,
            // O raciocínio também conta neste limite; o prompt final costuma ter poucas centenas de tokens.
            maxTokens: 16_000,
            system: [.init(text: systemPrompt, cacheControl: .init())],
            messages: [.init(role: "user", content: userMessage(transcript: transcript, context: context))],
            outputConfig: model.supportsEffort ? .init(effort: effort.rawValue) : nil,
            fallbacks: model.supportsServerFallback ? "default" : nil
        )
    }

    static func userMessage(transcript: String, context: DictationContext) -> String {
        var lines: [String] = []
        if let app = context.appName { lines.append("App: \(app)") }
        if let title = context.windowTitle { lines.append("Janela: \(title)") }
        let contextBlock = lines.isEmpty ? "(desconhecido)" : lines.joined(separator: "\n")
        return """
        <contexto>
        \(contextBlock)
        </contexto>

        <transcricao>
        \(transcript)
        </transcricao>
        """
    }
}
