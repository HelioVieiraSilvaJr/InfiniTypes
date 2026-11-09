import AppKit
import OSLog
import SwiftUI

/// Monta os serviços do app e liga o atalho ao fluxo de ditado.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let permissions = PermissionsManager()
    let settings = AppSettings()
    let models = AvailableModels()
    let transcriber = WhisperKitTranscriber()
    let history = HistoryStore()
    let glossary = GlossaryStore()
    private let activity = AppActivityTracker()
    private let hud = HUDController()
    private let windows = WindowPresenter()
    private let hotkey = HotkeyMonitor()

    private lazy var coordinator = DictationCoordinator(
        permissions: permissions, settings: settings, glossary: glossary, transcriber: transcriber,
        refiner: ClaudeRefiner(settings: settings), history: history, hud: hud
    )

    var menuActions: MenuActions {
        MenuActions(showHistory: showHistory, showSettings: showSettings,
                    showPermissions: showOnboarding, pasteLatest: pasteLatest)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nos testes o app é só o host: nada de atalho, microfone ou download do modelo.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        Logger.permissions.notice(
            "Inicialização — microfone: \(self.permissions.microphone.rawValue, privacy: .public), acessibilidade: \(self.permissions.accessibility.rawValue, privacy: .public)"
        )

        coordinator.onNeedsPermissions = { [weak self] in self?.showOnboarding() }
        coordinator.onNeedsRelaunch = { [weak self] in self?.relaunch() }
        hotkey.onPress = { [weak self] mode in self?.coordinator.startRecording(mode: mode) }
        hotkey.onHandsFree = { [weak self] in self?.coordinator.startRecording(mode: .prompt, handsFree: true) }
        coordinator.onRecordingEnded = { [weak self] in self?.hotkey.endHandsFree() }
        hotkey.onRelease = { [weak self] in self?.coordinator.finishRecording() }
        hotkey.onCancel = { [weak self] in self?.coordinator.cancelRecording() }
        hotkey.start()

        transcriber.prepare()
        Task { await models.refresh() }

        if !permissions.allGranted {
            showOnboarding()
        } else if !settings.hasAPIKey {
            showSettings()
        }

        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "transcribeFile") {
            let mode: DictationMode = UserDefaults.standard.bool(forKey: "literal") ? .literal : .prompt
            let selectionFile = UserDefaults.standard.string(forKey: "reviseFile")
            let glossary = UserDefaults.standard.string(forKey: "glossaryFile").flatMap {
                try? JSONDecoder().decode(Glossary.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
            }
            Task {
                await coordinator.debugProcessFile(at: path, mode: mode, selectionFile: selectionFile, glossary: glossary)
            }
        }
        #endif
    }

    // MARK: Janelas

    func showOnboarding() {
        permissions.startMonitoring()
        windows.show(id: "onboarding", title: "InfiniTypes", onClose: { [weak self] in
            guard let self else { return }
            permissions.stopMonitoring()
            // Monitores globais criados antes da permissão de Acessibilidade não recebem eventos.
            hotkey.stop()
            hotkey.start()
        }) {
            OnboardingView(permissions: permissions) { [weak self] in
                self?.windows.close(id: "onboarding")
            }
        }
    }

    func showSettings() {
        let windowTitle = activity.lastExternalApp.flatMap(ContextCollector.windowTitle(of:))
        windows.show(id: "settings", title: "Preferências do InfiniTypes") {
            SettingsView(settings: settings, models: models, transcriber: transcriber,
                         glossary: glossary, currentWindowTitle: windowTitle)
        }
    }

    func showHistory() {
        windows.show(id: "history", title: "Histórico do InfiniTypes", defaultSize: NSSize(width: 880, height: 560)) {
            HistoryView(activity: activity, onPaste: paste(_:into:), onDelete: { [history] in history.delete($0) },
                        onExportEval: exportEval)
                .modelContainer(history.container)
        }
    }

    private func exportEval(_ records: [DictationRecord]) {
        do {
            let url = try EvalExporter.export(records)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            hud.show(.failure("Falha ao exportar a avaliação: \(error.localizedDescription)"))
        }
    }

    // MARK: Colagem fora do ditado

    private func pasteLatest(_ text: String) {
        Task {
            // Espera o menu fechar e o foco voltar para o app anterior.
            try? await Task.sleep(for: .milliseconds(250))
            if FocusDetector.check() == .notEditable {
                TextInserter.copy(text)
                hud.show(.notice("Nenhum campo de texto em foco: prompt copiado"))
            } else {
                await TextInserter.paste(text)
            }
        }
    }

    private func paste(_ text: String, into app: NSRunningApplication) {
        app.activate()
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await TextInserter.paste(text)
        }
    }

    // MARK: Reabertura

    /// Encerra o app e abre de novo o mesmo caminho, que agora tem o build novo. Um processo à parte
    /// espera este terminar, porque o LaunchServices não abre uma segunda instância do mesmo app.
    private func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.5; /usr/bin/open \"$0\"",
                            Bundle.main.bundlePath]
        do {
            try reopen.run()
        } catch {
            Logger.permissions.error("Não foi possível reabrir o app: \(error.localizedDescription, privacy: .public)")
            return
        }
        Logger.permissions.notice("Build novo no disco: reabrindo o app")
        Task {
            // Tempo para o aviso do HUD ser lido.
            try? await Task.sleep(for: .seconds(1.5))
            NSApp.terminate(nil)
        }
    }
}
