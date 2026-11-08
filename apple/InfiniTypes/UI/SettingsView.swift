import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let models: AvailableModels
    let transcriber: WhisperKitTranscriber
    let glossary: GlossaryStore
    /// Título da janela em que você estava, para ajudar a nomear projetos no glossário.
    let currentWindowTitle: String?

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings, models: models, transcriber: transcriber)
                .tabItem { Label("Geral", systemImage: "gearshape") }
            GlossarySettingsView(store: glossary, currentWindowTitle: currentWindowTitle)
                .tabItem { Label("Glossário", systemImage: "character.book.closed") }
        }
        .frame(width: 580, height: 620)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let models: AvailableModels
    let transcriber: WhisperKitTranscriber

    @State private var draftKey = ""
    @State private var keyMessage: String?
    @State private var isValidatingKey = false

    var body: some View {
        Form {
            Section("Chave da API da Anthropic") {
                if settings.hasAPIKey {
                    Label("Chave salva no Keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                SecureField(settings.hasAPIKey ? "Nova chave (substitui a atual)" : "sk-ant-…", text: $draftKey)
                    .onSubmit { Task { await saveKey() } }
                HStack {
                    Link("Criar uma chave no Console", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    Spacer()
                    if settings.hasAPIKey {
                        Button("Remover", role: .destructive) {
                            try? settings.saveAPIKey("")
                            keyMessage = nil
                        }
                    }
                    Button("Salvar") { Task { await saveKey() } }
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty || isValidatingKey)
                }
                if let keyMessage {
                    Text(keyMessage).font(.callout).foregroundStyle(.secondary)
                }
                Text("O uso da API é cobrado à parte da assinatura do Claude.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Refinamento") {
                Picker("Modelo", selection: $settings.modelID) {
                    ForEach(models.models) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                if let price = settings.model.priceLabel {
                    LabeledContent("Preço", value: price)
                }
                Picker("Raciocínio", selection: $settings.effort) {
                    ForEach(Effort.allCases) { effort in
                        Text(effort.label).tag(effort)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.model.supportsEffort)
                HStack {
                    Group {
                        if let error = models.lastError {
                            Text(error).foregroundStyle(.red)
                        } else if let count = models.accountModelCount {
                            Text("\(count) modelos disponíveis na sua conta")
                        } else {
                            Text("Raciocínio mais baixo deixa o prompt pronto mais rápido.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button("Atualizar lista") { Task { await models.refresh() } }
                        .disabled(!settings.hasAPIKey || models.isLoading)
                }
            }

            Section("Ditado") {
                LabeledContent("Prompt", value: "Segure o ⌥ direito")
                LabeledContent("Literal (só limpa)", value: "Segure o ⌘ direito")
                LabeledContent("Revisar seleção", value: "Toque e segure o ⌥ direito")
                LabeledContent("Cancelar", value: "Outra tecla enquanto segura")
                LabeledContent("Modelo de voz", value: transcriber.state.label)
            }
        }
        .formStyle(.grouped)
    }

    private func saveKey() async {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isValidatingKey = true
        defer { isValidatingKey = false }
        do {
            // Listar modelos valida a chave sem custo.
            _ = try await AnthropicClient(apiKey: key).listModels()
            try settings.saveAPIKey(key)
            draftKey = ""
            keyMessage = "Chave válida e salva."
            await models.refresh()
        } catch {
            keyMessage = "Não foi possível validar a chave: \(error.localizedDescription)"
        }
    }
}

extension WhisperKitTranscriber.State {
    var label: String {
        switch self {
        case .idle: "Aguardando"
        case .downloading(let fraction): "Baixando… \(Int(fraction * 100))%"
        case .loading: "Preparando (a primeira vez leva alguns minutos)"
        case .ready: "Pronto · Whisper large-v3-turbo, local"
        case .failed(let message): "Falhou: \(message)"
        }
    }
}
