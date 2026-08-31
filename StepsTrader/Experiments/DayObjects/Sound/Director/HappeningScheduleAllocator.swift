#if DEBUG || INTERNAL_BUILD
enum HappeningScheduleAllocator {
    private static let maximumCycleCount = 16
    private static let maximumBeatsPerBar = 16

    private struct Candidate {
        let plan: HappeningMusicPlan
        let sequenceIndex: Int
        let candidateBeat: Double
        let intervalBars: Int
        let alignment: HappeningRecurrenceAlignment
    }

    static func allocate(
        plans: [HappeningMusicPlan],
        remixSeed: UInt64,
        cycleCount: Int,
        beatsPerBar: Int = 4
    ) -> HappeningScheduleAllocation {
        let activePlans = uniquePlansByStableID(plans)
        guard
            let intervalBand = intervalBand(for: activePlans.count),
            (1...maximumCycleCount).contains(cycleCount),
            (1...maximumBeatsPerBar).contains(beatsPerBar)
        else {
            return emptyAllocation(beatsPerBar: beatsPerBar)
        }

        let cycleBars = intervalBand.upperBound
        let horizonBars = cycleBars * cycleCount
        let horizonBeats = Double(horizonBars * beatsPerBar)
        let gridIDs = gridAlignedIDs(in: activePlans)
        var candidates: [Candidate] = []
        var cursors: [HappeningScheduleCursor] = []

        for plan in activePlans {
            let alignment: HappeningRecurrenceAlignment = gridIDs.contains(plan.happeningID)
                ? .gridAligned
                : .floating
            let generated = makeCandidates(
                for: plan,
                alignment: alignment,
                intervalBand: intervalBand,
                remixSeed: remixSeed,
                cycleBars: cycleBars,
                horizonBeats: horizonBeats,
                beatsPerBar: beatsPerBar
            )
            candidates.append(contentsOf: generated.candidates)
            cursors.append(generated.cursor)
        }

        candidates.sort {
            if $0.candidateBeat != $1.candidateBeat {
                return $0.candidateBeat < $1.candidateBeat
            }
            if $0.plan.happeningID != $1.plan.happeningID {
                return $0.plan.happeningID < $1.plan.happeningID
            }
            return $0.sequenceIndex < $1.sequenceIndex
        }

        var scheduled: [HappeningScheduleEvent] = []
        var previousBeatByID: [String: Double] = [:]
        let lastSequenceByID = candidates.reduce(into: [String: Int]()) { result, candidate in
            result[candidate.plan.happeningID] = max(
                result[candidate.plan.happeningID] ?? -1,
                candidate.sequenceIndex
            )
        }
        let maximumGapBeats = Double(intervalBand.upperBound * beatsPerBar)
        let minimumGapBeats = Double(intervalBand.lowerBound * beatsPerBar)
        for candidate in candidates {
            guard let startBeat = resolvedBeat(
                for: candidate,
                scheduled: scheduled,
                previousBeat: previousBeatByID[candidate.plan.happeningID],
                minimumGapBeats: minimumGapBeats,
                maximumGapBeats: maximumGapBeats,
                cycleBeats: Double(cycleBars * beatsPerBar),
                horizonBeats: horizonBeats,
                requiresTailCoverage: lastSequenceByID[candidate.plan.happeningID]
                    == candidate.sequenceIndex
            ) else {
                // Under the guarded count/horizon caps, the exhaustive window always has
                // more legal slots than competing voices can occupy. Reject the complete
                // allocation rather than publishing a partial, starving schedule if that
                // invariant is ever broken by a future change.
                return emptyAllocation(beatsPerBar: beatsPerBar)
            }
            previousBeatByID[candidate.plan.happeningID] = startBeat
            scheduled.append(HappeningScheduleEvent(
                happeningID: candidate.plan.happeningID,
                sequenceIndex: candidate.sequenceIndex,
                startBeat: startBeat,
                intervalBars: candidate.intervalBars,
                alignment: candidate.alignment,
                gain: candidate.plan.gain
            ))
        }
        scheduled.sort {
            if $0.startBeat != $1.startBeat { return $0.startBeat < $1.startBeat }
            if $0.happeningID != $1.happeningID { return $0.happeningID < $1.happeningID }
            return $0.sequenceIndex < $1.sequenceIndex
        }

        return HappeningScheduleAllocation(
            cycleBars: cycleBars,
            horizonBars: horizonBars,
            beatsPerBar: beatsPerBar,
            intervalBandBars: intervalBand,
            events: scheduled,
            nextCursors: cursors.sorted { $0.happeningID < $1.happeningID }
        )
    }

    private static func intervalBand(for count: Int) -> ClosedRange<Int>? {
        switch count {
        case 1...2: return 2...4
        case 3...6: return 6...12
        case 7...10: return 12...24
        default: return nil
        }
    }

    private static func emptyAllocation(beatsPerBar: Int) -> HappeningScheduleAllocation {
        HappeningScheduleAllocation(
            cycleBars: 0,
            horizonBars: 0,
            beatsPerBar: (1...maximumBeatsPerBar).contains(beatsPerBar) ? beatsPerBar : 0,
            intervalBandBars: nil,
            events: [],
            nextCursors: []
        )
    }

    private static func uniquePlansByStableID(
        _ plans: [HappeningMusicPlan]
    ) -> [HappeningMusicPlan] {
        var seen: Set<String> = []
        var result: [HappeningMusicPlan] = []
        for plan in plans where seen.insert(plan.happeningID).inserted {
            result.append(plan)
            if result.count == 10 { break }
        }
        return result
    }

