import Foundation

enum AppPaths {
    /// `~/Library/Application Support/InfiniTypes`, criada se ainda não existir.
    /// Nos testes, uma pasta temporária, para nunca tocar no histórico real.
    static let support: URL = {
        let folder: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            folder = FileManager.default.temporaryDirectory.appending(path: "InfiniTypesTests", directoryHint: .isDirectory)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            folder = base.appending(path: "InfiniTypes", directoryHint: .isDirectory)
            LegacyMigration.moveSupportFolder(to: folder)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
