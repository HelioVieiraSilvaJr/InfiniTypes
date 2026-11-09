import Foundation
import Testing
@testable import InfiniTypes

// Casos de `shared/conformance/`. Os testes das outras plataformas leem os mesmos arquivos.

struct SecretConformanceTests {
    @Test(arguments: try Conformance.cases(SecretCase.self, from: "secrets"))
    func findsTheSameSecrets(_ testCase: SecretCase) {
        #expect(SecretScanner.findings(in: testCase.text.joined()) == testCase.findings)
    }
}

struct HallucinationConformanceTests {
    @Test(arguments: try Conformance.cases(HallucinationCase.self, from: "hallucinations"))
    func cleansTheSameWay(_ testCase: HallucinationCase) {
        #expect(HallucinationFilter.clean(testCase.input) == testCase.output)
    }
}

struct ProjectConformanceTests {
    @Test(arguments: try Conformance.load(ProjectFile.self, from: "projects").cases)
    func picksTheSameProject(_ testCase: ProjectCase) throws {
        let input = try Conformance.load(ProjectFile.self, from: "projects").glossary
        let glossary = Glossary(globalTerms: input.globalTerms,
                                projects: input.projects.map { .init(name: $0.name, terms: $0.terms) })
        let match = glossary.match(windowTitle: testCase.windowTitle)
        #expect(match.projectName == testCase.project)
        #expect(match.terms == testCase.terms)
    }
}

struct RevisionEditsConformanceTests {
    @Test(arguments: try Conformance.cases(RevisionEditsCase.self, from: "revision-edits"))
    func appliesTheSameEdits(_ testCase: RevisionEditsCase) {
        do {
            let revised = try RevisionPatcher.apply(testCase.edits, to: testCase.text)
            #expect(testCase.error == nil, "deveria falhar com \(testCase.error ?? "")")
            #expect(revised == testCase.result)
        } catch let failure as RevisionPatcher.Failure {
            #expect(failure.code == testCase.error)
        } catch {
            Issue.record(error)
        }
    }
}

struct RequestConformanceTests {
    @Test func usesTheSameEndpointAndVersion() throws {
        let api = try Conformance.load(RequestFile.self, from: "requests").api
        #expect(AnthropicClient.baseURL.appending(path: "messages").absoluteString == api.messagesURL)
        #expect(AnthropicClient.apiVersion == api.anthropicVersion)
    }

    @Test(arguments: try Conformance.load(RequestFile.self, from: "requests").cases)
    func buildsTheSameRequest(_ testCase: RequestCase) throws {
        let model = ModelCatalog.model(id: testCase.model)
        let effort = try #require(Effort(rawValue: testCase.effort))
        let context = DictationContext(appName: testCase.context.app, windowTitle: testCase.context.windowTitle,
                                       projectName: testCase.context.project)
        let request = switch testCase.kind {
        case .refinement:
            ClaudeRefiner.makeRequest(model: model, effort: effort, systemPrompt: testCase.systemPrompt,
                                      transcript: testCase.transcript, context: context,
                                      vocabulary: testCase.vocabulary)
        case .revision:
            ClaudeRefiner.makeRevisionRequest(model: model, effort: effort, systemPrompt: testCase.systemPrompt,
                                              format: try #require(testCase.format?.revisionFormat),
                                              selection: try #require(testCase.selection),
                                              dictation: testCase.transcript, context: context,
                                              vocabulary: testCase.vocabulary)
        }
        let body = try JSONDecoder().decode(JSONAny.self, from: AnthropicClient.encoder.encode(request))
        #expect(body == testCase.expectedBody)
        #expect(AnthropicClient.betaHeader(for: request) == testCase.expectedBeta)
    }
}

// MARK: Leitura dos arquivos

