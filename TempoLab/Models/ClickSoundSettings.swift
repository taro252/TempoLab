import Foundation

nonisolated enum ClickSoundType: String, CaseIterable, Codable, Identifiable, Sendable {
    case sine
    case square
    case wood
    case digital

    var id: Self { self }

    var displayName: String {
        switch self {
        case .sine: String(localized: "Sine")
        case .square: String(localized: "Square")
        case .wood: String(localized: "Wood")
        case .digital: String(localized: "Digital")
        }
    }
}

nonisolated struct ClickSoundSettings: Codable, Equatable, Sendable {
    static let normalFrequencyRange = 300...2_000
    static let accentFrequencyRange = 300...3_000
    static let volumeRange = 0.0...1.0

    static let `default` = ClickSoundSettings()

    private(set) var normalFrequency: Int
    private(set) var accentFrequency: Int
    private(set) var volume: Double
    private(set) var soundType: ClickSoundType

    init(
        normalFrequency: Int = 800,
        accentFrequency: Int = 1_200,
        volume: Double = 0.8,
        soundType: ClickSoundType = .sine
    ) {
        self.normalFrequency = Self.clamp(normalFrequency, to: Self.normalFrequencyRange)
        self.accentFrequency = Self.clamp(accentFrequency, to: Self.accentFrequencyRange)
        self.volume = volume.isFinite
            ? min(max(volume, Self.volumeRange.lowerBound), Self.volumeRange.upperBound)
            : Self.defaultVolume
        self.soundType = soundType
    }

    func updatingNormalFrequency(_ value: Int) -> Self {
        Self(normalFrequency: value, accentFrequency: accentFrequency, volume: volume, soundType: soundType)
    }

    func updatingAccentFrequency(_ value: Int) -> Self {
        Self(normalFrequency: normalFrequency, accentFrequency: value, volume: volume, soundType: soundType)
    }

    func updatingVolume(_ value: Double) -> Self {
        Self(normalFrequency: normalFrequency, accentFrequency: accentFrequency, volume: value, soundType: soundType)
    }

    func updatingSoundType(_ value: ClickSoundType) -> Self {
        Self(normalFrequency: normalFrequency, accentFrequency: accentFrequency, volume: volume, soundType: value)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static let defaultVolume = 0.8
}
