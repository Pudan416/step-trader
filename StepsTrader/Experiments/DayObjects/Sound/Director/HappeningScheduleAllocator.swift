#if DEBUG || INTERNAL_BUILD
enum HappeningScheduleAllocator {
    private static let maximumCycleCount = 16
    private static let maximumBeatsPerBar = 16

    private struct VoiceLane {
        let plan: HappeningMusicPlan
        let alignment: HappeningRecurrenceAlignment
        let intervalBars: Int
        let phaseBeat: Double
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
        let minimumPeriodBeats = intervalBand.lowerBound * beatsPerBar
        // Every declared upper interval is exactly two minimum periods. Assigning
        // one collision-free phase per voice, then repeating at one or two periods,
        // makes all future placements collision-free without greedy horizon state.
        let lanes = makeVoiceLanes(
            plans: activePlans,
            gridIDs: gridIDs,
            intervalBand: intervalBand,
            minimumPeriodBeats: minimumPeriodBeats,
            remixSeed: remixSeed
        )
        var scheduled: [HappeningScheduleEvent] = []
        var cursors: [HappeningScheduleCursor] = []
        for lane in lanes {
            let intervalBeats = Double(lane.intervalBars * beatsPerBar)
            var sequenceIndex = 0
            var startBeat = lane.phaseBeat
            while startBeat < horizonBeats {
                scheduled.append(HappeningScheduleEvent(
                    happeningID: lane.plan.happeningID,
                    sequenceIndex: sequenceIndex,
                    startBeat: startBeat,
                    intervalBars: lane.intervalBars,
                    alignment: lane.alignment,
                    gain: lane.plan.gain
                ))
                sequenceIndex += 1
                startBeat += intervalBeats
            }
            cursors.append(HappeningScheduleCursor(
                happeningID: lane.plan.happeningID,
                nextSequenceIndex: sequenceIndex,
                nextCandidateBeat: startBeat
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

    private static func makeVoiceLanes(
        plans: [HappeningMusicPlan],
        gridIDs: Set<String>,
        intervalBand: ClosedRange<Int>,
        minimumPeriodBeats: Int,
        remixSeed: UInt64,
    ) -> [VoiceLane] {
        var occupiedPhases: [Double] = []
        return plans.sorted { $0.happeningID < $1.happeningID }.map { plan in
            let alignment: HappeningRecurrenceAlignment = gridIDs.contains(plan.happeningID)
                ? .gridAligned
                : .floating
            var random = StableMusicRandom(
                seed: plan.recurrence.scheduleSeed ^ remixSeed,
                domain: .happeningSchedule(stableID: plan.happeningID)
            )
            let intervalBars = random.bernoulli(probability: 0.5)
                ? intervalBand.lowerBound
                : intervalBand.upperBound
            let preferredWholeBeat = random.nextInt(upperBound: minimumPeriodBeats) ?? 0
            let preferredPhase = wrappedPhase(
                Double(preferredWholeBeat) + (
                    alignment == .gridAligned ? 0 : plan.recurrence.floatingOffsetBeats
                ),
                periodBeats: minimumPeriodBeats
            )
            // Guarded inputs guarantee phase capacity: active voice count is no
            // greater than the minimum period in beats, grid voices have one slot
            // per beat, and floating voices have the remaining two-per-beat slots.
            let phase = candidatePhases(
                alignment: alignment,
                periodBeats: minimumPeriodBeats
            ).filter { isPhaseAvailable($0, among: occupiedPhases) }
                .min {
                    let leftDistance = circularDistance(
                        from: $0,
                        to: preferredPhase,
                        period: Double(minimumPeriodBeats)
                    )
                    let rightDistance = circularDistance(
                        from: $1,
                        to: preferredPhase,
                        period: Double(minimumPeriodBeats)
                    )
                    if leftDistance != rightDistance { return leftDistance < rightDistance }
                    return $0 < $1
                } ?? preferredPhase
            occupiedPhases.append(phase)
            return VoiceLane(
                plan: plan,
                alignment: alignment,
                intervalBars: intervalBars,
                phaseBeat: phase
            )
        }
    }

    private static func candidatePhases(
        alignment: HappeningRecurrenceAlignment,
        periodBeats: Int
    ) -> [Double] {
        switch alignment {
        case .gridAligned:
            return (0..<periodBeats).map(Double.init)
        case .floating:
            return (1..<(periodBeats * 4)).compactMap { quarter in
                guard !quarter.isMultiple(of: 4) else { return nil }
                return Double(quarter) / 4
            }
        }
    }

    private static func isPhaseAvailable(
        _ position: Double,
        among occupied: [Double]
    ) -> Bool {
        if occupied.contains(where: { abs($0 - position) < 0.25 - 0.000_001 }) {
            return false
        }
        let beat = Int(position.rounded(.down))
        return occupied.filter { Int($0.rounded(.down)) == beat }.count < 2
    }

    private static func wrappedPhase(_ phase: Double, periodBeats: Int) -> Double {
        let period = Double(periodBeats)
        if phase < 0 { return phase + period }
        if phase >= period { return phase - period }
        return phase
    }

    private static func circularDistance(from lhs: Double, to rhs: Double, period: Double) -> Double {
        let direct = abs(lhs - rhs)
        return min(direct, period - direct)
    }
}
#endif
