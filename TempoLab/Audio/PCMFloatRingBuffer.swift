import AVFoundation
import Foundation

/// Audio callbackは待機せず、競合時には入力を捨てるSPSC向け固定長リングバッファ。
nonisolated final class PCMFloatRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var readIndex = 0
    private var writeIndex = 0
    private var storedCount = 0
    private var currentSampleRate = 0.0

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
        storage = .allocate(capacity: self.capacity)
        storage.initialize(repeating: 0, count: self.capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    @discardableResult
    func write(buffer: AVAudioPCMBuffer) -> Bool {
        guard lock.try() else { return false }
        defer { lock.unlock() }

        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData else { return false }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return false }

        currentSampleRate = buffer.format.sampleRate
        for frame in 0..<frameCount {
            var monoSample: Float = 0
            for channel in 0..<channelCount {
                monoSample += channels[channel][frame]
            }
            monoSample /= Float(channelCount)

            storage[writeIndex] = monoSample.isFinite ? monoSample : 0
            writeIndex = (writeIndex + 1) % capacity

            if storedCount == capacity {
                readIndex = (readIndex + 1) % capacity
            } else {
                storedCount += 1
            }
        }
        return true
    }

    func read(into destination: inout [Float]) -> (count: Int, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }

        let count = min(destination.count, storedCount)
        guard count > 0 else { return (0, currentSampleRate) }

        for index in 0..<count {
            destination[index] = storage[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        storedCount -= count
        return (count, currentSampleRate)
    }

    func reset() {
        lock.lock()
        readIndex = 0
        writeIndex = 0
        storedCount = 0
        currentSampleRate = 0
        lock.unlock()
    }

    var hasSamples: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedCount > 0
    }
}
