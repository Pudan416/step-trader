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
        let entryHorizonBeats = cycleBars * beatsPerBar
        // First entrances span the complete longest cycle. Recurrences then use
        // one of the band endpoints, so enabling Sound cannot front-load every
        // existing Happening and leave a long empty trough afterwards.
        let lanes = makeVoiceLanes(
            plans: activePlans,
            gridIDs: gridIDs,
            intervalBand: intervalBand,
            entryHorizonBeats: entryHorizonBeats,
            beatsPerBar: beatsPerBar,
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
        case 1...2: return 24...40
        case 3...6: return 56...96
        case 7...10: return 112...192
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
        entryHorizonBeats: Int,
        beatsPerBar: Int,
        remixSeed: UInt64,
    ) -> [VoiceLane] {
        var lanes: [VoiceLane] = []
        let orderedPlans = plans.sorted(by: { $0.happeningID < $1.happeningID })
        let entranceSlotBeats = Double(entryHorizonBeats) / Double(orderedPlans.count)
        for (index, plan) in orderedPlans.enumerated() {
            let alignment: HappeningRecurrenceAlignment = gridIDs.contains(plan.happeningID)
                ? .gridAligned
                : .floating
            var random = StableMusicRandom(
                seed: plan.recurrence.scheduleSeed ^ remixSeed,
                domain: .happeningSchedule(stableID: plan.happeningID)
            )
            let preferredIntervalBars = random.bernoulli(probability: 0.5)
                ? intervalBand.lowerBound
                : intervalBand.upperBound
            let entrancePosition = 0.25 + 0.50 * random.nextUnitDouble()
            let preferredPhase = entranceSlotBeats * (Double(index) + entrancePosition)
            let candidates = candidatePhases(
                alignment: alignment,
                periodBeats: entryHorizonBeats
            ).sorted {
                    let leftDistance = abs($0 - preferredPhase)
                    let rightDistance = abs($1 - preferredPhase)
                    if leftDistance != rightDistance { return leftDistance < rightDistance }
                    return $0 < $1
                }
            // Different interval endpoints are not necessarily harmonics of one
            // another. Validate the repeating common horizon so two otherwise
            // distinct phases cannot converge into a later cluster.
            let alternateIntervalBars = preferredIntervalBars == intervalBand.lowerBound
                ? intervalBand.upperBound
                : intervalBand.lowerBound
            var selected: (intervalBars: Int, phaseBeat: Double)?
            for intervalBars in [preferredIntervalBars, alternateIntervalBars] {
                guard let phase = candidates.first(where: {
                    isLaneAvailable(
                        phaseBeat: $0,
                        intervalBars: intervalBars,
                        among: lanes,
                        beatsPerBar: beatsPerBar
                    )
                }) else { continue }
                selected = (intervalBars, phase)
                break
            }
            let intervalBars = selected?.intervalBars ?? preferredIntervalBars
            let phase = selected?.phaseBeat ?? preferredPhase
            lanes.append(VoiceLane(
                plan: plan,
                alignment: alignment,
                intervalBars: intervalBars,
                phaseBeat: phase
            ))
        }
        return lanes
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

    private static func isLaneAvailable(
        phaseBeat: Double,
        intervalBars: Int,
        among lanes: [VoiceLane],
        beatsPerBar: Int
    ) -> Bool {
        let candidatePeriod = intervalBars * beatsPerBar
        let horizon = lanes.reduce(candidatePeriod) { partial, lane in
            leastCommonMultiple(partial, lane.intervalBars * beatsPerBar)
        }
        var positions: [Double] = []
        for lane in lanes {
            let period = Double(lane.intervalBars * beatsPerBar)
            var position = normalizedPhase(lane.phaseBeat, period: period)
            while position < Double(horizon) {
                positions.append(position)
                position += period
            }
        }
        var candidatePosition = normalizedPhase(
            phaseBeat,
            period: Double(candidatePeriod)
        )
        while candidatePosition < Double(horizon) {
            positions.append(candidatePosition)
            candidatePosition += Double(candidatePeriod)
        }
        positions.sort()

        for pair in zip(positions, positions.dropFirst())
            where pair.1 - pair.0 < 0.25 - 0.000_001 {
            return false
        }
        if let first = positions.first,
           let last = positions.last,
           first + Double(horizon) - last < 0.25 - 0.000_001 {
            return false
        }
        let attacksByBeat = Dictionary(grouping: positions) { Int($0.rounded(.down)) }
        return attacksByBeat.values.allSatisfy { $0.count <= 2 }
    }

    private static func leastCommonMultiple(_ lhs: Int, _ rhs: Int) -> Int {
        lhs / greatestCommonDivisor(lhs, rhs) * rhs
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var left = lhs
        var right = rhs
        while right != 0 {
            (left, right) = (right, left % right)
        }
        return left
    }

    private static func normalizedPhase(_ phase: Double, period: Double) -> Double {
        let remainder = phase.truncatingRemainder(dividingBy: period)
        return remainder >= 0 ? remainder : remainder + period
    }
}
#endif
