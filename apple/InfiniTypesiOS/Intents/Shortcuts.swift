import AppIntents

/// Frases da Siri e atalhos prontos no app Atalhos e no Botão de Ação.
nonisolated struct InfiniTypesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: ["Ditar no \(.applicationName)", "Novo prompt no \(.applicationName)"],
            shortTitle: "Ditar prompt",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StartDictationIntent(mode: .revision),
            phrases: ["Revisar com o \(.applicationName)"],
            shortTitle: "Revisar o copiado",
            systemImageName: "text.badge.checkmark"
        )
    }
}
