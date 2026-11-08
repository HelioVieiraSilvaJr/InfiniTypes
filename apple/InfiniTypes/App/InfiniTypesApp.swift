import SwiftUI

@main
struct InfiniTypesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                permissions: appDelegate.permissions,
                settings: appDelegate.settings,
                models: appDelegate.models,
                transcriber: appDelegate.transcriber,
                actions: appDelegate.menuActions
            )
            .modelContainer(appDelegate.history.container)
        } label: {
            Image("MenuBarIcon")
                .accessibilityLabel("InfiniTypes")
        }
    }
}
