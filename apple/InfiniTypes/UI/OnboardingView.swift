import SwiftUI

struct OnboardingView: View {
    let permissions: PermissionsManager
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bem-vindo ao InfiniTypes")
                    .font(.title2.bold())
                Text("Para transformar sua fala em prompts, o app precisa de duas permissões.")
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                title: "Microfone",
                detail: "Grava sua voz apenas enquanto você segura o atalho.",
                systemImage: "mic.fill",
                status: permissions.microphone
            ) {
                Task { await permissions.requestMicrophone() }
            }

            PermissionRow(
                title: "Acessibilidade",
                detail: "Detecta o atalho global e cola o texto no campo em foco.",
                systemImage: "accessibility",
                status: permissions.accessibility
            ) {
                permissions.requestAccessibility()
            }

            HStack {
                Spacer()
                Button(permissions.allGranted ? "Concluir" : "Continuar depois", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let status: PermissionsManager.Status
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if status == .granted {
                Label("Permitido", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Permitir…", action: request)
            }
        }
    }
}
