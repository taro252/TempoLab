import Foundation

nonisolated protocol SettingsStoring: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

nonisolated final class SettingsStore: SettingsStoring, @unchecked Sendable {
    static let storageKey = "appSettings"

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = SettingsStore.storageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() -> AppSettings {
        guard let data = userDefaults.data(forKey: storageKey),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
