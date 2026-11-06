import Foundation

enum AppPaths {
    /// `~/Library/Application Support/InfinidimTypes`, criada se ainda não existir.
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appending(path: "InfinidimTypes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
