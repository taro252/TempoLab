import Foundation

nonisolated struct BPMNumericDraft: Equatable, Sendable {
    private(set) var text: String
    private var replacesCurrentOnNextDigit = true

    init(bpm: Int) {
        text = String(bpm)
    }

    mutating func append(_ digit: Int) {
        guard (0...9).contains(digit) else { return }
        if replacesCurrentOnNextDigit {
            text = String(digit)
            replacesCurrentOnNextDigit = false
        } else if text.count < 3 {
            text.append(String(digit))
        }
    }

    mutating func delete() {
        if replacesCurrentOnNextDigit {
            text = ""
            replacesCurrentOnNextDigit = false
        } else if !text.isEmpty {
            text.removeLast()
        }
    }
}
