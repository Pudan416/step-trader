#if DEBUG || INTERNAL_BUILD
import Foundation
import Darwin

private final class DayObjectsAtomicWord: @unchecked Sendable {
    private var storage: Int64

    init(_ value: UInt64) {
        storage = Int64(bitPattern: value)
    }

    @inline(__always)
    func load() -> UInt64 {
        UInt64(bitPattern: OSAtomicAdd64Barrier(0, &storage))
    }

    @inline(__always)
    func store(_ value: UInt64) {
        let desired = Int64(bitPattern: value)
        while true {
            let current = OSAtomicAdd64Barrier(0, &storage)
            if OSAtomicCompareAndSwap64Barrier(current, desired, &storage) { return }
        }
    }

    @inline(__always)
    func increment() {
        _ = OSAtomicIncrement64Barrier(&storage)
    }
}

/// A single-writer seqlock for audio-meter scalars. The render callback writes
/// only four preallocated atomic words; it does not lock, allocate, dispatch,
/// or log. Main-actor readers retry if they overlap the audio-thread writer.
final class DayObjectsBusMeter: @unchecked Sendable {
    private static let silenceFloorDBFS = -120.0

    private let sequence = DayObjectsAtomicWord(0)
    private let peakBits = DayObjectsAtomicWord(0)
    private let squaredSumBits = DayObjectsAtomicWord(0)
    private let sampleCount = DayObjectsAtomicWord(0)

    func consume(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>?,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }

        var bufferPeak = 0.0
        var bufferSquaredSum = 0.0
        var bufferSampleCount: UInt64 = 0
        for index in 0..<frameCount {
            accumulate(left[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            if let right {
                accumulate(right[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            }
        }

        sequence.increment()
        let previousPeak = Double(bitPattern: peakBits.load())
        let previousSquaredSum = Double(bitPattern: squaredSumBits.load())
        let previousCount = sampleCount.load()
        peakBits.store(max(previousPeak.isFinite ? previousPeak : 0, bufferPeak).bitPattern)
        let totalSquaredSum = previousSquaredSum + bufferSquaredSum
        squaredSumBits.store((totalSquaredSum.isFinite ? totalSquaredSum : bufferSquaredSum).bitPattern)
        sampleCount.store(previousCount &+ bufferSampleCount)
        sequence.increment()
    }

    /// Convenience adapter for tests and non-render-thread callers.
    func consume(left: [Float], right: [Float]) {
        let frameCount = min(left.count, right.count)
        guard frameCount > 0 else { return }
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                guard let leftBase = leftBuffer.baseAddress else { return }
                consume(left: leftBase, right: rightBuffer.baseAddress, frameCount: frameCount)
            }
        }
    }

    func snapshot(activeVoiceCount: Int) -> DayObjectsRoleBusMetrics {
        let values = readScalars()
        return .init(
            peakDBFS: Self.decibels(values.peak),
            rmsDBFS: Self.decibels(values.count > 0 ? sqrt(values.squaredSum / Double(values.count)) : 0),
            activeVoiceCount: max(activeVoiceCount, 0)
        )
    }

    func masterSnapshot(limiterReductionDB: Double) -> DayObjectsMasterMetrics {
        let values = readScalars()
        let reduction = limiterReductionDB.isFinite ? min(max(limiterReductionDB, 0), 120) : 0
        return .init(
            peakDBFS: Self.decibels(values.peak),
            rmsDBFS: Self.decibels(values.count > 0 ? sqrt(values.squaredSum / Double(values.count)) : 0),
            limiterReductionDB: reduction
        )
    }

    private func accumulate(
        _ sample: Float,
        peak: inout Double,
        squaredSum: inout Double,
        count: inout UInt64
    ) {
        let value = sample.isFinite ? Double(sample) : 0
        peak = max(peak, abs(value))
        squaredSum += value * value
        count &+= 1
    }

    private func readScalars() -> (peak: Double, squaredSum: Double, count: UInt64) {
        while true {
            let before = sequence.load()
            guard before.isMultiple(of: 2) else { continue }
            let peak = Double(bitPattern: peakBits.load())
            let squaredSum = Double(bitPattern: squaredSumBits.load())
            let count = sampleCount.load()
            let after = sequence.load()
            if before == after {
                return (
                    peak.isFinite ? max(peak, 0) : 0,
                    squaredSum.isFinite ? max(squaredSum, 0) : 0,
                    count
                )
            }
        }
    }

    private static func decibels(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return silenceFloorDBFS }
        return max(20 * log10(amplitude), silenceFloorDBFS)
    }
}
#endif
