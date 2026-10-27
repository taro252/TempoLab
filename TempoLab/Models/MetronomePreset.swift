import Foundation

nonisolated struct PresetConfiguration: Codable, Equatable, Sendable {
    let bpm: Int
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    let accentPattern: AccentPattern
    let clickSoundSettings: ClickSoundSettings

    init(
        bpm: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        accentPattern: AccentPattern,
        clickSoundSettings: ClickSoundSettings
    ) {
        self.bpm = min(max(bpm, AppSettings.bpmRange.lowerBound), AppSettings.bpmRange.upperBound)
        let signature = TimeSignature.supported.contains(timeSignature) ? timeSignature : .fourFour
        self.timeSignature = signature
        self.subdivision = subdivision
        self.accentPattern = accentPattern.isValid
            && accentPattern.timeSignature == signature
            && accentPattern.subdivision == subdivision
            ? accentPattern
            : .defaultPattern(timeSignature: signature, subdivision: subdivision)
        self.clickSoundSettings = ClickSoundSettings(
            normalFrequency: clickSoundSettings.normalFrequency,
            accentFrequency: clickSoundSettings.accentFrequency,
            volume: clickSoundSettings.volume,
            soundType: clickSoundSettings.soundType
        )
    }

    private enum CodingKeys: String, CodingKey {
        case bpm, timeSignature, subdivision, accentPattern, clickSoundSettings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let signature = try values.decode(TimeSignature.self, forKey: .timeSignature)
        let subdivision = (try? values.decode(Subdivision.self, forKey: .subdivision)) ?? .quarter
        let pattern = (try? values.decode(AccentPattern.self, forKey: .accentPattern))
            ?? .defaultPattern(timeSignature: .fourFour, subdivision: subdivision)
        self.init(
            bpm: try values.decode(Int.self, forKey: .bpm),
            timeSignature: signature,
            subdivision: subdivision,
            accentPattern: pattern,
            clickSoundSettings: try values.decode(ClickSoundSettings.self, forKey: .clickSoundSettings)
        )
    }
}

nonisolated struct MetronomePreset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    private(set) var name: String
    var configuration: PresetConfiguration
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        configuration: PresetConfiguration,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) throws {
        self.id = id
        self.name = try Self.validatedName(name)
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    mutating func rename(_ name: String) throws {
        self.name = try Self.validatedName(name)
        updatedAt = Date()
    }

    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.emptyName }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, configuration, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            configuration: values.decode(PresetConfiguration.self, forKey: .configuration),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt)
        )
    }
}

nonisolated enum PresetError: Error, LocalizedError, Sendable {
    case emptyName
    case notFound
    case unreadableData
    case unsupportedSchema
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .emptyName: String(localized: "プリセット名を入力してください。")
        case .notFound: String(localized: "プリセットが見つかりません。")
        case .unreadableData: String(localized: "プリセットを読み込めませんでした。保存データは保持されています。")
        case .unsupportedSchema: String(localized: "このバージョンでは読み込めないプリセットです。保存データは保持されています。")
        case .saveFailed: String(localized: "プリセットを保存できませんでした。")
        }
    }
}
