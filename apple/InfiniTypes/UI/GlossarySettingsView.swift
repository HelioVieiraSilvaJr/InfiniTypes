import SwiftUI

struct GlossarySettingsView: View {
    @Bindable var store: GlossaryStore
    let currentWindowTitle: String?

    var body: some View {
        Form {
            Section {
                TermsEditor(text: $store.glossary.globalTerms)
            } header: {
                Text("Termos globais")
            } footer: {
                Text("Um termo por linha, com a grafia correta (ex.: `useEffect`, Supabase, `auth.routes.ts`). Ajudam o Whisper a reconhecer e o Claude a corrigir. Valem para todos os ditados.")
            }

            Section {
                ForEach($store.glossary.projects) { $project in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Nome do projeto", text: $project.name, prompt: Text("Nome como aparece na janela"))
                            Button(role: .destructive) {
                                store.removeProject(id: project.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remover projeto")
                        }
                        TermsEditor(text: $project.terms)
                    }
                    .padding(.vertical, 4)
                }
                Button("Adicionar projeto", systemImage: "plus") {
                    store.addProject()
                }
            } header: {
                Text("Projetos")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Os termos de um projeto entram quando o nome dele aparece no título da janela, como em “users.ts — minha-api”.")
                    if let currentWindowTitle {
                        Text("Janela em que você estava: “\(currentWindowTitle)”")
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TermsEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .frame(minHeight: 70)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }
}
