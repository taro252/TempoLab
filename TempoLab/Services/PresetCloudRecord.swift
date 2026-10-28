import CloudKit
import Foundation

/// CloudKit固有の形式は境界で変換し、マージ規則から切り離す。
nonisolated enum PresetCloudRecord: Equatable, Sendable {
    static let containerIdentifier = "iCloud.app.merodoa.PiTempo"
    static let zoneID = CKRecordZone.ID(zoneName: "TempoPresets")
    case preset(PresetSyncRecord)
    case order(PresetOrderRecord)

    var recordName: String {
        switch self {
        case .preset(let value): value.id.uuidString
        case .order: PresetOrderRecord.recordName
        }
    }

    init(record: CKRecord) throws {
        guard record.recordID.zoneID == Self.zoneID,
              (record["schemaVersion"] as? NSNumber)?.intValue == 1,
              let counter = (record["revision"] as? NSNumber)?.int64Value, counter >= 0,
              let writer = record["writerID"] as? String, !writer.isEmpty else {
            throw PresetSyncError.invalidRecord
        }
        let revision = PresetRevision(counter: counter, writerID: writer)
        switch record.recordType {
        case "TempoPreset":
            guard let id = UUID(uuidString: record.recordID.recordName),
                  record["uuid"] as? String == id.uuidString,
                  let deleted = record["isDeleted"] as? NSNumber else { throw PresetSyncError.invalidRecord }
            let preset: MetronomePreset?
            if let data = record["presetJSON"] as? Data {
                preset = try JSONDecoder().decode(MetronomePreset.self, from: data)
            } else {
                preset = nil
            }
            let value = PresetSyncRecord(
                id: id, preset: preset, revision: revision,
                isDeleted: deleted.boolValue, deletedAt: record["deletedAt"] as? Date
            )
            guard value.isValid else { throw PresetSyncError.invalidRecord }
            self = .preset(value)
        case "TempoPresetOrder":
            guard record.recordID.recordName == PresetOrderRecord.recordName,
                  let strings = record["orderedIDs"] as? [String] else { throw PresetSyncError.invalidRecord }
            let ids = strings.compactMap(UUID.init(uuidString:))
            guard ids.count == strings.count, Set(ids).count == ids.count else { throw PresetSyncError.invalidRecord }
            self = .order(PresetOrderRecord(orderedIDs: ids, revision: revision))
        default:
            throw PresetSyncError.invalidRecord
        }
    }

    func makeRecord(systemFields: Data? = nil) throws -> CKRecord {
        let id = CKRecord.ID(recordName: recordName, zoneID: Self.zoneID)
        let type: String
        let revision: PresetRevision
        switch self {
        case .preset(let value): type = "TempoPreset"; revision = value.revision
        case .order(let value): type = "TempoPresetOrder"; revision = value.revision
        }
        let record: CKRecord
        if let systemFields {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            unarchiver.requiresSecureCoding = true
            defer { unarchiver.finishDecoding() }
            guard let restored = CKRecord(coder: unarchiver), restored.recordID == id, restored.recordType == type else {
                throw PresetSyncError.invalidRecord
            }
            record = restored
        } else {
            record = CKRecord(recordType: type, recordID: id)
        }
        record["schemaVersion"] = 1 as NSNumber
        record["revision"] = revision.counter as NSNumber
        record["writerID"] = revision.writerID as NSString
        switch self {
        case .preset(let value):
            record["uuid"] = value.id.uuidString as NSString
            record["presetJSON"] = try value.preset.map { try JSONEncoder().encode($0) } as NSData?
            record["isDeleted"] = value.isDeleted as NSNumber
            record["deletedAt"] = value.deletedAt as NSDate?
        case .order(let value):
            record["orderedIDs"] = value.orderedIDs.map(\.uuidString) as NSArray
        }
        return record
    }

    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}

nonisolated extension PresetSyncPartition {
    var pendingCloudRecords: [PresetCloudRecord] {
        pending.sorted().compactMap { name in
            if name == PresetOrderRecord.recordName { return order.map(PresetCloudRecord.order) }
            return records[name].map(PresetCloudRecord.preset)
        }
    }
}
