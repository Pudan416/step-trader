#if DEBUG || INTERNAL_BUILD
enum TonalWorldPlanner {
    private static let allowedCenterPitchClasses = [0, 2, 4, 5, 7, 9]

    static func makePlan(
        input: NormalizedDayMusicInput,
        remixSeed: UInt64
    ) -> TonalWorldPlan {
        var keyRandom = StableMusicRandom(seed: remixSeed, domain: .worldKey)
        var modeRandom = StableMusicRandom(seed: remixSeed, domain: .worldMode)
        var progressionRandom = StableMusicRandom(seed: remixSeed, domain: .worldProgression)

        let centerPitchClass = keyRandom.choice(from: allowedCenterPitchClasses) ?? 0
        let mode = modeRandom.choice(from: DayMusicMode.allCases) ?? .dorian
        let progressionLength = selectedProgressionLength(
            sleepProgress: input.sleepProgress,
            random: &progressionRandom
        )
        let cycleBars = selectedCycleBars(
            sleepProgress: input.sleepProgress,
            random: &progressionRandom
        )

        return makePlan(
            centerPitchClass: centerPitchClass,
            mode: mode,
            progressionLength: progressionLength,
            cycleBars: cycleBars
        )
    }

    static func makePlan(
        centerPitchClass: Int,
        mode: DayMusicMode,
        progressionLength: Int,
        cycleBars: Int
    ) -> TonalWorldPlan {
        let normalizedCenter = normalizedPitchClass(centerPitchClass)
        let safePitchClasses = mode.scaleIntervals.map {
            normalizedPitchClass(normalizedCenter + $0)
        }
        let templateIndex = min(max(progressionLength, 1), mode.progressionDegreeTemplates.count) - 1
        let degrees = mode.progressionDegreeTemplates[templateIndex]
        let durations = chordDurations(chordCount: degrees.count, cycleBars: cycleBars)
        var previousNotes: [UInt8]?

        let progression = degrees.enumerated().map { index, degree -> ChordPlan in
            let rootPitchClass = normalizedPitchClass(normalizedCenter + degree)
            let chordPitchClasses = chordPitchClasses(
                centerPitchClass: normalizedCenter,
                mode: mode,
                modalDegree: degree
            )
            let voicedNotes = AmbientVoiceLeading.nearestVoicing(
                chordPitchClasses: chordPitchClasses,
                previousNotes: previousNotes
            )
            previousNotes = voicedNotes

            return ChordPlan(
                modalDegree: degree,
                rootPitchClass: rootPitchClass,
                chordPitchClasses: chordPitchClasses,
                safePassingPitchClasses: safePitchClasses,
                voicedMIDINotes: voicedNotes,
                durationBars: durations[index]
            )
        }

        return TonalWorldPlan(
            centerPitchClass: normalizedCenter,
            mode: mode,
            scalePitchClasses: safePitchClasses,
            progression: progression,
            cycleBars: max(cycleBars, degrees.count)
        )
    }

    private static func selectedProgressionLength(
        sleepProgress: Double,
        random: inout StableMusicRandom
    ) -> Int {
        if sleepProgress <= 0.35 {
            return 1
        }
        if sleepProgress <= 0.70 {
            return 2
        }
        if sleepProgress < 1 {
            return 3
        }
        return random.choice(from: [3, 4]) ?? 3
    }

    private static func selectedCycleBars(
        sleepProgress: Double,
        random: inout StableMusicRandom
    ) -> Int {
        let options: [Int]
        if sleepProgress <= 0.35 {
            options = [16, 16, 12, 8]
        } else if sleepProgress <= 0.70 {
            options = [16, 12, 8]
        } else {
            options = [12, 8, 16]
        }
        return random.choice(from: options) ?? 16
    }

    private static func chordPitchClasses(
        centerPitchClass: Int,
        mode: DayMusicMode,
        modalDegree: Int
    ) -> [Int] {
        if mode == .majorPentatonic {
            let chordIntervals: [Int]
            switch modalDegree {
            case 0:
                chordIntervals = [0, 7]
            case 5:
                chordIntervals = [0, 2, 7]
            case 9:
                chordIntervals = [0, 7, 10]
            case 7:
                chordIntervals = [0, 5, 7]
            default:
                chordIntervals = [0, 7]
            }
            let root = normalizedPitchClass(centerPitchClass + modalDegree)
            return chordIntervals.map { normalizedPitchClass(root + $0) }
        }

        guard let rootIndex = mode.scaleIntervals.firstIndex(of: modalDegree) else {
            return [normalizedPitchClass(centerPitchClass + modalDegree)]
        }
        let scale = mode.scaleIntervals
        return [rootIndex, rootIndex + 2, rootIndex + 4].map { scaleIndex in
            normalizedPitchClass(centerPitchClass + scale[scaleIndex % scale.count])
        }
    }

    private static func chordDurations(chordCount: Int, cycleBars: Int) -> [Int] {
        let boundedCycleBars = max(cycleBars, chordCount)
        let baseDuration = boundedCycleBars / chordCount
        let remainder = boundedCycleBars % chordCount
        return (0..<chordCount).map { index in
            baseDuration + (index < remainder ? 1 : 0)
        }
    }

    private static func normalizedPitchClass(_ value: Int) -> Int {
        ((value % 12) + 12) % 12
    }
}
#endif
