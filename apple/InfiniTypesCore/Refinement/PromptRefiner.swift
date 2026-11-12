import Foundation
import OSLog

struct RefinementResult {
    let text: String
    let modelID: String
    let inputTokens: Int?
    let outputTokens: Int?
}

struct RevisionResult {
    let text: String
    let modelID: String
    /// Quantas alterações foram aplicadas; `nil` quando o modelo reescreveu o texto inteiro.
    let editCount: Int?
    let inputTokens: Int
    let outputTokens: Int
}

protocol PromptRefiner {
    func refine(transcript: String, context: DictationContext, mode: DictationMode,
                vocabulary: [String]) async throws -> RefinementResult

    /// Incorpora a fala ao texto selecionado.
    func revise(selection: String, dictation: String, context: DictationContext,
                vocabulary: [String]) async throws -> RevisionResult
}

/// Transforma a transcrição bruta no texto final usando o modelo escolhido nas preferências.
final class ClaudeRefiner: PromptRefiner {
    enum RevisionFormat: CaseIterable {
        /// Lista de alterações aplicadas localmente: rápida, e o resto do texto fica intacto.
        case edits
        /// Texto completo reescrito, a reserva quando as alterações não casam com o original.
        case fullText

        /// Instruções que entram no lugar de `{{formato}}` no prompt da revisão.
        var instructionsResource: String {
            switch self {
            case .edits: "RevisionFormatEdits"
            case .fullText: "RevisionFormatFullText"
            }
        }
    }

    private let settings: AppSettings
    private let systemPrompts: [DictationMode: String]
    /// Prompt da revisão já com as instruções de cada formato.
    private let revisionPrompts: [RevisionFormat: String]

    init(settings: AppSettings) {
        self.settings = settings
        var prompts: [DictationMode: String] = [:]
        for mode in [DictationMode.prompt, .literal] {
            prompts[mode] = Self.bundledPrompt(mode.systemPromptResource)
        }
        systemPrompts = prompts
        let template = Self.bundledPrompt(DictationMode.revision.systemPromptResource)
        var revision: [RevisionFormat: String] = [:]
        for format in RevisionFormat.allCases {
            revision[format] = Self.revisionPrompt(template: template,
                                                   instructions: Self.bundledPrompt(format.instructionsResource))
        }
        revisionPrompts = revision
    }

    private static func bundledPrompt(_ resource: String) -> String {
        let url = Bundle.main.url(forResource: resource, withExtension: "md")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        assert(text?.isEmpty == false, "\(resource).md não foi incluído no bundle")
        return text ?? ""
    }

