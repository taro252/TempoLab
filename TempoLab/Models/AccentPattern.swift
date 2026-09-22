import Foundation

nonisolated enum StepEmphasis: String, CaseIterable, Codable, Sendable {
    case accent
    case normal
    case mute

    var next: Self {
        switch self {
        case .accent: .normal
        case .normal: .mute
        case .mute: .accent
        }
    }

    var symbol: String {
        switch self {
        case .accent: "●"
        case .normal: "○"
        case .mute: "×"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .accent: String(localized: "アクセント")
        case .normal: String(localized: "通常")
        case .mute: String(localized: "ミュート")
        }
    }

    var isAudible: Bool { self != .mute }
}

nonisolated struct AccentPattern: Codable, Equatable, Sendable {
    let timeSignature: TimeSignature
    let subdivision: Subdivision
    private(set) var steps: [StepEmphasis]

    var expectedStepCount: Int {
        Self.stepCount(timeSignature: timeSignature, subdivision: subdivision)
    }

    var isValid: Bool {
        TimeSignature.supported.contains(timeSignature)
            && steps.count == expectedStepCount
    }

    init(
        timeSignature: TimeSignature,
        subdivision: Subdivision,
        steps: [StepEmphasis]? = nil
    ) {
        self.timeSignature = timeSignature
        self.subdivision = subdivision
        let expectedCount = Self.stepCount(
            timeSignature: timeSignature,
            subdivision: subdivision
        )

        if let steps, steps.count == expectedCount {
            self.steps = steps
        } else {
            self.steps = Self.defaultSteps(count: expectedCount)
        }
    }

    mutating func cycleStep(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index] = steps[index].next
    }

    func emphasis(at index: Int) -> StepEmphasis {
        guard !steps.isEmpty else { return .normal }
        return steps[index % steps.count]
    }

    static func stepCount(
        timeSignature: TimeSignature,
        subdivision: Subdivision
    ) -> Int {
        timeSignature.numerator * subdivision.divisionsPerBeat
    }

    static func defaultPattern(
        timeSignature: TimeSignature,
        subdivision: Subdivision
    ) -> Self {
        Self(timeSignature: timeSignature, subdivision: subdivision)
    }

    private static func defaultSteps(count: Int) -> [StepEmphasis] {
        guard count > 0 else { return [] }
        return [.accent] + Array(repeating: .normal, count: count - 1)
    }
}

nonisolated struct AccentPatternLibrary: Codable, Equatable, Sendable {
    private var patternsByKey: [String: AccentPattern]

    init(patternsByKey: [String: AccentPattern] = [:]) {
        self.patternsByKey = patternsByKey
    }

    func pattern(
        for timeSignature: TimeSignature,
        subdivision: Subdivision
    ) -> AccentPattern {
        let key = Self.key(timeSignature: timeSignature, subdivision: subdivision)
        guard let stored = patternsByKey[key],
              stored.timeSignature == timeSignature,
              stored.subdivision == subdivision,
              stored.isValid else {
            return .defaultPattern(
                timeSignature: timeSignature,
                subdivision: subdivision
            )
        }
        return stored
    }

    mutating func setPattern(_ pattern: AccentPattern) {
        guard pattern.isValid else { return }
        patternsByKey[
            Self.key(
                timeSignature: pattern.timeSignature,
                subdivision: pattern.subdivision
            )
        ] = pattern
    }

    func validated() -> Self {
        var result = Self()
        for timeSignature in TimeSignature.supported {
            for subdivision in Subdivision.allCases {
                let key = Self.key(
                    timeSignature: timeSignature,
                    subdivision: subdivision
                )
                guard let pattern = patternsByKey[key],
                      pattern.timeSignature == timeSignature,
                      pattern.subdivision == subdivision,
                      pattern.isValid else { continue }
                result.patternsByKey[key] = pattern
            }
        }
        return result
    }

    private static func key(
        timeSignature: TimeSignature,
        subdivision: Subdivision
    ) -> String {
        "\(timeSignature.numerator)-\(timeSignature.denominator)-\(subdivision.rawValue)"
    }
}