    private static func gridAlignedIDs(in plans: [HappeningMusicPlan]) -> Set<String> {
        let count = plans.count
        let lower = Int((Double(count) * 0.35).rounded(.up))
        let upper = Int((Double(count) * 0.60).rounded(.down))
        let ideal = Int((Double(count) * 0.45).rounded())
        let target = lower <= upper ? min(max(ideal, lower), upper) : min(max(ideal, 0), count)
        let ranked = plans.sorted {
            if $0.recurrence.alignmentRank != $1.recurrence.alignmentRank {
                return $0.recurrence.alignmentRank < $1.recurrence.alignmentRank
            }
            return $0.happeningID < $1.happeningID
        }
        return Set(ranked.prefix(target).map(\.happeningID))
    }

    private static func makeCandidates(
        for plan: HappeningMusicPlan,
        alignment: HappeningRecurrenceAlignment,
        intervalBand: ClosedRange<Int>,
        remixSeed: UInt64,
        cycleBars: Int,
        horizonBeats: Double,
        beatsPerBar: Int
    ) -> (candidates: [Candidate], cursor: HappeningScheduleCursor) {
        var random = StableMusicRandom(
            seed: plan.recurrence.scheduleSeed ^ remixSeed,
            domain: .happeningSchedule(stableID: plan.happeningID)
        )
        let cycleBeats = cycleBars * beatsPerBar
        let latestInitialBeat = max(1, cycleBeats - 6)
        let initialWholeBeat = 1 + (random.nextInt(upperBound: latestInitialBeat) ?? 0)
        let fractionalOffset = alignment == .gridAligned
            ? 0
            : plan.recurrence.floatingOffsetBeats
        var candidateBeat = Double(initialWholeBeat) + fractionalOffset
        if candidateBeat < 0.25 { candidateBeat = 0.25 }

        var sequenceIndex = 0
        var result: [Candidate] = []
        while candidateBeat < horizonBeats {
            let selectableCount = max(1, intervalBand.upperBound - intervalBand.lowerBound + 1)
            let intervalBars = intervalBand.lowerBound
                + (random.nextInt(upperBound: selectableCount) ?? 0)
            result.append(Candidate(
                plan: plan,
                sequenceIndex: sequenceIndex,
                candidateBeat: candidateBeat,
                intervalBars: intervalBars,
                alignment: alignment
            ))
            sequenceIndex += 1
            candidateBeat += Double(intervalBars * beatsPerBar)
        }

        return (
            result,
            HappeningScheduleCursor(
                happeningID: plan.happeningID,
                nextSequenceIndex: sequenceIndex,
                nextCandidateBeat: candidateBeat
            )
        )
    }

    private static func resolvedBeat(
        for candidate: Candidate,
        scheduled: [HappeningScheduleEvent],
        previousBeat: Double?,
        minimumGapBeats: Double,
        maximumGapBeats: Double,
        cycleBeats: Double,
        horizonBeats: Double,
        requiresTailCoverage: Bool
    ) -> Double? {
        let cycleStart = Double(Int(candidate.candidateBeat / cycleBeats)) * cycleBeats
        let cycleEnd = min(horizonBeats, cycleStart + cycleBeats)
        var lowerBound = cycleStart
        var upperBound = cycleEnd - 0.25
        if let previousBeat {
            lowerBound = max(lowerBound, previousBeat + minimumGapBeats)
            upperBound = min(upperBound, previousBeat + maximumGapBeats)
        }
        if requiresTailCoverage {
            lowerBound = max(lowerBound, horizonBeats - maximumGapBeats)
        }
        guard lowerBound <= upperBound else { return nil }

        let positions = candidatePositions(
            alignment: candidate.alignment,
            lowerBound: lowerBound,
            upperBound: upperBound
        ).sorted {
            let leftDistance = abs($0 - candidate.candidateBeat)
            let rightDistance = abs($1 - candidate.candidateBeat)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return $0 < $1
        }
        for position in positions {
            guard isAvailable(position, among: scheduled) else { continue }
            return position
        }
        return nil
    }

    private static func candidatePositions(
        alignment: HappeningRecurrenceAlignment,
        lowerBound: Double,
        upperBound: Double
    ) -> [Double] {
        switch alignment {
        case .gridAligned:
            let first = Int(lowerBound.rounded(.up))
            let last = Int(upperBound.rounded(.down))
            guard first <= last else { return [] }
            return (first...last).map(Double.init)
        case .floating:
            let firstQuarter = Int((lowerBound * 4).rounded(.up))
            let lastQuarter = Int((upperBound * 4).rounded(.down))
            guard firstQuarter <= lastQuarter else { return [] }
            return (firstQuarter...lastQuarter).compactMap { quarter in
                guard !quarter.isMultiple(of: 4) else { return nil }
                return Double(quarter) / 4
            }
        }
    }

    private static func isAvailable(
        _ position: Double,
        among scheduled: [HappeningScheduleEvent]
    ) -> Bool {
        if scheduled.contains(where: { abs($0.startBeat - position) < 0.25 - 0.000_001 }) {
            return false
        }
        let beat = Int(position.rounded(.down))
        return scheduled.filter { Int($0.startBeat.rounded(.down)) == beat }.count < 2
    }
}
#endif
