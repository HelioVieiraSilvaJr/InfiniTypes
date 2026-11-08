import Foundation
import Observation

enum Effort: String, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: "Baixa"
        case .medium: "Média"
        case .high: "Alta"
        }
    }
}

/// Preferências do usuário em `UserDefaults`. A chave da API fica no Keychain (`KeychainStore`).
@Observable
final class AppSettings {
    var modelID: String {
        didSet { defaults.set(modelID, forKey: Keys.modelID) }
    }

    var effort: Effort {
        didSet { defaults.set(effort.rawValue, forKey: Keys.effort) }
    }

    /// Espelha a existência da chave no Keychain, para a interface não consultar o Keychain a cada redesenho.
    private(set) var hasAPIKey: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        LegacyMigration.importSettings(keys: [Keys.modelID, Keys.effort], into: defaults)
        modelID = defaults.string(forKey: Keys.modelID) ?? ModelCatalog.defaultModelID
        effort = defaults.string(forKey: Keys.effort).flatMap(Effort.init(rawValue:)) ?? .low
        hasAPIKey = KeychainStore.apiKey() != nil
    }

    var model: RefinementModel { ModelCatalog.model(id: modelID) }

    func saveAPIKey(_ key: String) throws {
        try KeychainStore.setAPIKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        hasAPIKey = KeychainStore.apiKey() != nil
    }

    private enum Keys {
        static let modelID = "refinement.modelID"
        static let effort = "refinement.effort"
    }
}
