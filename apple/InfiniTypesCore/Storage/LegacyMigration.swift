import Foundation
import OSLog

/// Traz os dados da versão 0.1.0, quando o app se chamava InfinidimTypes: pasta de dados,
/// preferências e chave da API. Pode sair quando ninguém mais tiver a versão antiga.
enum LegacyMigration {
    private static let bundleID = "com.infinidim.InfinidimTypes"
    private static let folderName = "InfinidimTypes"
    private static let doneKey = "migration.infinidimTypes"

    /// Nos testes o app é só o host: não mexe nas preferências nem no Keychain reais.
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// Renomeia a pasta antiga em Application Support para `folder`, se `folder` ainda não existir.
    static func moveSupportFolder(to folder: URL) {
        let fileManager = FileManager.default
        let legacy = folder.deletingLastPathComponent().appending(path: folderName, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: folder.path), fileManager.fileExists(atPath: legacy.path) else { return }
        do {
            try fileManager.moveItem(at: legacy, to: folder)
            Logger.history.notice("Dados de \(folderName, privacy: .public) movidos para \(folder.lastPathComponent, privacy: .public)")
        } catch {
            Logger.history.error("Falha ao mover os dados de \(folderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Copia as preferências e a chave da API do app antigo, uma única vez.
    static func importSettings(keys: [String], into defaults: UserDefaults) {
        guard isEnabled, !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        if let legacyDefaults = UserDefaults(suiteName: bundleID) {
            for key in keys where defaults.object(forKey: key) == nil {
                if let value = legacyDefaults.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
        // O macOS pode pedir permissão para o app novo ler o item criado pelo antigo.
        if KeychainStore.apiKey() == nil, let key = KeychainStore.apiKey(service: bundleID) {
            do {
                try KeychainStore.setAPIKey(key)
                Logger.history.notice("Chave da API trazida de \(folderName, privacy: .public)")
            } catch {
                Logger.history.error("Falha ao copiar a chave da API: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
