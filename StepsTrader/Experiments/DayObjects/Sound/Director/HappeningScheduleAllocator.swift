#if DEBUG || INTERNAL_BUILD
enum HappeningScheduleAllocator {
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
        let uniquePlans = uniquePlansByStableID(plans).prefix(10)
        let activePlans = Array(uniquePlans)
        guard
            let intervalBand = intervalBand(for: activePlans.count),
            cycleCount > 0,
            beatsPerBar > 0
        else {
            return HappeningScheduleAllocation(
                cycleBars: 0,
                horizonBars: 0,
                beatsPerBar: max(0, beatsPerBar),
                intervalBandBars: nil,
                events: [],
                nextCursors: []
            )
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
        let maximumGapBeats = Double(intervalBand.upperBound * beatsPerBar)
        for candidate in candidates {
            guard let startBeat = resolvedBeat(
                for: candidate,
                scheduled: scheduled,
                previousBeat: previousBeatByID[candidate.plan.happeningID],
                maximumGapBeats: maximumGapBeats,
                cycleBeats: Double(cycleBars * beatsPerBar),
                horizonBeats: horizonBeats
            ) else { continue }
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

    private static func uniquePlansByStableID(
        _ plans: [HappeningMusicPlan]
    ) -> [HappeningMusicPlan] {
        var seen: Set<String> = []
        return plans.filter { seen.insert($0.happeningID).inserted }
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
        maximumGapBeats: Double,
        cycleBeats: Double,
        horizonBeats: Double
    ) -> Double? {
        let step = candidate.alignment == .gridAligned ? 1.0 : 0.25
        let cycleStart = Double(Int(candidate.candidateBeat / cycleBeats)) * cycleBeats
        let cycleEnd = min(horizonBeats, cycleStart + cycleBeats)
        for alternateIndex in 0...32 {
            let alternateOffset: Double
            if alternateIndex == 0 {
                alternateOffset = 0
            } else {
                let magnitude = Double((alternateIndex + 1) / 2) * step
                alternateOffset = alternateIndex.isMultiple(of: 2) ? magnitude : -magnitude
            }
            let position = candidate.candidateBeat + alternateOffset
            guard position >= cycleStart, position < cycleEnd else { continue }
            if candidate.alignment == .floating, position == position.rounded() {
                continue
            }
            if let previousBeat {
                guard position - previousBeat >= 0.25 - 0.000_001 else { continue }
                guard position - previousBeat <= maximumGapBeats + 0.000_001 else { continue }
            }
            guard isAvailable(position, among: scheduled) else { continue }
            return position
        }
        return nil
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
