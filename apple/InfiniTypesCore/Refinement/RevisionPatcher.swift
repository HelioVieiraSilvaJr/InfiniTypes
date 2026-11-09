import Foundation

/// Aplica ao texto original as alterações devolvidas pelo modelo. O que não foi alterado fica idêntico.
enum RevisionPatcher {
    nonisolated struct Edit: Codable, Equatable, Sendable {
        /// Trecho copiado literalmente do texto original.
        var original: String
        var revised: String
    }

    nonisolated struct Response: Codable, Equatable, Sendable {
        var edits: [Edit]
    }

    enum Failure: Error, Equatable {
        case notFound(String)
        case ambiguous(String)
        case overlapping

        /// Motivo para o log, sem o trecho do texto do usuário.
        var reason: String {
            switch self {
            case .notFound: "trecho não encontrado"
            case .ambiguous: "trecho repetido"
            case .overlapping: "alterações sobrepostas"
            }
        }
    }

    /// Esquema JSON enviado à API para a resposta vir como `Response`.
    static let schema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "edits": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "original": .object(["type": .string("string")]),
                        "revised": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("original"), .string("revised")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ]),
        "required": .array([.string("edits")]),
        "additionalProperties": .bool(false),
    ])

    /// Cada trecho precisa aparecer uma única vez no original, e os trechos não podem se sobrepor.
    static func apply(_ edits: [Edit], to text: String) throws -> String {
        var located: [(range: Range<String.Index>, revised: String)] = []
        for edit in edits {
            guard !edit.original.isEmpty else { throw Failure.notFound(edit.original) }
            let matches = text.ranges(of: edit.original)
            guard let range = matches.first else { throw Failure.notFound(edit.original) }
            guard matches.count == 1 else { throw Failure.ambiguous(edit.original) }
            located.append((range, edit.revised))
        }
        located.sort { $0.range.lowerBound < $1.range.lowerBound }

        var result = ""
        var cursor = text.startIndex
        for edit in located {
            guard edit.range.lowerBound >= cursor else { throw Failure.overlapping }
            result += text[cursor..<edit.range.lowerBound]
            result += edit.revised
            cursor = edit.range.upperBound
        }
        result += text[cursor...]
        return result
    }
}