nonisolated enum Conformance {
    private final class BundleToken {}

    private struct File<Case: Decodable>: Decodable {
        var cases: [Case]
    }

    static func cases<Case: Decodable>(_ type: Case.Type, from name: String) throws -> [Case] {
        try load(File<Case>.self, from: name).cases
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        guard let url = Bundle(for: BundleToken.self)
            .url(forResource: name, withExtension: "json", subdirectory: "conformance") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "conformance/\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

nonisolated struct SecretCase: Decodable, Sendable, CustomTestStringConvertible {
    var name: String
    /// Pedaços juntados sem separador: assim as chaves falsas não disparam os detectores de segredos.
    var text: [String]
    var findings: [String]

    var testDescription: String { name }
}

nonisolated struct HallucinationCase: Decodable, Sendable, CustomTestStringConvertible {
    var name: String
    var input: String
    var output: String

    var testDescription: String { name }
}

nonisolated struct ProjectFile: Decodable, Sendable {
    var glossary: GlossaryInput
    var cases: [ProjectCase]

    struct GlossaryInput: Decodable, Sendable {
        var globalTerms: String
        var projects: [Project]

        struct Project: Decodable, Sendable {
            var name: String
            var terms: String
        }

        enum CodingKeys: String, CodingKey {
            case projects
            case globalTerms = "global_terms"
        }
    }
}

nonisolated struct ProjectCase: Decodable, Sendable, CustomTestStringConvertible {
    var name: String
    var windowTitle: String?
    var project: String?
    var terms: [String]

    var testDescription: String { name }

    enum CodingKeys: String, CodingKey {
        case name, project, terms
        case windowTitle = "window_title"
    }
}

nonisolated struct RevisionEditsCase: Decodable, Sendable, CustomTestStringConvertible {
    var name: String
    var text: String
    var edits: [RevisionPatcher.Edit]
    var result: String?
    /// `not_found`, `ambiguous` ou `overlapping`.
    var error: String?

    var testDescription: String { name }
}

nonisolated struct RequestFile: Decodable, Sendable {
    var api: API
    var cases: [RequestCase]

    struct API: Decodable, Sendable {
        var messagesURL: String
        var anthropicVersion: String

        enum CodingKeys: String, CodingKey {
            case messagesURL = "messages_url"
            case anthropicVersion = "anthropic_version"
        }
    }
}

nonisolated struct RequestCase: Decodable, Sendable, CustomTestStringConvertible {
    enum Kind: String, Decodable, Sendable {
        case refinement, revision
    }

    enum Format: String, Decodable, Sendable {
        case edits
        case fullText = "full_text"

        var revisionFormat: ClaudeRefiner.RevisionFormat {
            switch self {
            case .edits: .edits
            case .fullText: .fullText
            }
        }
    }

    struct Context: Decodable, Sendable {
        var app: String?
        var windowTitle: String?
        var project: String?

        enum CodingKeys: String, CodingKey {
            case app, project
            case windowTitle = "window_title"
        }
    }

    var name: String
    var kind: Kind
    var model: String
    var effort: String
    var format: Format?
    var systemPrompt: String
    var selection: String?
    var transcript: String
    var context: Context
    var vocabulary: [String]
    var expectedBeta: String?
    var expectedBody: JSONAny

    var testDescription: String { name }

    enum CodingKeys: String, CodingKey {
        case name, kind, model, effort, format, selection, transcript, context, vocabulary
        case systemPrompt = "system_prompt"
        case expectedBeta = "expected_beta"
        case expectedBody = "expected_body"
    }
}

/// Qualquer valor JSON, para comparar o corpo da requisição com o esperado.
nonisolated indirect enum JSONAny: Decodable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONAny])
    case object([String: JSONAny])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONAny].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONAny].self))
        }
    }
}

private extension RevisionPatcher.Failure {
    /// Nome do erro nos arquivos de conformidade.
    var code: String {
        switch self {
        case .notFound: "not_found"
        case .ambiguous: "ambiguous"
        case .overlapping: "overlapping"
        }
    }
}
