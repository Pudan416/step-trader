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

    @inline(__always)
    func incrementAndLoad() -> UInt64 {
        UInt64(bitPattern: OSAtomicIncrement64Barrier(&storage))
    }
}

/// A fixed ring of single-writer seqlocks for recent render-buffer scalars.
/// The audio callback overwrites one preallocated slot per buffer; it does not
/// lock, allocate, dispatch, or log. Readers accept only complete slots from
/// the current generation, giving peak and RMS one bounded, aligned window.
final class DayObjectsBusMeter: @unchecked Sendable {
    static let windowBufferCount = 8
    private static let silenceFloorDBFS = -120.0

    private final class Slot: @unchecked Sendable {
        let sequence = DayObjectsAtomicWord(0)
        let peakBits = DayObjectsAtomicWord(0)
        let squaredSumBits = DayObjectsAtomicWord(0)
        let sampleCount = DayObjectsAtomicWord(0)
        let generation = DayObjectsAtomicWord(0)
    }

    private let slots = (0..<windowBufferCount).map { _ in Slot() }
    private let writeCount = DayObjectsAtomicWord(0)
    private let generation = DayObjectsAtomicWord(1)

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

        let write = writeCount.incrementAndLoad() &- 1
        let slot = slots[Int(write % UInt64(Self.windowBufferCount))]
        slot.sequence.increment()
        slot.peakBits.store(bufferPeak.bitPattern)
        slot.squaredSumBits.store(bufferSquaredSum.bitPattern)
        slot.sampleCount.store(bufferSampleCount)
        slot.generation.store(generation.load())
        slot.sequence.increment()
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

    /// Starts a new logical window without touching render-thread-owned slots.
    /// Old samples become invisible through the atomic generation tag.
    func reset() {
        generation.increment()
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
        let expectedGeneration = generation.load()
        var peak = 0.0
        var squaredSum = 0.0
        var count: UInt64 = 0
        for slot in slots {
            while true {
                let before = slot.sequence.load()
                guard before.isMultiple(of: 2) else { continue }
                let slotPeak = Double(bitPattern: slot.peakBits.load())
                let slotSquaredSum = Double(bitPattern: slot.squaredSumBits.load())
                let slotCount = slot.sampleCount.load()
                let slotGeneration = slot.generation.load()
                let after = slot.sequence.load()
                guard before == after else { continue }
                if slotGeneration == expectedGeneration {
                    peak = max(peak, slotPeak.isFinite ? max(slotPeak, 0) : 0)
                    squaredSum += slotSquaredSum.isFinite ? max(slotSquaredSum, 0) : 0
                    count &+= slotCount
                }
                break
            }
        }
        return (peak, squaredSum, count)
    }

    private static func decibels(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return silenceFloorDBFS }
        return max(20 * log10(amplitude), silenceFloorDBFS)
    }
}
#endif
