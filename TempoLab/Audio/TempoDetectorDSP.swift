import Accelerate
import Foundation

nonisolated final class TempoDetectorDSP {
    private let configuration: TempoDetectionConfiguration
    private let fft: TempoFFT
    private var sampleRate = 0.0
    private var circularSamples: [Float]
    private var circularWriteIndex = 0
    private var totalSampleCount = 0
    private var samplesSinceFrame = 0
    private var frameSamples: [Float]
    private var currentMagnitudes: [Float]
    private var previousMagnitudes: [Float]
    private var fluxHistory: [Double] = []
    private var rmsHistory: [Double] = []
    private var framesSinceAnalysis = 0
    private var recentBPMs: [Double] = []
    private(set) var didAnalyzeCurrentProcess = false

    init(configuration: TempoDetectionConfiguration = .init()) {
        self.configuration = configuration
        fft = TempoFFT(size: configuration.fftSize)
        circularSamples = .init(repeating: 0, count: configuration.fftSize)
        frameSamples = .init(repeating: 0, count: configuration.fftSize)
        currentMagnitudes = .init(repeating: 0, count: configuration.fftSize / 2)
        previousMagnitudes = .init(repeating: 0, count: configuration.fftSize / 2)
        fluxHistory.reserveCapacity(2_048)
        rmsHistory.reserveCapacity(2_048)
    }

    func reset() {
        sampleRate = 0
        circularSamples.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        circularWriteIndex = 0
        totalSampleCount = 0
        samplesSinceFrame = 0
        previousMagnitudes.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        fluxHistory.removeAll(keepingCapacity: true)
        rmsHistory.removeAll(keepingCapacity: true)
        framesSinceAnalysis = 0
        recentBPMs.removeAll(keepingCapacity: true)
        didAnalyzeCurrentProcess = false
    }

    func process(
        samples: UnsafeBufferPointer<Float>,
        sampleRate newSampleRate: Double
    ) -> TempoDetectionResult? {
        guard newSampleRate > 0, !samples.isEmpty else { return nil }
        didAnalyzeCurrentProcess = false
        if sampleRate != 0, abs(sampleRate - newSampleRate) > 1 {
            reset()
        }
        sampleRate = newSampleRate

        var latestResult: TempoDetectionResult?
        for sample in samples {
            circularSamples[circularWriteIndex] = sample.isFinite ? sample : 0
            circularWriteIndex = (circularWriteIndex + 1) % configuration.fftSize
            totalSampleCount += 1
            samplesSinceFrame += 1

            guard totalSampleCount >= configuration.fftSize else { continue }
            if totalSampleCount == configuration.fftSize {
                samplesSinceFrame = 0
            } else {
                guard samplesSinceFrame >= configuration.hopSize else { continue }
                samplesSinceFrame -= configuration.hopSize
            }
            copyCurrentFrame()
            processCurrentFrame()
            framesSinceAnalysis += 1

            let envelopeRate = sampleRate / Double(configuration.hopSize)
            let analysisFrameInterval = max(
                1,
                Int((configuration.analysisInterval * envelopeRate).rounded())
            )
            if framesSinceAnalysis >= analysisFrameInterval {
                framesSinceAnalysis = 0
                didAnalyzeCurrentProcess = true
                latestResult = analyzeCurrentHistory()
            }
        }
        return latestResult
    }

    func currentResult() -> TempoDetectionResult? {
        analyzeCurrentHistory()
    }

    static func analyze(
        samples: [Float],
        sampleRate: Double,
        configuration: TempoDetectionConfiguration = .init()
    ) -> TempoDetectionResult? {
        let analyzer = TempoDetectorDSP(configuration: configuration)
        samples.withUnsafeBufferPointer {
            _ = analyzer.process(samples: $0, sampleRate: sampleRate)
        }
        return analyzer.currentResult()
    }

    private func copyCurrentFrame() {
        let tailCount = configuration.fftSize - circularWriteIndex
        frameSamples.withUnsafeMutableBufferPointer { destination in
            circularSamples.withUnsafeBufferPointer { source in
                destination.baseAddress?.update(
                    from: source.baseAddress! + circularWriteIndex,
                    count: tailCount
                )
                destination.baseAddress?.advanced(by: tailCount).update(
                    from: source.baseAddress!,
                    count: circularWriteIndex
                )
            }
        }
    }

    private func processCurrentFrame() {
        var mean: Float = 0
        vDSP_meanv(frameSamples, 1, &mean, vDSP_Length(frameSamples.count))
        var negativeMean = -mean
        vDSP_vsadd(
            frameSamples,
            1,
            &negativeMean,
            &frameSamples,
            1,
            vDSP_Length(frameSamples.count)
        )

        var sumSquares: Float = 0
        vDSP_svesq(frameSamples, 1, &sumSquares, vDSP_Length(frameSamples.count))
        let rms = sqrt(Double(sumSquares) / Double(frameSamples.count))
        rmsHistory.append(rms)

        fft.magnitudes(of: &frameSamples, output: &currentMagnitudes)
        let binWidth = sampleRate / Double(configuration.fftSize)
        let lowerBin = max(1, Int(configuration.minimumFrequency / binWidth))
        let upperBin = min(
            currentMagnitudes.count - 1,
            Int(configuration.maximumFrequency / binWidth)
        )

        var flux = 0.0
        if lowerBin <= upperBin {
            for bin in lowerBin...upperBin {
                let current = log1p(Double(currentMagnitudes[bin]) * 10)
                let previous = log1p(Double(previousMagnitudes[bin]) * 10)
                flux += max(current - previous, 0)
            }
            flux /= Double(upperBin - lowerBin + 1)
        }
        currentMagnitudes.withUnsafeBufferPointer { source in
            previousMagnitudes.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: source.baseAddress!, count: source.count)
            }
        }
        fluxHistory.append(flux)
        trimHistoryIfNeeded()
    }

    private func trimHistoryIfNeeded() {
        let envelopeRate = sampleRate / Double(configuration.hopSize)
        let maximumFrames = max(
            1,
            Int((configuration.maximumHistoryDuration * envelopeRate).rounded())
        )
        guard fluxHistory.count > maximumFrames * 2 else { return }
        fluxHistory.removeFirst(fluxHistory.count - maximumFrames)
        rmsHistory.removeFirst(rmsHistory.count - maximumFrames)
    }

    private func analyzeCurrentHistory() -> TempoDetectionResult? {
        guard sampleRate > 0 else { return nil }
        let envelopeRate = sampleRate / Double(configuration.hopSize)
        let minimumFrames = Int(configuration.minimumAnalysisDuration * envelopeRate)
        guard fluxHistory.count >= minimumFrames else { return nil }

        let maximumFrames = Int(configuration.maximumHistoryDuration * envelopeRate)
        let historyCount = min(fluxHistory.count, maximumFrames)
        let flux = Array(fluxHistory.suffix(historyCount))
        let rms = Array(rmsHistory.suffix(historyCount))
        let overallRMS = sqrt(rms.reduce(0) { $0 + $1 * $1 } / Double(max(rms.count, 1)))
        guard overallRMS > 0.0015 else { return nil }

        let onsetEnvelope = adaptiveOnsetEnvelope(flux: flux, envelopeRate: envelopeRate)
        let onsetIndices = onsetPeakIndices(
            envelope: onsetEnvelope,
            envelopeRate: envelopeRate
        )
        guard onsetIndices.count >= 4 else { return nil }

        let lagRange = autocorrelationLagRange(envelopeRate: envelopeRate)
        let correlations = normalizedAutocorrelation(
            envelope: onsetEnvelope,
            lagRange: lagRange
        )
        guard !correlations.isEmpty else { return nil }

        let onsetTempo = tempoFromOnsets(onsetIndices, envelopeRate: envelopeRate)
        let regularity = onsetRegularity(onsetIndices, envelopeRate: envelopeRate)
        var candidates = makeCandidates(
            correlations: correlations,
            lagRange: lagRange,
            envelopeRate: envelopeRate,
            onsetTempo: onsetTempo,
            regularity: regularity
        )
        guard !candidates.isEmpty else { return nil }

        let bestRawScore = candidates[0].score
        let secondScore = candidates.dropFirst().first?.score ?? 0
        let peakCorrelation = correlation(
            forBPM: candidates[0].bpm,
            correlations: correlations,
            lagRange: lagRange,
            envelopeRate: envelopeRate
        )
        guard peakCorrelation >= 0.16 else { return nil }

        let onsetSufficiency = min(Double(onsetIndices.count) / 12, 1)
        let signalQuality = min(max((20 * log10(overallRMS) + 55) / 35, 0), 1)
        let margin = bestRawScore > 0
            ? min(max((bestRawScore - secondScore) / bestRawScore, 0), 1)
            : 0
        let confidence = min(max(
            0.35 * peakCorrelation
                + 0.20 * margin
                + 0.20 * regularity
                + 0.15 * onsetSufficiency
                + 0.10 * signalQuality,
            0
        ), 1)
        guard confidence >= 0.32 else { return nil }

        let stableBPM = stabilizedBPM(candidates[0].bpm)
        if abs(stableBPM - candidates[0].bpm) <= 4 {
            candidates[0] = TempoCandidate(bpm: stableBPM, score: candidates[0].score)
        }
        return TempoDetectionResult(
            bpm: candidates[0].bpm,
            confidence: confidence,
            candidates: Array(candidates.prefix(3))
        )
    }

    private func adaptiveOnsetEnvelope(
        flux: [Double],
        envelopeRate: Double
    ) -> [Double] {
        let windowSize = max(8, Int(envelopeRate.rounded()))
        var result = [Double](repeating: 0, count: flux.count)

        for index in flux.indices {
            let start = max(0, index - windowSize)
            let localValues = Array(flux[start...index])
            let median = Self.median(localValues)
            let deviations = localValues.map { abs($0 - median) }
            let mad = Self.median(deviations)
            let threshold = median + max(1.5 * mad, median * 0.12, 0.000_01)
            result[index] = max(flux[index] - threshold, 0)
        }
        return result
    }

    private func onsetPeakIndices(
        envelope: [Double],
        envelopeRate: Double
    ) -> [Int] {
        guard envelope.count >= 3 else { return [] }
        let minimumDistance = max(1, Int(0.10 * envelopeRate))
        var peaks: [Int] = []

        for index in 1..<(envelope.count - 1) {
            guard envelope[index] > 0,
                  envelope[index] >= envelope[index - 1],
                  envelope[index] > envelope[index + 1] else { continue }

            if let last = peaks.last, index - last < minimumDistance {
                if envelope[index] > envelope[last] {
                    peaks[peaks.count - 1] = index
                }
            } else {
                peaks.append(index)
            }
        }
        return peaks
    }

    private func autocorrelationLagRange(envelopeRate: Double) -> ClosedRange<Int> {
        let minimumLag = max(1, Int(floor(60 * envelopeRate / configuration.bpmRange.upperBound)))
        let maximumLag = max(
            minimumLag,
            Int(ceil(60 * envelopeRate / configuration.bpmRange.lowerBound))
        )
        return minimumLag...maximumLag
    }

    private func normalizedAutocorrelation(
        envelope: [Double],
        lagRange: ClosedRange<Int>
    ) -> [Double] {
        var correlations = [Double](repeating: 0, count: lagRange.count)
        for lag in lagRange {
            guard envelope.count > lag else { continue }
            var numerator = 0.0
            var energyA = 0.0
            var energyB = 0.0
            for index in lag..<envelope.count {
                let a = envelope[index]
                let b = envelope[index - lag]
                numerator += a * b
                energyA += a * a
                energyB += b * b
            }
            let denominator = sqrt(energyA * energyB)
            if denominator > 0 {
                correlations[lag - lagRange.lowerBound] = numerator / denominator
            }
        }
        return correlations
    }

    private func makeCandidates(
        correlations: [Double],
        lagRange: ClosedRange<Int>,
        envelopeRate: Double,
        onsetTempo: Double?,
        regularity: Double
    ) -> [TempoCandidate] {
        var candidateLags: [Double] = []
        for offset in correlations.indices {
            let previous = offset > 0 ? correlations[offset - 1] : -Double.infinity
            let next = offset + 1 < correlations.count
                ? correlations[offset + 1]
                : -Double.infinity
            guard correlations[offset] >= previous, correlations[offset] > next else { continue }
            candidateLags.append(refinedLag(
                offset: offset,
                correlations: correlations,
                lowerLag: lagRange.lowerBound
            ))
        }

        if let onsetTempo {
            for bpm in [onsetTempo, onsetTempo / 2, onsetTempo * 2]
                where configuration.bpmRange.contains(bpm) {
                candidateLags.append(60 * envelopeRate / bpm)
            }
        }

        var candidates: [TempoCandidate] = []
        for lag in candidateLags {
            let bpm = 60 * envelopeRate / lag
            guard configuration.bpmRange.contains(bpm),
                  !candidates.contains(where: { abs($0.bpm - bpm) < 0.75 }) else { continue }

            let correlationScore = correlation(
                atLag: lag,
                correlations: correlations,
                lagRange: lagRange
            )
            let directOnsetMatch: Double
            let harmonicMatch: Double
            if let onsetTempo {
                directOnsetMatch = exp(-abs(log2(bpm / onsetTempo)) * 5)
                let ratios = [bpm / onsetTempo, onsetTempo / bpm]
                harmonicMatch = ratios.map {
                    exp(-abs(log2($0) - 1) * 6)
                }.max() ?? 0
            } else {
                directOnsetMatch = 0
                harmonicMatch = 0
            }
            let score = 0.68 * correlationScore
                + 0.24 * directOnsetMatch * regularity
                + 0.08 * harmonicMatch
            candidates.append(TempoCandidate(bpm: bpm, score: min(max(score, 0), 1)))
        }

        return candidates.sorted { $0.score > $1.score }
    }

    private func refinedLag(
        offset: Int,
        correlations: [Double],
        lowerLag: Int
    ) -> Double {
        guard offset > 0, offset + 1 < correlations.count else {
            return Double(lowerLag + offset)
        }
        let left = correlations[offset - 1]
        let center = correlations[offset]
        let right = correlations[offset + 1]
        let denominator = left - 2 * center + right
        guard abs(denominator) > 0.000_001 else {
            return Double(lowerLag + offset)
        }
        let adjustment = min(max(0.5 * (left - right) / denominator, -0.5), 0.5)
        return Double(lowerLag + offset) + adjustment
    }

    private func correlation(
        forBPM bpm: Double,
        correlations: [Double],
        lagRange: ClosedRange<Int>,
        envelopeRate: Double
    ) -> Double {
        correlation(
            atLag: 60 * envelopeRate / bpm,
            correlations: correlations,
            lagRange: lagRange
        )
    }

    private func correlation(
        atLag lag: Double,
        correlations: [Double],
        lagRange: ClosedRange<Int>
    ) -> Double {
        let position = lag - Double(lagRange.lowerBound)
        let lower = Int(floor(position))
        guard correlations.indices.contains(lower) else { return 0 }
        let upper = min(lower + 1, correlations.count - 1)
        let fraction = position - Double(lower)
        return correlations[lower] * (1 - fraction) + correlations[upper] * fraction
    }

    private func tempoFromOnsets(_ indices: [Int], envelopeRate: Double) -> Double? {
        let intervals = zip(indices.dropFirst(), indices).map { Double($0 - $1) / envelopeRate }
            .filter { $0 > 0 }
        guard !intervals.isEmpty else { return nil }
        let tempo = 60 / Self.median(intervals)
        guard tempo.isFinite else { return nil }

        if tempo > configuration.bpmRange.upperBound, configuration.bpmRange.contains(tempo / 2) {
            return tempo / 2
        }
        if tempo < configuration.bpmRange.lowerBound, configuration.bpmRange.contains(tempo * 2) {
            return tempo * 2
        }
        return configuration.bpmRange.contains(tempo) ? tempo : nil
    }

    private func onsetRegularity(_ indices: [Int], envelopeRate: Double) -> Double {
        let intervals = zip(indices.dropFirst(), indices).map { Double($0 - $1) / envelopeRate }
        guard intervals.count >= 3 else { return 0 }
        let medianInterval = Self.median(intervals)
        guard medianInterval > 0 else { return 0 }
        let deviations = intervals.map { abs($0 - medianInterval) }
        let relativeMAD = Self.median(deviations) / medianInterval
        return min(max(1 - relativeMAD * 4, 0), 1)
    }

    private func stabilizedBPM(_ bpm: Double) -> Double {
        recentBPMs.append(bpm)
        if recentBPMs.count > 5 {
            recentBPMs.removeFirst(recentBPMs.count - 5)
        }
        let nearby = recentBPMs.filter { abs($0 - bpm) <= 8 }
        return nearby.count >= 2 ? Self.median(nearby) : bpm
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

nonisolated private final class TempoFFT {
    private let size: Int
    private let log2Size: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitude: [Float]

    init(size: Int) {
        precondition(size > 0 && size.isMultiple(of: 2))
        self.size = size
        log2Size = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2Size, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("FFT setupを作成できませんでした。")
        }
        self.setup = setup
        window = .init(repeating: 0, count: size)
        windowed = .init(repeating: 0, count: size)
        real = .init(repeating: 0, count: size / 2)
        imaginary = .init(repeating: 0, count: size / 2)
        magnitude = .init(repeating: 0, count: size / 2)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func magnitudes(of samples: inout [Float], output: inout [Float]) {
        precondition(output.count == magnitude.count)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(size))
        windowed.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(
                to: DSPComplex.self,
                capacity: size / 2
            ) { complex in
                real.withUnsafeMutableBufferPointer { realBuffer in
                    imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                        var split = DSPSplitComplex(
                            realp: realBuffer.baseAddress!,
                            imagp: imaginaryBuffer.baseAddress!
                        )
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(size / 2))
                        vDSP_fft_zrip(setup, &split, 1, log2Size, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &magnitude, 1, vDSP_Length(size / 2))
                    }
                }
            }
        }
        var scale = Float(2) / Float(size)
        vDSP_vsmul(magnitude, 1, &scale, &magnitude, 1, vDSP_Length(magnitude.count))
        magnitude.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: source.baseAddress!, count: source.count)
            }
        }
    }
}
