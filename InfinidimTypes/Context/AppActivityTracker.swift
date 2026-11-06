import AppKit
import Observation

/// Lembra o último app usado fora do InfinidimTypes, para o "Colar em…" do histórico.
@Observable
final class AppActivityTracker {
    private(set) var lastExternalApp: NSRunningApplication?

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        record(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.record(app) }
        }
    }

    private func record(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApp = app
    }
}
