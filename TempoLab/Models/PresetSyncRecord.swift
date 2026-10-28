import Foundation

/// 端末の時計を使わず、観測済みの最大値に1を加えて変更を識別する。
nonisolated struct PresetRevision: Codable, Equatable, Comparable, Sendable {
    var counter: Int64
    var writerID: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.writerID < rhs.writerID : lhs.counter < rhs.counter
    }
}

nonisolated struct PresetSyncRecord: Codable, Equatable, Sendable {
    let id: UUID
    var preset: MetronomePreset?
    var revision: PresetRevision
    var isDeleted = false
    var deletedAt: Date?

    var isValid: Bool {
        revision.counter >= 0 && !revision.writerID.isEmpty
            && (isDeleted || preset?.id == id)
    }

    /// 同じUUIDの削除は永久に優先する。作り直す場合は新しいUUIDを使う。
    func merged(with other: Self) -> Self {
        guard id == other.id else { return self }
        if isDeleted != other.isDeleted { return isDeleted ? self : other }
        if revision != other.revision { return revision > other.revision ? self : other }
        // 同一リビジョンで内容が異なる不正データにも、端末によらない結果を与える。
        return canonicalData.lexicographicallyPrecedes(other.canonicalData) ? other : self
    }

    private var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }
}

nonisolated struct PresetOrderRecord: Codable, Equatable, Sendable {
    static let recordName = "preset-order"
    var orderedIDs: [UUID]
    var revision: PresetRevision

    func merged(with other: Self) -> Self {
        if revision != other.revision { return revision > other.revision ? self : other }
        return orderedIDs.map(\.uuidString).joined() > other.orderedIDs.map(\.uuidString).joined() ? self : other
    }
}

nonisolated struct PresetSyncPartition: Codable, Equatable, Sendable {
    var records: [String: PresetSyncRecord] = [:]
    var order: PresetOrderRecord?
    var pending: Set<String> = []
    var systemFields: [String: Data] = [:]
    var engineState: Data?
    var logicalClock: Int64 = 0
    var initialFetchComplete = false
    var lastSyncDate: Date?

    var presets: [MetronomePreset] {
        let available = records.values.filter { !$0.isDeleted }.compactMap(\.preset)
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        var seen = Set<UUID>()
        let ids = (order?.orderedIDs ?? []) + available.map(\.id).sorted { $0.uuidString < $1.uuidString }
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return byID[id]
        }
    }
}

nonisolated struct PresetSyncDocument: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var writerID = UUID().uuidString
    var activeScope = "local"
    var localWasBound = false
    var partitions: [String: PresetSyncPartition] = ["local": PresetSyncPartition()]
}

nonisolated enum PresetMutation: Sendable {
    case insert(MetronomePreset)
    case rename(UUID, String)
    case overwrite(UUID, PresetConfiguration)
    case delete(UUID)
    case reorder([UUID])

    func apply(to presets: inout [MetronomePreset]) throws {
        switch self {
        case .insert(let preset):
            guard !presets.contains(where: { $0.id == preset.id }) else { return }
            presets.append(preset)
        case .rename(let id, let name):
            guard let index = presets.firstIndex(where: { $0.id == id }) else { throw PresetError.notFound }
            try presets[index].rename(name)
        case .overwrite(let id, let configuration):
            guard let index = presets.firstIndex(where: { $0.id == id }) else { throw PresetError.notFound }
            presets[index].configuration = configuration
            presets[index].updatedAt = Date()
        case .delete(let id):
            guard presets.contains(where: { $0.id == id }) else { throw PresetError.notFound }
            presets.removeAll { $0.id == id }
        case .reorder(let ids):
            let byID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0) })
            var seen = Set<UUID>()
            presets = (ids + presets.map(\.id)).compactMap {
                seen.insert($0).inserted ? byID[$0] : nil
            }
        }
    }
}
