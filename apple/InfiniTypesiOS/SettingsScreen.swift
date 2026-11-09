import SwiftUI

/// Chave da API, modelo, glossário e o estado do modelo de voz.
struct SettingsScreen: View {
    @Bindable var settings: AppSettings
    @Bindable var glossary: GlossaryStore
    let transcriber: WhisperKitTranscriber
    @State private var key = ""
    @State private var keyError: String?
    @State private var models = AvailableModels()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if settings.hasAPIKey {
                        LabeledContent("Chave", value: "Salva no Keychain")
                        Button("Remover chave", role: .destructive) { save("") }
                    } else {
                        SecureField("sk-ant-…", text: $key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Salvar chave") { save(key) }.disabled(key.isEmpty)
                    }
                    if let keyError { Text(keyError).foregroundStyle(.red) }
                } header: {
                    Text("Chave da API da Anthropic")
                } footer: {
                    Text("Crie uma chave em console.anthropic.com. Ela fica no Keychain deste iPhone e só é enviada para api.anthropic.com.")
                }

                Section("Modelo") {
                    Picker("Modelo", selection: $settings.modelID) {
                        ForEach(models.models) { Text($0.displayName).tag($0.id) }
                        if !models.models.contains(where: { $0.id == settings.modelID }) {
                            Text(settings.modelID).tag(settings.modelID)
                        }
                    }
                    if settings.model.supportsEffort {
                        Picker("Esforço", selection: $settings.effort) {
                            ForEach(Effort.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    if let price = settings.model.priceLabel {
                        Text(price).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextEditor(text: $glossary.glossary.globalTerms)
                        .frame(minHeight: 90)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Glossário: termos globais")
                } footer: {
                    Text("Um termo por linha, com a grafia certa (ex.: Supabase, useAuthStore).")
                }

                Section {
                    ForEach($glossary.glossary.projects) { $project in
                        NavigationLink(project.name.isEmpty ? "Projeto sem nome" : project.name) {
                            ProjectEditor(project: $project)
                        }
                    }
                    .onDelete { glossary.glossary.projects.remove(atOffsets: $0) }
                    Button("Adicionar projeto", systemImage: "plus") { glossary.addProject() }
                } header: {
                    Text("Glossário: projetos")
                } footer: {
                    Text("Escolha o projeto no menu da aba Ditar: os termos dele entram junto com os globais.")
                }

                Section("Modelo de voz") {
                    LabeledContent("Whisper", value: WhisperKitTranscriber.modelVariant
                        .replacingOccurrences(of: "openai_whisper-", with: ""))
                    LabeledContent("Situação", value: voiceStatus)
                }
            }
            .navigationTitle("Ajustes")
            .task { await models.refresh() }
        }
    }

    private var voiceStatus: String {
        switch transcriber.state {
        case .idle: "Aguardando"
        case .downloading(let progress): "Baixando (\(progress.formatted(.percent.precision(.fractionLength(0)))))"
        case .loading: "Carregando"
        case .ready: "Pronto, no aparelho"
        case .failed(let message): "Falhou: \(message)"
        }
    }

    private func save(_ value: String) {
        do {
            try settings.saveAPIKey(value)
            key = ""
            keyError = nil
            Task { await models.refresh() }
        } catch {
            keyError = error.localizedDescription
        }
    }
}

private struct ProjectEditor: View {
    @Binding var project: Glossary.Project

    var body: some View {
        Form {
            Section("Nome") {
                TextField("Nome do projeto", text: $project.name)
            }
            Section {
                TextEditor(text: $project.terms)
                    .frame(minHeight: 160)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Termos")
            } footer: {
                Text("Um por linha.")
            }
        }
        .navigationTitle(project.name.isEmpty ? "Projeto" : project.name)
    }
}
