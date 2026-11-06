import Foundation

/// Cliente HTTP mínimo da API da Anthropic. Não há SDK oficial em Swift.
struct AnthropicClient {
    let apiKey: String
    var session: URLSession = .shared

    private static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let apiVersion = "2026-10-21"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    // MARK: Messages

    struct MessageRequest: Encodable, Equatable {
        var model: String
        var maxTokens: Int
        var system: [SystemBlock]
        var messages: [Message]
        var outputConfig: OutputConfig?
        /// `"default"`: se o modelo recusar, a API tenta de novo no modelo que a Anthropic recomenda.
        var fallbacks: String?

        struct SystemBlock: Encodable, Equatable {
            var type = "text"
            var text: String
            var cacheControl: CacheControl?
        }

        struct CacheControl: Encodable, Equatable {
            var type = "ephemeral"
        }

        struct Message: Encodable, Equatable {
            var role: String
            var content: String
        }

        struct OutputConfig: Encodable, Equatable {
            var effort: String
        }
    }

    struct MessageResponse: Decodable {
        var content: [ContentBlock]
        var stopReason: String?
        var usage: Usage?

        struct ContentBlock: Decodable {
            var type: String
            var text: String?
        }

        struct Usage: Decodable {
            var inputTokens: Int?
            var outputTokens: Int?
        }

        /// Só os blocos de texto; os de raciocínio (`thinking`) e de fallback ficam de fora.
        var text: String {
            content.filter { $0.type == "text" }.compactMap(\.text).joined()
        }
    }

    func createMessage(_ body: MessageRequest) async throws -> MessageResponse {
        var request = makeRequest(path: "messages", method: "POST")
        request.timeoutInterval = 45
        if body.fallbacks != nil {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try Self.encoder.encode(body)
        return try await send(request, retryingOnce: true)
    }

    // MARK: Models

    struct ModelInfo: Decodable, Sendable {
        var id: String
        var displayName: String
    }

    private struct ModelPage: Decodable {
        var data: [ModelInfo]
        var hasMore: Bool
        var lastId: String?
    }

    func listModels() async throws -> [ModelInfo] {
        var models: [ModelInfo] = []
        var afterID: String?
        repeat {
            var path = "models?limit=100"
            if let afterID { path += "&after_id=\(afterID)" }
            let page: ModelPage = try await send(makeRequest(path: path, method: "GET"), retryingOnce: false)
            models += page.data
            afterID = page.hasMore ? page.lastId : nil
        } while afterID != nil
        return models
    }

    // MARK: Transporte

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(Self.baseURL.absoluteString)/\(path)")!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, retryingOnce: Bool) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = try? Self.decoder.decode(ErrorEnvelope.self, from: data)
                throw AnthropicError.http(status: status, type: body?.error.type, message: body?.error.message)
            }
            return try Self.decoder.decode(T.self, from: data)
        } catch let error as AnthropicError where retryingOnce && error.isRetryable {
            try await Task.sleep(for: .seconds(1))
            return try await send(request, retryingOnce: false)
        }
    }

    private struct ErrorEnvelope: Decodable {
        var error: Detail
        struct Detail: Decodable {
            var type: String?
            var message: String?
        }
    }
}

enum AnthropicError: LocalizedError, Equatable {
    case missingAPIKey
    case http(status: Int, type: String?, message: String?)
    case refusal
    case truncated
    case emptyResponse

    var isRetryable: Bool {
        guard case .http(let status, _, _) = self else { return false }
        return status == 429 || status >= 500
    }

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Configure a chave da API nas Preferências"
        case .http(401, _, _):
            "Chave da API inválida"
        case .http(403, _, _):
            "A chave não tem permissão para usar este modelo"
        case .http(404, _, _):
            "Modelo indisponível para a sua conta"
        case .http(429, _, _):
            "Limite de uso da API atingido"
        case .http(529, _, _):
            "API da Anthropic sobrecarregada"
        case .http(let status, _, let message):
            message.map { "Erro da API (\(status)): \($0)" } ?? "Erro da API (\(status))"
        case .refusal:
            "O modelo recusou o pedido"
        case .truncated:
            "A resposta do modelo veio incompleta"
        case .emptyResponse:
            "O modelo não devolveu texto"
        }
    }
}
