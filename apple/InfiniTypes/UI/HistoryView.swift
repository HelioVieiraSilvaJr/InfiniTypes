import AppKit
import SwiftData
import SwiftUI

struct HistoryView: View {
    let activity: AppActivityTracker
    let onPaste: (String, NSRunningApplication) -> Void
    let onDelete: (DictationRecord) -> Void
    let onExportEval: ([DictationRecord]) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DictationRecord.createdAt, order: .reverse) private var records: [DictationRecord]
    @State private var selection: PersistentIdentifier?
    @State private var search = ""

    private var evalRecords: [DictationRecord] { records.filter(\.inEvalSet) }

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
                                    Button(record.inEvalSet ? "Tirar da avaliação" : "Usar na avaliação") {
                                        toggleEval(record)
                                    }
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
                              onPaste: onPaste, onToggleEval: { toggleEval(selected) },
                              onDelete: { delete(selected) })
            } else {
                ContentUnavailableView("Selecione um ditado", systemImage: "text.bubble")
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Exportar avaliação (\(evalRecords.count))", systemImage: "square.and.arrow.up") {
                    onExportEval(evalRecords)
                }
                .labelStyle(.titleAndIcon)
                .disabled(evalRecords.isEmpty)
                .help("Salva os ditados marcados com estrela em um arquivo JSONL para avaliar o refinador")
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

    private func toggleEval(_ record: DictationRecord) {
        record.inEvalSet.toggle()
        try? modelContext.save()
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
                if record.mode != .prompt {
                    Text(record.mode.label)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if record.inEvalSet {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .help("Marcado para a avaliação")
                }
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
    let onToggleEval: () -> Void
    let onDelete: () -> Void

    private enum Version: Hashable {
        case result, speech, original
    }

    @State private var version: Version = .result
    @State private var copied = false

    private var versions: [(Version, String)] {
        record.originalText == nil
            ? [(.result, "Resultado"), (.speech, "Transcrição bruta")]
            : [(.result, "Revisado"), (.speech, "Fala"), (.original, "Original")]
    }

    private var displayedText: String {
        switch version {
        case .result: record.text
        case .speech: record.rawTranscript
        case .original: record.originalText ?? record.text
        }
    }

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
                Picker("Versão", selection: $version) {
                    ForEach(versions, id: \.0) { version, label in
                        Text(label).tag(version)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button(action: onToggleEval) {
                    Image(systemName: record.inEvalSet ? "star.fill" : "star")
                }
                .help(record.inEvalSet ? "Tirar da avaliação" : "Usar na avaliação do refinador")
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
            version = .result
            copied = false
        }
    }

    private var summary: String {
        var parts: [String] = []
        if record.mode != .prompt {
            parts.append("Modo \(record.mode.label.lowercased())")
        }
        if record.pasted {
            parts.append("Colado em \(record.appName ?? "app desconhecido")")
        } else {
            parts.append("Não colado")
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
