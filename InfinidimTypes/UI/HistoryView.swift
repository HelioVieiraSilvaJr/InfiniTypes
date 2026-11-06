import AppKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    let activity: AppActivityTracker
    let onPaste: (String, NSRunningApplication) -> Void
    let onDelete: (DictationRecord) -> Void

    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var selection: PersistentIdentifier?
    @State private var search = ""

    private var filtered: [DictationRecord] {
        guard !search.isEmpty else { return records }
        return records.filter {
            $0.text.localizedCaseInsensitiveContains(search) || $0.rawTranscript.localizedCaseInsensitiveContains(search)
        }
    }

    private var selected: DictationRecord? {
        records.first { $0.persistentModelID == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(DayGrouping.sections(filtered, date: \.createdAt)) { section in
                    Section(section.title) {
                        ForEach(section.items) { record in
                            HistoryRow(record: record)
                                .tag(record.persistentModelID)
                                .contextMenu {
                                    Button("Copiar") { TextInserter.copy(record.text) }
                                    Button("Apagar", role: .destructive) { delete(record) }
                                }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            .searchable(text: $search, placement: .sidebar, prompt: "Buscar no histórico")
            .onDeleteCommand { selected.map(delete) }
            .onCopyCommand { selected.map { [NSItemProvider(object: $0.text as NSString)] } ?? [] }
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView("Nenhum ditado ainda", systemImage: "waveform",
                                           description: Text("Segure o ⌥ direito e fale."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
        } detail: {
            if let selected {
                HistoryDetail(record: selected, previousApp: activity.lastExternalApp,
                              onPaste: onPaste, onDelete: { delete(selected) })
            } else {
                ContentUnavailableView("Selecione um ditado", systemImage: "text.bubble")
            }
        }
        .onAppear {
            if selection == nil { selection = records.first?.persistentModelID }
        }
    }

    private func delete(_ record: DictationRecord) {
        if record.persistentModelID == selection { selection = nil }
        onDelete(record)
    }
}

private struct HistoryRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(record.createdAt, format: .dateTime.hour().minute())
                    .monospacedDigit()
                if let app = record.appName {
                    Text(app)
                }
                Spacer()
                if !record.pasted {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(.orange)
                        .help("Não foi colado: ficou só no histórico")
                }
                if !record.refined {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help("Texto sem refinamento")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(record.text)
                .font(.callout)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetail: View {
    let record: DictationRecord
    let previousApp: NSRunningApplication?
    let onPaste: (String, NSRunningApplication) -> Void
    let onDelete: () -> Void

    @State private var showRaw = false
    @State private var copied = false

    private var displayedText: String { showRaw ? record.rawTranscript : record.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.createdAt.formatted(Date.FormatStyle(date: .complete, time: .shortened)
                    .locale(Locale(identifier: "pt_BR"))))
                    .font(.headline)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                Text(displayedText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            Divider()

            HStack {
                Toggle("Mostrar transcrição bruta", isOn: $showRaw)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Apagar", role: .destructive, action: onDelete)
                if let previousApp {
                    Button("Colar em \(previousApp.localizedName ?? "app anterior")") {
                        onPaste(displayedText, previousApp)
                    }
                }
                Button(copied ? "Copiado" : "Copiar") {
                    TextInserter.copy(displayedText)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .onChange(of: record.persistentModelID) {
            showRaw = false
            copied = false
        }
    }

    private var summary: String {
        var parts: [String] = []
        if record.pasted {
            parts.append("Colado em \(record.appName ?? "app desconhecido")")
        } else {
            parts.append("Não colado: nenhum campo de texto em foco")
        }
        if record.refined {
            let model = record.modelID.map { ModelCatalog.model(id: $0).displayName } ?? "Claude"
            parts.append(model)
        } else {
            parts.append("Sem refinamento" + (record.errorMessage.map { ": \($0)" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }
}
