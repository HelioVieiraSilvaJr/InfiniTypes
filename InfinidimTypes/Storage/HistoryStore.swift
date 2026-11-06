import Foundation
import OSLog
import SwiftData

/// Um ditado salvo no histórico.
@Model
final class DictationRecord {
    var createdAt: Date
    /// Texto entregue: o prompt refinado ou, se o refinamento falhou, a transcrição bruta.
    var text: String
    var rawTranscript: String
    var appName: String?
    var appBundleID: String?
    var windowTitle: String?
    var modelID: String?
    var refined: Bool
    var pasted: Bool
    var errorMessage: String?
    var audioSeconds: Double
    var transcriptionSeconds: Double
    var refinementSeconds: Double?
    var inputTokens: Int?
    var outputTokens: Int?

    init(createdAt: Date = .now, text: String, rawTranscript: String, context: DictationContext,
         modelID: String?, refined: Bool, errorMessage: String?, audioSeconds: Double,
         transcriptionSeconds: Double, refinementSeconds: Double?, inputTokens: Int?, outputTokens: Int?) {
        self.createdAt = createdAt
        self.text = text
        self.rawTranscript = rawTranscript
        self.appName = context.appName
        self.appBundleID = context.bundleID
        self.windowTitle = context.windowTitle
        self.modelID = modelID
        self.refined = refined
        self.pasted = false
        self.errorMessage = errorMessage
        self.audioSeconds = audioSeconds
        self.transcriptionSeconds = transcriptionSeconds
        self.refinementSeconds = refinementSeconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// Persistência do histórico em `~/Library/Application Support/InfinidimTypes/History.store`.
final class HistoryStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() {
        let url = AppPaths.support.appending(path: "History.store")
        do {
            container = try ModelContainer(for: DictationRecord.self, configurations: ModelConfiguration(url: url))
        } catch {
            // Sem o arquivo, o app segue funcionando, mas o histórico só dura até ele fechar.
            Logger.history.fault("Histórico indisponível, usando memória: \(error.localizedDescription, privacy: .public)")
            container = try! ModelContainer(for: DictationRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    func insert(_ record: DictationRecord) {
        context.insert(record)
        save()
    }

    func delete(_ record: DictationRecord) {
        context.delete(record)
        save()
    }

    func save() {
        do {
            try context.save()
        } catch {
            Logger.history.error("Falha ao salvar o histórico: \(error.localizedDescription, privacy: .public)")
        }
    }

    var latest: DictationRecord? {
        var descriptor = FetchDescriptor<DictationRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Agrupa itens por dia, do mais recente para o mais antigo, com títulos como "Hoje" e "Ontem".
enum DayGrouping {
    struct Section<Item>: Identifiable {
        let day: Date
        let title: String
        let items: [Item]
        var id: Date { day }
    }

    static func sections<Item>(_ items: [Item], date: (Item) -> Date,
                               calendar: Calendar = .current, now: Date = .now) -> [Section<Item>] {
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
        return grouped.keys.sorted(by: >).map { day in
            Section(day: day, title: title(for: day, calendar: calendar, now: now),
                    items: grouped[day]!.sorted { date($0) > date($1) })
        }
    }

    static func title(for day: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) { return "Hoje" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Ontem" }
        var style = Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "pt_BR"))
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }
}
