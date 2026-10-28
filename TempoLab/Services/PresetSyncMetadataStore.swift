import Foundation

nonisolated protocol PresetSyncMetadataStoring: Sendable {
    func load() throws -> PresetSyncDocument?
    func save(_ document: PresetSyncDocument) throws
}

/// 本体、削除記録、送信待ち、CloudKit状態を一つの原子的な置換で保存する。
nonisolated final class PresetSyncMetadataStore: PresetSyncMetadataStoring, @unchecked Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "app.merodoa.PiTempo/PresetSync/state.json")
    }

    func load() throws -> PresetSyncDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let document: PresetSyncDocument
        do {
            document = try JSONDecoder().decode(PresetSyncDocument.self, from: Data(contentsOf: fileURL))
        } catch {
            throw PresetError.unreadableData
        }
        guard document.schemaVersion == 1 else { throw PresetError.unsupportedSchema }
        guard !document.writerID.isEmpty, document.partitions[document.activeScope] != nil,
              document.partitions.values.allSatisfy({ partition in
                  partition.logicalClock >= 0 && partition.records.allSatisfy {
                      $0.key == $0.value.id.uuidString && $0.value.isValid
                  }
              }) else { throw PresetError.unreadableData }
        return document
    }

    func save(_ document: PresetSyncDocument) throws {
        // 読めない／将来の形式を通常操作で上書きしない。
        _ = try load()
        do {
            let data = try JSONEncoder().encode(document)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try Data(contentsOf: fileURL).write(to: fileURL.appendingPathExtension("previous"), options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PresetError.saveFailed
        }
    }
}
