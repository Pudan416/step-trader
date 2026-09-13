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
        let sampleTime = DayObjectsAtomicWord(0)
        let frameCount = DayObjectsAtomicWord(0)
        let hasTimeline = DayObjectsAtomicWord(0)
        let generation = DayObjectsAtomicWord(0)
    }

    private let slots = (0..<windowBufferCount).map { _ in Slot() }
    private let writeCount = DayObjectsAtomicWord(0)
    private let generation = DayObjectsAtomicWord(1)

    func consume(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>?,
        frameCount: Int,
        sampleTime: Int64
    ) {
        guard frameCount > 0 else { return }
        // A reset racing this scan must not relabel samples which began in the
        // old lifecycle as current. Capture the generation before reading audio.
        let sampleGeneration = generation.load()

        var bufferPeak = 0.0
        var bufferSquaredSum = 0.0
        var bufferSampleCount: UInt64 = 0
        for index in 0..<frameCount {
            accumulate(left[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            if let right {
                accumulate(right[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            }
        }

        publish(
            peak: bufferPeak,
            squaredSum: bufferSquaredSum,
            sampleCount: bufferSampleCount,
            sampleTime: sampleTime,
            frameCount: frameCount,
            hasTimeline: true,
            generation: sampleGeneration
        )
    }

    func consume(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>?,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        let sampleGeneration = generation.load()

        var bufferPeak = 0.0
        var bufferSquaredSum = 0.0
        var bufferSampleCount: UInt64 = 0
        for index in 0..<frameCount {
            accumulate(left[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            if let right {
                accumulate(right[index], peak: &bufferPeak, squaredSum: &bufferSquaredSum, count: &bufferSampleCount)
            }
        }

        publish(
            peak: bufferPeak,
            squaredSum: bufferSquaredSum,
            sampleCount: bufferSampleCount,
            sampleTime: 0,
            frameCount: frameCount,
            hasTimeline: false,
            generation: sampleGeneration
        )
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

    func consume(left: [Float], right: [Float], sampleTime: Int64) {
        let frameCount = min(left.count, right.count)
        guard frameCount > 0 else { return }
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                guard let leftBase = leftBuffer.baseAddress else { return }
                consume(
                    left: leftBase,
                    right: rightBuffer.baseAddress,
                    frameCount: frameCount,
                    sampleTime: sampleTime
                )
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

    var capturedSampleCount: UInt64 { readScalars().count }

    var capturedTimelineRanges: [(sampleTime: Int64, frameCount: UInt64, peak: Double)] {
        readWindows().map { ($0.sampleTime, $0.frameCount, $0.peak) }
    }

    func masterSnapshot(estimatedLimiterReductionDB: Double) -> DayObjectsMasterMetrics {
        let values = readScalars()
        let reduction = estimatedLimiterReductionDB.isFinite
            ? min(max(estimatedLimiterReductionDB, 0), 120)
            : 0
        return .init(
            peakDBFS: Self.decibels(values.peak),
            rmsDBFS: Self.decibels(values.count > 0 ? sqrt(values.squaredSum / Double(values.count)) : 0),
            estimatedLimiterReductionDB: reduction
        )
    }

    func estimatedReduction(
        comparedTo postMeter: DayObjectsBusMeter,
        latencyFrames: Int64,
        fixedOutputGainDB: Double
    ) -> Double {
        let preWindows = readWindows()
        let postWindows = postMeter.readWindows()
        guard !preWindows.isEmpty, !postWindows.isEmpty else { return 0 }
        let boundedLatency = max(latencyFrames, 0)
        let outputGain = fixedOutputGainDB.isFinite ? fixedOutputGainDB : 0
        var maximumReduction = 0.0
        for pre in preWindows {
            let (shiftedStart, overflow) = pre.sampleTime.addingReportingOverflow(boundedLatency)
            guard !overflow else { continue }
            let shiftedEnd = shiftedStart + Int64(clamping: pre.frameCount)
            guard let post = postWindows.max(by: { lhs, rhs in
                Self.overlapFrames(start: shiftedStart, end: shiftedEnd, with: lhs)
                    < Self.overlapFrames(start: shiftedStart, end: shiftedEnd, with: rhs)
            }), Self.overlapFrames(start: shiftedStart, end: shiftedEnd, with: post) > 0 else { continue }
            maximumReduction = max(
                maximumReduction,
                Self.decibels(pre.peak) + outputGain - Self.decibels(post.peak)
            )
        }
        return min(max(maximumReduction, 0), 120)
    }

    private static func overlapFrames(start: Int64, end: Int64, with window: Window) -> Int64 {
        let windowEnd = window.sampleTime + Int64(clamping: window.frameCount)
        return max(min(end, windowEnd) - max(start, window.sampleTime), 0)
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

    private struct Window {
        let peak: Double
        let squaredSum: Double
        let sampleCount: UInt64
        let sampleTime: Int64
        let frameCount: UInt64
        let hasTimeline: Bool
    }

    private func publish(
        peak: Double,
        squaredSum: Double,
        sampleCount: UInt64,
        sampleTime: Int64,
        frameCount: Int,
        hasTimeline: Bool,
        generation: UInt64
    ) {
        let write = writeCount.incrementAndLoad() &- 1
        let slot = slots[Int(write % UInt64(Self.windowBufferCount))]
        slot.sequence.increment()
        slot.peakBits.store(peak.bitPattern)
        slot.squaredSumBits.store(squaredSum.bitPattern)
        slot.sampleCount.store(sampleCount)
        slot.sampleTime.store(UInt64(bitPattern: sampleTime))
        slot.frameCount.store(UInt64(frameCount))
        slot.hasTimeline.store(hasTimeline ? 1 : 0)
        slot.generation.store(generation)
        slot.sequence.increment()
    }

    private func readWindows() -> [Window] {
        let expectedGeneration = generation.load()
        var result: [Window] = []
        result.reserveCapacity(Self.windowBufferCount)
        for slot in slots {
            while true {
                let before = slot.sequence.load()
                guard before.isMultiple(of: 2) else { continue }
                let window = Window(
                    peak: Double(bitPattern: slot.peakBits.load()),
                    squaredSum: Double(bitPattern: slot.squaredSumBits.load()),
                    sampleCount: slot.sampleCount.load(),
                    sampleTime: Int64(bitPattern: slot.sampleTime.load()),
                    frameCount: slot.frameCount.load(),
                    hasTimeline: slot.hasTimeline.load() == 1
                )
                let slotGeneration = slot.generation.load()
                let after = slot.sequence.load()
                guard before == after else { continue }
                if slotGeneration == expectedGeneration, window.hasTimeline {
                    result.append(window)
                }
                break
            }
        }
        return result
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
