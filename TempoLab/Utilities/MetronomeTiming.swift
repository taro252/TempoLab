import Foundation

nonisolated enum MetronomeTiming {
    static func samplesPerBeat(bpm: Int, sampleRate: Double) -> Double {
        precondition(bpm > 0)
        precondition(sampleRate > 0)
        return sampleRate * 60.0 / Double(bpm)
    }

    static func samplePosition(forBeat beatIndex: Int, bpm: Int, sampleRate: Double) -> Int64 {
        precondition(beatIndex >= 0)
        return Int64((Double(beatIndex) * samplesPerBeat(bpm: bpm, sampleRate: sampleRate)).rounded())
    }

    static func samplesPerSubdivision(
        bpm: Int,
        sampleRate: Double,
        subdivision: Subdivision
    ) -> Double {
        samplesPerBeat(bpm: bpm, sampleRate: sampleRate)
            / Double(subdivision.divisionsPerBeat)
    }

    static func lookAheadStepCount(
        bpm: Int,
        subdivision: Subdivision,
        minimumBeats: Int,
        minimumSeconds: Double
    ) -> Int {
        precondition(bpm > 0 && minimumBeats > 0 && minimumSeconds > 0)
        let stepsPerBeat = subdivision.divisionsPerBeat
        let stepsForDuration = Int(
            ceil(minimumSeconds * Double(bpm * stepsPerBeat) / 60)
        )
        return max(minimumBeats * stepsPerBeat, stepsForDuration)
    }

    static func samplePosition(
        forSubdivision subdivisionIndex: Int64,
        bpm: Int,
        sampleRate: Double,
        subdivision: Subdivision
    ) -> Int64 {
        precondition(subdivisionIndex >= 0)
        let exactPosition = Double(subdivisionIndex) * samplesPerSubdivision(
            bpm: bpm,
            sampleRate: sampleRate,
            subdivision: subdivision
        )
        return Int64(exactPosition.rounded())
    }

    static func framesPerMeasure(bpm: Int, sampleRate: Double, timeSignature: TimeSignature) -> Int64 {
        samplePosition(
            forBeat: timeSignature.numerator,
            bpm: bpm,
            sampleRate: sampleRate
        )
    }

    static func isAccent(beatIndex: Int, timeSignature: TimeSignature) -> Bool {
        precondition(beatIndex >= 0)
        return beatIndex.isMultiple(of: timeSignature.numerator)
    }

    static func nextBeatIndex(after beatIndex: Int, timeSignature: TimeSignature) -> Int {
        precondition(beatIndex >= 0)
        return (beatIndex + 1) % timeSignature.numerator
    }
}
