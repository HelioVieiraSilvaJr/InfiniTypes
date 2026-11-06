import Foundation

/// Um ditado real marcado no histórico, no formato do conjunto de avaliação do refinador.
nonisolated struct EvalCase: Codable, Equatable, Sendable {
    /// Data e hora do ditado (ISO 8601).
    var id: String
    var mode: String
    var app: String?
    var windowTitle: String?
    var project: String?
    var rawTranscript: String
    /// Na revisão, o texto que estava selecionado.
    var originalText: String?
    /// O que o app entregou na época, para comparar com versões novas do prompt.
    var deliveredText: String
    var modelID: String?
    var refined: Bool

    enum CodingKeys: String, CodingKey {
        case id, mode, app, project, refined
        case windowTitle = "window_title"
        case rawTranscript = "raw_transcript"
        case originalText = "original_text"
        case deliveredText = "delivered_text"
        case modelID = "model_id"
    }
}

/// Exporta os ditados marcados para `~/Library/Application Support/InfinidimTypes/Eval/cases.jsonl`.
enum EvalExporter {
    static var fileURL: URL { AppPaths.support.appending(path: "Eval/cases.jsonl") }

    static func evalCase(from record: DictationRecord) -> EvalCase {
        EvalCase(id: record.createdAt.ISO8601Format(), mode: record.mode.rawValue, app: record.appName,
                 windowTitle: record.windowTitle, project: record.projectName, rawTranscript: record.rawTranscript,
                 originalText: record.originalText, deliveredText: record.text, modelID: record.modelID,
                 refined: record.refined)
    }

    /// Uma linha JSON por caso, do mais antigo para o mais novo.
    static func jsonl(_ cases: [EvalCase]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try cases.sorted { $0.id < $1.id }
            .map { String(decoding: try encoder.encode($0), as: UTF8.self) }
            .joined(separator: "\n") + "\n"
    }

    @discardableResult
    static func export(_ records: [DictationRecord]) throws -> URL {
        let url = fileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jsonl(records.map(evalCase(from:))).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
