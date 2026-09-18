import Foundation

nonisolated struct PlaybackPosition: Equatable, Sendable {
    let beatIndex: Int
    let subdivisionIndex: Int
    let stepIndex: Int
    let timeSignature: TimeSignature
    let subdivision: Subdivision

    init?(
        stepIndex: Int,
        timeSignature: TimeSignature,
        subdivision: Subdivision
    ) {
        let stepCount = AccentPattern.stepCount(
            timeSignature: timeSignature,
            subdivision: subdivision
        )
        guard (0..<stepCount).contains(stepIndex) else { return nil }

        self.beatIndex = stepIndex / subdivision.divisionsPerBeat
        self.subdivisionIndex = stepIndex % subdivision.divisionsPerBeat
        self.stepIndex = stepIndex
        self.timeSignature = timeSignature
        self.subdivision = subdivision
    }
}
