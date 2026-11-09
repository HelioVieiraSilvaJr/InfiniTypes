import SwiftUI

/// Tela principal: um botão grande para gravar e o resultado, já copiado.
struct DictateView: View {
    @Bindable var model: DictationModel
    @Environment(\.scenePhase) private var scenePhase
    private let pending = PendingDictation.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Modo", selection: $model.mode) {
                    Text("Prompt").tag(DictationMode.prompt)
                    Text("Literal").tag(DictationMode.literal)
                    Text("Revisão").tag(DictationMode.revision)
                }
                .pickerStyle(.segmented)
                .disabled(model.isRecording || model.isWorking)

                Text(modeHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
                RecordButton(model: model)
                status
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)

                if let text = model.lastText {
                    ResultCard(text: text)
                }
            }
            .padding()
            .navigationTitle("InfiniTypes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProjectMenu(model: model)
                }
            }
        }
        .onChange(of: pending.mode, initial: true) { startPendingDictation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startPendingDictation() }
        }
    }

    private var modeHint: String {
        switch model.mode {
        case .prompt: "Fale do jeito que você pensa: sai um prompt organizado para a IA de codificação."
        case .literal: "Só limpa a fala: tira vícios e repetições, mantendo as suas palavras."
        case .revision: "Copie o texto antes. Depois dite o que mudar: a versão revisada volta para a área de transferência."
        }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .idle:
            Text(model.settings.hasAPIKey ? "Toque para gravar" : "Toque para gravar. Sem a chave da API, o texto sai sem refinar.")
                .foregroundStyle(.secondary)
        case .recording:
            Text("Ouvindo… toque para parar").foregroundStyle(.red)
        case .working(let message):
            Label(message, systemImage: "ellipsis").foregroundStyle(.secondary)
        case .finished(let message):
            Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    /// Pedidos vindos do Botão de Ação, da Central de Controle ou dos Atalhos.
    private func startPendingDictation() {
        guard let trigger = pending.take() else { return }
        let mode: DictationMode = switch trigger {
        case .prompt: .prompt
        case .literal: .literal
        case .revision: .revision
        }
        Task { await model.start(mode: mode) }
    }
}

private struct RecordButton: View {
    let model: DictationModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !model.isRecording)) { _ in
            let level = CGFloat(model.isRecording ? model.level : 0)
            Button {
                model.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(model.isRecording ? Color.red.opacity(0.18) : Color.accentColor.opacity(0.12))
                        .scaleEffect(1 + level * 0.35)
                    Circle()
                        .fill(model.isRecording ? Color.red : Color.accentColor)
                        .padding(28)
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 200, height: 200)
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking)
            .accessibilityLabel(model.isRecording ? "Parar e processar" : "Começar a gravar")
        }
    }
}

private struct ResultCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Último resultado").font(.headline)
                Spacer()
                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
            }
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Escolha do projeto do glossário, lembrada entre um ditado e outro.
private struct ProjectMenu: View {
    @Bindable var model: DictationModel

    var body: some View {
        let projects = model.glossary.glossary.projects
            .map { $0.name.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Menu {
            Picker("Projeto", selection: $model.projectName) {
                Text("Nenhum projeto").tag(String?.none)
                ForEach(projects, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            Label(model.projectName ?? "Projeto", systemImage: "folder")
        }
    }
}
