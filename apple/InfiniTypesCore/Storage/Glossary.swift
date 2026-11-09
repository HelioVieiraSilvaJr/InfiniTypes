import Foundation
import Observation
import OSLog

/// Termos com a grafia correta, que ajudam o Whisper a reconhecer e o Claude a corrigir.
nonisolated struct Glossary: Codable, Equatable, Sendable {
    /// Um termo por linha. Guardado como texto para a edição livre nas preferências.
    var globalTerms: String = ""
    var projects: [Project] = []

    struct Project: Codable, Equatable, Identifiable, Sendable {
        var id = UUID()
        /// Reconhecido quando aparece no título da janela.
        var name: String = ""
        var terms: String = ""
    }

    struct Match: Equatable, Sendable {
        var projectName: String?
        var terms: [String]
    }

    /// Termos globais mais os do projeto cujo nome aparece no título da janela.
    func match(windowTitle: String?) -> Match {
        let project = windowTitle.flatMap { title in
            projects
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                // O nome mais longo vence, para "api-admin" não ser confundido com "api".
                .sorted { $0.name.count > $1.name.count }
                .first { title.range(of: $0.name.trimmingCharacters(in: .whitespaces),
                                     options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        var seen = Set<String>()
        let terms = (Self.lines(globalTerms) + Self.lines(project?.terms ?? ""))
            .filter { seen.insert($0.lowercased()).inserted }
        return Match(projectName: project?.name.trimmingCharacters(in: .whitespaces), terms: terms)
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Glossário salvo em `~/Library/Application Support/InfiniTypes/Glossary.json`.
@Observable
final class GlossaryStore {
    var glossary: Glossary {
        didSet { save() }
    }

    @ObservationIgnored private let url = AppPaths.support.appending(path: "Glossary.json")

    init() {
        glossary = (try? JSONDecoder().decode(Glossary.self, from: Data(contentsOf: url))) ?? Glossary()
    }

    func addProject() {
        glossary.projects.append(Glossary.Project())
    }

    func removeProject(id: Glossary.Project.ID) {
        glossary.projects.removeAll { $0.id == id }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(glossary).write(to: url, options: .atomic)
        } catch {
            Logger.history.error("Falha ao salvar o glossário: \(error.localizedDescription, privacy: .public)")
        }
    }
}