    static func revisionPrompt(template: String, instructions: String) -> String {
        template.replacingOccurrences(of: "{{formato}}",
                                      with: instructions.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func refine(transcript: String, context: DictationContext, mode: DictationMode,
                vocabulary: [String]) async throws -> RefinementResult {
        let client = try Self.client()
        let model = ModelCatalog.model(id: settings.modelID)
        let request = Self.makeRequest(model: model, effort: settings.effort, systemPrompt: systemPrompts[mode] ?? "",
                                       transcript: transcript, context: context, vocabulary: vocabulary)
        // Um ditado de 10 minutos rende um prompt longo, e a análise das etapas leva mais tempo.
        let text = try Self.text(of: try await client.createMessage(request, timeout: 120))
        return RefinementResult(text: text.value, modelID: model.id,
                                inputTokens: text.usage.inputTokens, outputTokens: text.usage.outputTokens)
    }

    func revise(selection: String, dictation: String, context: DictationContext,
                vocabulary: [String]) async throws -> RevisionResult {
        let client = try Self.client()
        let model = ModelCatalog.model(id: settings.modelID)
        var inputTokens = 0
        var outputTokens = 0

        if model.supportsEffort {
            let request = Self.makeRevisionRequest(model: model, effort: settings.effort,
                                                   systemPrompt: revisionPrompts[.edits] ?? "", format: .edits,
                                                   selection: selection, dictation: dictation,
                                                   context: context, vocabulary: vocabulary)
            let response = try Self.text(of: try await client.createMessage(request, timeout: 60))
            inputTokens += response.usage.inputTokens ?? 0
            outputTokens += response.usage.outputTokens ?? 0
            do {
                let edits = try JSONDecoder().decode(RevisionPatcher.Response.self, from: Data(response.value.utf8)).edits
                let revised = try RevisionPatcher.apply(edits, to: selection)
                return RevisionResult(text: revised, modelID: model.id, editCount: edits.count,
                                      inputTokens: inputTokens, outputTokens: outputTokens)
            } catch {
                let reason = (error as? RevisionPatcher.Failure)?.reason ?? "resposta fora do esquema"
                Logger.dictation.notice("Alterações não casaram com o original (\(reason, privacy: .public)); reescrevendo o texto inteiro")
            }
        }

        let request = Self.makeRevisionRequest(model: model, effort: settings.effort,
                                               systemPrompt: revisionPrompts[.fullText] ?? "", format: .fullText,
                                               selection: selection, dictation: dictation,
                                               context: context, vocabulary: vocabulary)
        let response = try Self.text(of: try await client.createMessage(request, timeout: 120))
        // A resposta vem sem espaços nas pontas; mantém os da seleção, como uma quebra de linha final.
        let leading = selection.prefix { $0.isWhitespace }
        let trailing = String(selection.reversed().prefix { $0.isWhitespace }.reversed())
        return RevisionResult(text: leading + response.value + trailing, modelID: model.id, editCount: nil,
                              inputTokens: inputTokens + (response.usage.inputTokens ?? 0),
                              outputTokens: outputTokens + (response.usage.outputTokens ?? 0))
    }

    // MARK: Requisições

    static func makeRequest(model: RefinementModel, effort: Effort, systemPrompt: String, transcript: String,
                            context: DictationContext, vocabulary: [String] = []) -> AnthropicClient.MessageRequest {
        AnthropicClient.MessageRequest(
            model: model.id,
            // O raciocínio também conta neste limite; o texto final costuma ter poucas centenas de tokens.
            maxTokens: 16_000,
            system: [.init(text: systemPrompt, cacheControl: .init())],
            messages: [.init(role: "user", content: userMessage(transcript: transcript, context: context,
                                                                vocabulary: vocabulary))],
            outputConfig: model.supportsEffort ? .init(effort: effort.rawValue) : nil,
            fallbacks: model.supportsServerFallback ? "default" : nil
        )
    }

    static func makeRevisionRequest(model: RefinementModel, effort: Effort, systemPrompt: String,
                                    format: RevisionFormat, selection: String, dictation: String,
                                    context: DictationContext, vocabulary: [String]) -> AnthropicClient.MessageRequest {
        var outputConfig: AnthropicClient.MessageRequest.OutputConfig?
        if model.supportsEffort {
            outputConfig = .init(effort: effort.rawValue,
                                 format: format == .edits ? .init(schema: RevisionPatcher.schema) : nil)
        }
        let message = contextBlock(context, vocabulary: vocabulary) + """


        <texto_original>
        \(selection)
        </texto_original>

        <fala>
        \(dictation)
        </fala>
        """
        return AnthropicClient.MessageRequest(
            model: model.id,
            maxTokens: 16_000,
            system: [.init(text: systemPrompt, cacheControl: .init())],
            messages: [.init(role: "user", content: message)],
            outputConfig: outputConfig,
            fallbacks: model.supportsServerFallback ? "default" : nil
        )
    }

    static func userMessage(transcript: String, context: DictationContext, vocabulary: [String] = []) -> String {
        contextBlock(context, vocabulary: vocabulary) + "\n\n<transcricao>\n\(transcript)\n</transcricao>"
    }

    private static func contextBlock(_ context: DictationContext, vocabulary: [String]) -> String {
        var lines: [String] = []
        if let app = context.appName { lines.append("App: \(app)") }
        if let title = context.windowTitle { lines.append("Janela: \(title)") }
        if let project = context.projectName { lines.append("Projeto: \(project)") }
        var block = """
        <contexto>
        \(lines.isEmpty ? "(desconhecido)" : lines.joined(separator: "\n"))
        </contexto>
        """
        if !vocabulary.isEmpty {
            block += "\n\n<glossario>\n\(vocabulary.joined(separator: "\n"))\n</glossario>"
        }
        return block
    }

    // MARK: Respostas

    private static func client() throws -> AnthropicClient {
        guard let apiKey = KeychainStore.apiKey() else { throw AnthropicError.missingAPIKey }
        return AnthropicClient(apiKey: apiKey)
    }

    private static func text(of response: AnthropicClient.MessageResponse)
        throws -> (value: String, usage: AnthropicClient.MessageResponse.Usage) {
        switch response.stopReason {
        case "refusal": throw AnthropicError.refusal
        case "max_tokens": throw AnthropicError.truncated
        default: break
        }
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AnthropicError.emptyResponse }
        return (text, response.usage ?? .init())
    }
}
