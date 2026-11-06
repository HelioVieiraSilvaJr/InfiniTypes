import AppKit
import SwiftData
import SwiftUI

struct MenuActions {
    let showHistory: () -> Void
    let showSettings: () -> Void
    let showPermissions: () -> Void
    let pasteLatest: (String) -> Void
}

struct MenuBarContent: View {
    let permissions: PermissionsManager
    @Bindable var settings: AppSettings
    let models: AvailableModels
    let transcriber: WhisperKitTranscriber
    let actions: MenuActions

    @Query(MenuBarContent.latestDescriptor) private var latest: [DictationRecord]

    private static var latestDescriptor: FetchDescriptor<DictationRecord> {
        var descriptor = FetchDescriptor<DictationRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        Text(status)
        Divider()
        Picker("Modelo", selection: $settings.modelID) {
            ForEach(models.models) { model in
                Text(model.displayName).tag(model.id)
            }
        }
        Divider()
        Button("Colar último prompt") {
            if let text = latest.first?.text { actions.pasteLatest(text) }
        }
        .disabled(latest.isEmpty)
        Button("Copiar último prompt") {
            if let text = latest.first?.text { TextInserter.copy(text) }
        }
        .disabled(latest.isEmpty)
        Button("Histórico…", action: actions.showHistory)
            .keyboardShortcut("y")
        Divider()
        Button("Preferências…", action: actions.showSettings)
            .keyboardShortcut(",")
        Button("Permissões…", action: actions.showPermissions)
        Divider()
        Button("Sair do InfinidimTypes") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var status: String {
        if !permissions.allGranted { return "Permissões pendentes" }
        switch transcriber.state {
        case .downloading(let fraction): return "Baixando modelo de voz… \(Int(fraction * 100))%"
        case .idle, .loading: return "Preparando modelo de voz…"
        case .failed: return "Falha no modelo de voz"
        case .ready: break
        }
        if !settings.hasAPIKey { return "Configure a chave da API" }
        return "Pronto: segure o ⌥ direito"
    }
}
