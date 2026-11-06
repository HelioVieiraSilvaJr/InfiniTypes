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
    private let activity = AppActivityTracker()
    private let hud = HUDController()
    private let windows = WindowPresenter()
    private let hotkey = HotkeyMonitor()

    private lazy var coordinator = DictationCoordinator(
        permissions: permissions, settings: settings, transcriber: transcriber,
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
        hotkey.onPress = { [weak self] in self?.coordinator.startRecording() }
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
            Task { await coordinator.debugProcessFile(at: path) }
        }
        #endif
    }

    // MARK: Janelas

    func showOnboarding() {
        permissions.startMonitoring()
        windows.show(id: "onboarding", title: "InfinidimTypes", onClose: { [weak self] in
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
        windows.show(id: "settings", title: "Preferências do InfinidimTypes") {
            SettingsView(settings: settings, models: models, transcriber: transcriber)
        }
    }

    func showHistory() {
        windows.show(id: "history", title: "Histórico do InfinidimTypes", defaultSize: NSSize(width: 880, height: 560)) {
            HistoryView(activity: activity, onPaste: paste(_:into:), onDelete: { [history] in history.delete($0) })
                .modelContainer(history.container)
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
}
