import AppKit
import ApplicationServices
import AVFoundation
import Observation

/// Estado das permissões que o app precisa: microfone (gravar o ditado) e
/// Acessibilidade (atalho global, leitura do contexto e colagem com ⌘V).
@Observable
final class PermissionsManager {
    enum Status: String {
        case granted
        case denied
        case notDetermined
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var accessibility: Status = .notDetermined

    var allGranted: Bool { microphone == .granted && accessibility == .granted }

    private var monitorTask: Task<Void, Never>?

    init() {
        refresh()
    }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
        accessibility = AXIsProcessTrusted() ? .granted : .denied
    }

    func requestMicrophone() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            // Já foi negado uma vez: o sistema não pergunta de novo, só pelos Ajustes.
            openSystemSettings(pane: "Privacy_Microphone")
        }
        refresh()
    }

    func requestAccessibility() {
        // O alerta do sistema também inclui o app na lista de Acessibilidade.
        // A chave é passada como texto porque a constante global não é concurrency-safe no Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openSystemSettings(pane: "Privacy_Accessibility")
        }
        refresh()
    }

    /// A Acessibilidade não avisa quando muda, então consultamos enquanto o onboarding está aberto.
    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func openSystemSettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
