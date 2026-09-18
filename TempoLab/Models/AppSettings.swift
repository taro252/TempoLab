import Foundation

nonisolated struct AppSettings: Codable, Equatable, Sendable {
    static let bpmRange = 30...300
    static let `default` = AppSettings()

    let bpm: Int
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    let accentPatterns: AccentPatternLibrary
    let clickSoundSettings: ClickSoundSettings
    let keepScreenAwake: Bool

    init(
        bpm: Int = 120,
        timeSignature: TimeSignature = .fourFour,
        subdivision: Subdivision = .quarter,
        accentPatterns: AccentPatternLibrary = AccentPatternLibrary(),
        clickSoundSettings: ClickSoundSettings = .default,
        keepScreenAwake: Bool = false
    ) {
        self.bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        self.timeSignature = TimeSignature.supported.contains(timeSignature)
            ? timeSignature
            : .fourFour
        self.subdivision = subdivision
        self.accentPatterns = accentPatterns.validated()
        self.clickSoundSettings = ClickSoundSettings(
            normalFrequency: clickSoundSettings.normalFrequency,
            accentFrequency: clickSoundSettings.accentFrequency,
            volume: clickSoundSettings.volume,
            soundType: clickSoundSettings.soundType
        )
        self.keepScreenAwake = keepScreenAwake
    }

    private enum CodingKeys: String, CodingKey {
        case bpm
        case timeSignature
        case subdivision
        case accentPatterns
        case clickSoundSettings
        case keepScreenAwake
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.default

        let decodedBPM = (try? container.decode(Int.self, forKey: .bpm)) ?? defaults.bpm
        let decodedTimeSignature = (
            try? container.decode(TimeSignature.self, forKey: .timeSignature)
        ) ?? defaults.timeSignature
        let decodedSubdivision = (
            try? container.decode(Subdivision.self, forKey: .subdivision)
        ) ?? defaults.subdivision
        let decodedAccentPatterns = (
            try? container.decode(AccentPatternLibrary.self, forKey: .accentPatterns)
        ) ?? defaults.accentPatterns
        let decodedClickSettings = (
            try? container.decode(ClickSoundSettings.self, forKey: .clickSoundSettings)
        ) ?? defaults.clickSoundSettings
        let decodedKeepScreenAwake = (
            try? container.decode(Bool.self, forKey: .keepScreenAwake)
        ) ?? defaults.keepScreenAwake

        self.init(
            bpm: decodedBPM,
            timeSignature: decodedTimeSignature,
            subdivision: decodedSubdivision,
            accentPatterns: decodedAccentPatterns,
            clickSoundSettings: decodedClickSettings,
            keepScreenAwake: decodedKeepScreenAwake
        )
    }
}
