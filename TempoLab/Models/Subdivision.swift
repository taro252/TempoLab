import Foundation

nonisolated enum Subdivision: String, CaseIterable, Codable, Identifiable, Sendable {
    case quarter
    case eighth
    case triplet
    case sixteenth

    var id: Self { self }

    var divisionsPerBeat: Int {
        switch self {
        case .quarter: 1
        case .eighth: 2
        case .triplet: 3
        case .sixteenth: 4
        }
    }

    var symbol: String {
        switch self {
        case .quarter: "♩"
        case .eighth: "♪"
        case .triplet: "3"
        case .sixteenth: "16"
        }
    }

    var displayName: String {
        switch self {
        case .quarter: String(localized: "Quarter")
        case .eighth: String(localized: "8th")
        case .triplet: String(localized: "Triplet")
        case .sixteenth: String(localized: "16th")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .quarter: String(localized: "4分音符")
        case .eighth: String(localized: "8分音符")
        case .triplet: String(localized: "3連符")
        case .sixteenth: String(localized: "16分音符")
        }
    }

    func stepLabel(at indexInBeat: Int) -> String {
        precondition((0..<divisionsPerBeat).contains(indexInBeat))

        switch self {
        case .quarter:
            return ""
        case .eighth:
            return indexInBeat == 0 ? "" : "&"
        case .triplet:
            return ["", "trip", "let"][indexInBeat]
        case .sixteenth:
            return ["", "e", "&", "a"][indexInBeat]
        }
    }
}
