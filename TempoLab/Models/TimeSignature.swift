import Foundation

nonisolated struct TimeSignature: Codable, Hashable, Identifiable, Sendable {
    let numerator: Int
    let denominator: Int

    var id: String { displayName }
    var displayName: String { "\(numerator)/\(denominator)" }

    static let twoFour = TimeSignature(numerator: 2, denominator: 4)
    static let threeFour = TimeSignature(numerator: 3, denominator: 4)
    static let fourFour = TimeSignature(numerator: 4, denominator: 4)
    static let fiveFour = TimeSignature(numerator: 5, denominator: 4)
    static let sixEight = TimeSignature(numerator: 6, denominator: 8)

    static let supported: [TimeSignature] = [
        .twoFour,
        .threeFour,
        .fourFour,
        .fiveFour,
        .sixEight,
    ]
}
