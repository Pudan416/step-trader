import Foundation

struct LeadGestureMapping: Equatable, Sendable {
    let regionIndex: Int
    let midiNote: UInt8
    let cutoffMultiplier: Double
    let expressionDepth: Double
}

/// Converts touch input into bounded, chord-aware Lead controls without
/// inventing another set of pitch-region boundary rules.
struct LeadGestureMapper: Sendable {
    private static let referenceSpeed = 3.0
    private static let cutoffSmoothing = 0.22
    private static let expressionSmoothing = 0.20

    private let plan: LeadPlan
    private var previousX: Double?
    private var previousY: Double?
    private var previousCutoffMultiplier: Double?
    private var previousExpressionDepth: Double?

    init(plan: LeadPlan) {
        self.plan = plan
    }

    mutating func map(_ sample: LeadGestureSample, chordIndex: Int) -> LeadGestureMapping {
        let x = Self.finiteUnit(sample.normalizedX, fallback: previousX ?? 0)
        let y = Self.finiteUnit(sample.normalizedY, fallback: previousY ?? 0.5)
        previousX = x
        previousY = y

        let regionIndex = plan.regionIndex(forNormalizedX: x)
        let region = plan.pitchRegions.indices.contains(regionIndex)
            ? plan.pitchRegions[regionIndex]
            : nil
        let safeChordIndex = Self.safeChordIndex(
            chordIndex,
            count: region?.midiNotesByChord.count ?? 0
        )
        let midiNote = region.flatMap { pitchRegion in
            pitchRegion.midiNotesByChord.indices.contains(safeChordIndex)
                ? pitchRegion.midiNotesByChord[safeChordIndex]
                : nil
        } ?? plan.register.lowerBound

        let cutoffRange = plan.cutoffMultiplierRange
        // Equal travel spans equal octaves. Y=0 is open; Y=1 is closed.
        // Smooth in log-frequency space as well, avoiding a jump at the dark end.
        let lowerLog = log(cutoffRange.lowerBound)
        let upperLog = log(cutoffRange.upperBound)
        let cutoffLog = smoothed(
            target: upperLog - y * (upperLog - lowerLog),
            previous: previousCutoffMultiplier.map { log($0) },
            coefficient: Self.cutoffSmoothing,
            range: lowerLog...upperLog
        )
        let cutoff = min(max(exp(cutoffLog), cutoffRange.lowerBound), cutoffRange.upperBound)
        previousCutoffMultiplier = cutoff

        let speed = sample.speed.isFinite ? max(sample.speed, 0) : 0
        let maximumExpression = min(
            Self.finiteUnit(plan.maximumExpressionDepth, fallback: 0),
            0.25
        )
        let expressionTarget = min(speed / Self.referenceSpeed, 1) * maximumExpression
        let expression = smoothed(
            target: expressionTarget,
            previous: previousExpressionDepth,
            coefficient: Self.expressionSmoothing,
            range: 0...maximumExpression
        )
        previousExpressionDepth = expression

        return .init(
            regionIndex: regionIndex,
            midiNote: midiNote,
            cutoffMultiplier: cutoff,
            expressionDepth: expression
        )
    }

    mutating func reset() {
        previousX = nil
        previousY = nil
        previousCutoffMultiplier = nil
        previousExpressionDepth = nil
    }

    private func smoothed(
        target: Double,
        previous: Double?,
        coefficient: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let value = previous.map { $0 + (target - $0) * coefficient } ?? target
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func finiteUnit(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return min(max(fallback, 0), 1) }
        return min(max(value, 0), 1)
    }

    private static func safeChordIndex(_ chordIndex: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(chordIndex, 0), count - 1)
    }
}
