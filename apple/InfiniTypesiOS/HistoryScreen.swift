import SwiftData
import SwiftUI

/// Todo ditado fica aqui, para você nunca perder o que falou.
struct HistoryScreen: View {
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @Environment(\.modelContext) private var context
    @State private var search = ""

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return records }
        return records.filter {
            $0.text.localizedCaseInsensitiveContains(search) || $0.rawTranscript.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(DayGrouping.sections(filtered, date: \.createdAt)) { section in
                    Section(section.title) {
                        ForEach(section.items) { record in
                            NavigationLink {
                                RecordDetail(record: record)
                            } label: {
                                RecordRow(record: record)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = record.text }
                                    .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Apagar", systemImage: "trash", role: .destructive) { delete(record) }
                                Button(record.inEvalSet ? "Tirar" : "Avaliar", systemImage: record.inEvalSet ? "star.slash" : "star") {
                                    record.inEvalSet.toggle()
                                    try? context.save()
                                }
                                .tint(.yellow)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Histórico")
            .searchable(text: $search, prompt: "Buscar no histórico")
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView("Nenhum ditado ainda", systemImage: "waveform",
                                           description: Text("Toque no microfone na aba Ditar e fale."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
    }

    private func delete(_ record: DictationRecord) {
        context.delete(record)
        try? context.save()
    }
}

private struct RecordRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.createdAt, format: .dateTime.hour().minute())
                Text("·")
                Text(record.mode.label)
                if let project = record.projectName {
                    Text("·")
                    Text(project)
                }
                if record.inEvalSet { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                if record.errorMessage != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(record.text).lineLimit(3)
        }
    }
}

private struct RecordDetail: View {
    let record: DictationRecord

    var body: some View {
        List {
            Section("Texto entregue") {
                Text(record.text).textSelection(.enabled)
                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = record.text }
            }
            if let original = record.originalText {
                Section("Texto original") { Text(original).textSelection(.enabled) }
            }
            Section("Transcrição") { Text(record.rawTranscript).textSelection(.enabled) }
            if let error = record.errorMessage {
                Section("Problema") { Text(error).foregroundStyle(.orange) }
            }
            Section("Detalhes") {
                LabeledContent("Modo", value: record.mode.label)
                if let model = record.modelID { LabeledContent("Modelo", value: ModelCatalog.model(id: model).displayName) }
                LabeledContent("Áudio", value: "\(record.audioSeconds.formatted(.number.precision(.fractionLength(1)))) s")
                LabeledContent("Transcrição", value: "\(record.transcriptionSeconds.formatted(.number.precision(.fractionLength(1)))) s")
                if let refinement = record.refinementSeconds {
                    LabeledContent("Refinamento", value: "\(refinement.formatted(.number.precision(.fractionLength(1)))) s")
                }
            }
        }
        .navigationTitle(record.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }
}
