#if DEBUG || INTERNAL_BUILD
import Combine
import Foundation

@MainActor
final class DayObjectsLabMusicViewModel: ObservableObject {
    static let maximumSteps = 10_000.0
    static let maximumSleepHours = 8.0
    static let maximumHappenings = 10
    static let maximumSpentColors = 100

    @Published private(set) var state: DayObjectsLabMusicState
    private var musicVariantHistory: [(seed: UInt64, world: DayObjectsSoundWorld)] = []

    init(state: DayObjectsLabMusicState = DayObjectsLabMusicState()) {
        self.state = state
        setSteps(state.steps)
        setSleepHours(state.sleepHours)
        setHappeningCount(state.happeningCount)
        setSpentColors(state.spentColors)
    }

    var happeningIDs: [String] {
        guard state.happeningCount > 0 else { return [] }
        return (1...state.happeningCount).map { index in
            String(format: "lab-happening-%02d", index)
        }
    }

    var dayMusicInput: DayMusicInput {
        DayMusicInput(
            countedSteps: state.steps,
            stepGoal: state.stepGoal,
            countedSleepHours: state.sleepHours,
            sleepGoalHours: state.sleepGoalHours,
            happeningIDs: happeningIDs,
            spentColors: state.spentColors
        )
    }

    var normalizedInput: NormalizedDayMusicInput {
        dayMusicInput.normalized()
    }

    var canUndoMusicRemix: Bool { !musicVariantHistory.isEmpty }

    var musicPlan: DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: dayMusicInput,
            remixSeed: state.remixSeed,
            soundWorld: state.soundWorld
        )
    }

    var digitalImpact: DayObjectDigitalImpact {
        DayObjectDigitalImpact(spentColors: state.spentColors)
    }

    var worldSummary: String {
        let world = musicPlan.world
        let center = Self.pitchClassNames[world.centerPitchClass]
        let mode = Self.modeName(world.mode)
        let chordCount = world.progression.count
        let chordLabel = chordCount == 1 ? "chord" : "chords"
        return "\(center) \(mode) · \(chordCount) \(chordLabel) · \(world.cycleBars)-bar cycle"
    }

    func setSteps(_ value: Double) {
        updateState { state in
            state.steps = Self.clamp(value, to: 0...Self.maximumSteps)
        }
    }

    func setSleepHours(_ value: Double) {
        updateState { state in
            state.sleepHours = Self.clamp(value, to: 0...Self.maximumSleepHours)
        }
    }

    func setHappeningCount(_ value: Int) {
        updateState { state in
            state.happeningCount = min(max(value, 0), Self.maximumHappenings)
        }
    }

    func setSpentColors(_ value: Int) {
        updateState { state in
            state.spentColors = min(max(value, 0), Self.maximumSpentColors)
        }
    }

    func remix() {
        rememberCurrentMusicVariant()
        updateState { state in
            state.remixSeed &+= 1
        }
    }

    func selectSoundWorld(_ soundWorld: DayObjectsSoundWorld) {
        guard state.soundWorld != soundWorld else { return }
        rememberCurrentMusicVariant()
        updateState { $0.soundWorld = soundWorld }
    }

    func undoMusicRemix() {
        guard let previous = musicVariantHistory.popLast() else { return }
        updateState {
            $0.remixSeed = previous.seed
            $0.soundWorld = previous.world
        }
    }

    func sceneInput(
        dayKey: String,
        motionEnergyOverride: Double? = nil,
        visualClarityOverride: Double? = nil,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls
    ) -> DayObjectSceneInput {
        let normalized = normalizedInput
        let derivedInput = DayObjectSceneInput.labPreview(
            dayKey: dayKey,
            eventIDs: normalized.happeningIDs,
            stepsProgress: normalized.stepsProgress,
            sleepProgress: normalized.sleepProgress,
            uiExclusionRegion: uiExclusionRegion
        )
        guard motionEnergyOverride != nil || visualClarityOverride != nil else {
            return derivedInput
        }
        return DayObjectSceneInput(
            dayKey: derivedInput.dayKey,
            identity: derivedInput.identity,
            eventIDs: derivedInput.eventIDs,
            motionEnergy: motionEnergyOverride ?? derivedInput.motionEnergy,
            visualClarity: visualClarityOverride ?? derivedInput.visualClarity,
            uiExclusionRegion: derivedInput.uiExclusionRegion
        )
    }

    private func updateState(_ update: (inout DayObjectsLabMusicState) -> Void) {
        var updated = state
        update(&updated)
        state = updated
    }

    private func rememberCurrentMusicVariant() {
        musicVariantHistory.append((state.remixSeed, state.soundWorld))
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static let pitchClassNames = [
        "C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B",
    ]

    private static func modeName(_ mode: DayMusicMode) -> String {
        switch mode {
        case .dorian: "Dorian"
        case .aeolian: "Aeolian"
        case .mixolydian: "Mixolydian"
        case .majorPentatonic: "major pentatonic"
        }
    }
}
#endif
