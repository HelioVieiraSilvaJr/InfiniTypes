import AppIntents
import SwiftUI
import WidgetKit

@main
struct InfiniTypesControls: WidgetBundle {
    var body: some Widget {
        DictationControl()
    }
}

/// Botão na Central de Controle, na tela bloqueada e no Botão de Ação: abre o app já gravando.
struct DictationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.infinidim.InfiniTypes.dictation") {
            ControlWidgetButton(action: StartDictationIntent()) {
                Label("Ditar prompt", systemImage: "waveform")
            }
        }
        .displayName("Ditar prompt")
        .description("Abre o InfiniTypes já gravando.")
    }
}
