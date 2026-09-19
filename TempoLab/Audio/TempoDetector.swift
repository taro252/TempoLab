import AVFoundation
import Foundation

nonisolated protocol TempoDetecting: AnyObject, Sendable {
    typealias ResultHandler = @MainActor @Sendable (TempoDetectionResult?) -> Void

    func setResultHandler(_ handler: @escaping ResultHandler)
    func process(buffer: AVAudioPCMBuffer, at time: AVAudioTime)
    func reset()
}

nonisolated final class TempoDetector: TempoDetecting, @unchecked Sendable {
    private let ringBuffer = PCMFloatRingBuffer(capacity: 262_144)
    private let dspQueue = DispatchQueue(label: "jp.taro252.TempoLab.tempo-dsp", qos: .userInitiated)
    private let schedulingLock = NSLock()
    private let analyzer: TempoDetectorDSP
    private var drainIsScheduled = false
    private var workingSamples = [Float](repeating: 0, count: 8_192)
    private var resultHandler: ResultHandler?

    init(configuration: TempoDetectionConfiguration = .init()) {
        analyzer = TempoDetectorDSP(configuration: configuration)
    }

    func setResultHandler(_ handler: @escaping ResultHandler) {
        dspQueue.async { [weak self] in
            self?.resultHandler = handler
        }
    }

    func process(buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard ringBuffer.write(buffer: buffer) else { return }
        scheduleDrainIfNeeded()
    }

    func reset() {
        ringBuffer.reset()
        dspQueue.async { [weak self] in
            guard let self else { return }
            analyzer.reset()
            publish(nil)
        }
    }

    private func scheduleDrainIfNeeded() {
        guard schedulingLock.try() else { return }
        let shouldSchedule = !drainIsScheduled
        if shouldSchedule {
            drainIsScheduled = true
        }
        schedulingLock.unlock()
        guard shouldSchedule else { return }

        dspQueue.async { [weak self] in
            self?.drainAvailableSamples()
        }
    }

    private func drainAvailableSamples() {
        while true {
            let read = ringBuffer.read(into: &workingSamples)
            guard read.count > 0 else { break }

            let result = workingSamples.withUnsafeBufferPointer { buffer in
                let samples = UnsafeBufferPointer(start: buffer.baseAddress, count: read.count)
                return analyzer.process(samples: samples, sampleRate: read.sampleRate)
            }
            if analyzer.didAnalyzeCurrentProcess {
                publish(result)
            }
        }

        schedulingLock.lock()
        drainIsScheduled = false
        schedulingLock.unlock()
        if ringBuffer.hasSamples {
            scheduleDrainIfNeeded()
        }
    }

    private func publish(_ result: TempoDetectionResult?) {
        guard let resultHandler else { return }
        DispatchQueue.main.async {
            resultHandler(result)
        }
    }
}
