import Foundation

struct TapTempoCalculator {
    private let maximumIntervalCount: Int
    private let sessionTimeout: TimeInterval
    private let bpmRange: ClosedRange<Int>

    private var lastTapTime: TimeInterval?
    private var intervals: [TimeInterval] = []

    init(
        maximumIntervalCount: Int = 8,
        sessionTimeout: TimeInterval = 2.0,
        bpmRange: ClosedRange<Int> = 30...300
    ) {
        self.maximumIntervalCount = maximumIntervalCount
        self.sessionTimeout = sessionTimeout
        self.bpmRange = bpmRange
    }

    mutating func registerTap(at time: TimeInterval) -> Int? {
        guard let lastTapTime else {
            self.lastTapTime = time
            return nil
        }

        let interval = time - lastTapTime
        self.lastTapTime = time

        guard interval > 0, interval < sessionTimeout else {
            intervals.removeAll(keepingCapacity: true)
            return nil
        }

        intervals.append(interval)
        if intervals.count > maximumIntervalCount {
            intervals.removeFirst(intervals.count - maximumIntervalCount)
        }

        let medianInterval = median(of: intervals)
        let calculatedBPM = Int((60.0 / medianInterval).rounded())
        return min(max(calculatedBPM, bpmRange.lowerBound), bpmRange.upperBound)
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2

        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2
        }

        return sortedValues[middleIndex]
    }
}
