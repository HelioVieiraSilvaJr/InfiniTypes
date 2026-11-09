import SwiftData
import SwiftUI

@main
struct InfiniTypesiOSApp: App {
    @State private var model: DictationModel
    private let history: HistoryStore

    init() {
        let settings = AppSettings()
        let history = HistoryStore()
        let transcriber = WhisperKitTranscriber()
        self.history = history
        _model = State(initialValue: DictationModel(settings: settings, glossary: GlossaryStore(), history: history,
                                                    transcriber: transcriber, refiner: ClaudeRefiner(settings: settings)))
        // O modelo de voz é baixado e carregado em segundo plano, para o primeiro ditado não esperar.
        transcriber.prepare()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Ditar", systemImage: "waveform") {
                    DictateView(model: model)
                }
                Tab("Histórico", systemImage: "clock.arrow.circlepath") {
                    HistoryScreen()
                }
                Tab("Ajustes", systemImage: "gearshape") {
                    SettingsScreen(settings: model.settings, glossary: model.glossary, transcriber: model.transcriber)
                }
            }
            .modelContainer(history.container)
        }
    }
}
