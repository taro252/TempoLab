import Foundation

nonisolated enum BPMInputParser {
    static func parse(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return nil }
        return min(max(value, AppSettings.bpmRange.lowerBound), AppSettings.bpmRange.upperBound)
    }
}
