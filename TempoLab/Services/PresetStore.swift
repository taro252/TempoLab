import Foundation

nonisolated struct PresetLoadResult: Sendable {
    var presets: [MetronomePreset] = []
    var skippedRecordCount = 0
}

nonisolated protocol PresetStoring: Sendable {
    func load() throws -> PresetLoadResult
    func save(_ presets: [MetronomePreset]) throws
    func apply(_ mutation: PresetMutation) throws -> [MetronomePreset]
}

nonisolated extension PresetStoring {
    func apply(_ mutation: PresetMutation) throws -> [MetronomePreset] {
        var presets = try load().presets
        try mutation.apply(to: &presets)
        try save(presets)
        return presets
    }
}

nonisolated final class PresetStore: PresetStoring, @unchecked Sendable {
    static let storageKey = "metronomePresets.v1"
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    init(userDefaults: UserDefaults = .standard, storageKey: String = PresetStore.storageKey) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func load() throws -> PresetLoadResult {
        try lock.withLock { try loadStoredData() }
    }

    func save(_ presets: [MetronomePreset]) throws {
        try lock.withLock {
            // 新しいスキーマや読めないデータを、空の一覧で上書きしない。
            _ = try loadStoredData()
            let data: Data
            do {
                data = try JSONEncoder().encode(Container(schemaVersion: 1, presets: presets))
            } catch {
                throw PresetError.saveFailed
            }
            userDefaults.set(data, forKey: storageKey)
            guard userDefaults.data(forKey: storageKey) == data else {
                throw PresetError.saveFailed
            }
        }
    }

    private func loadStoredData() throws -> PresetLoadResult {
        guard userDefaults.object(forKey: storageKey) != nil else { return PresetLoadResult() }
        guard let data = userDefaults.data(forKey: storageKey),
              let header = try? JSONDecoder().decode(Header.self, from: data) else {
            throw PresetError.unreadableData
        }
        guard header.schemaVersion == 1 else { throw PresetError.unsupportedSchema }
        guard let container = try? JSONDecoder().decode(RecoverableContainer.self, from: data) else {
            throw PresetError.unreadableData
        }
        var result = PresetLoadResult()
        var ids = Set<UUID>()
        for record in container.presets {
            if let preset = record.preset, ids.insert(preset.id).inserted {
                result.presets.append(preset)
            } else {
                result.skippedRecordCount += 1
            }
        }
        return result
    }

    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private struct Container: Encodable {
        let schemaVersion: Int
        let presets: [MetronomePreset]
    }

    private struct RecoverableContainer: Decodable {
        let presets: [Record]
    }

    private struct Record: Decodable {
        let preset: MetronomePreset?

        init(from decoder: Decoder) throws {
            preset = try? MetronomePreset(from: decoder)
        }
    }
}
