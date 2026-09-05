#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayMusicInput: Equatable, Sendable {
    let countedSteps: Double
    let stepGoal: Double
    let countedSleepHours: Double
    let sleepGoalHours: Double
    let happeningIDs: [String]
    let spentColors: Int
}

extension DayMusicInput {
    func normalized() -> NormalizedDayMusicInput {
        var diagnostics: [DayMusicDiagnostic] = []

        let validCountedSteps = countedSteps.isFinite && countedSteps >= 0
        if !validCountedSteps {
            diagnostics.append(.invalidCountedSteps)
        }

        let validStepGoal = stepGoal.isFinite && stepGoal > 0
        if !validStepGoal {
            diagnostics.append(.invalidStepGoal)
        }

        let validCountedSleepHours = countedSleepHours.isFinite && countedSleepHours >= 0
        if !validCountedSleepHours {
            diagnostics.append(.invalidCountedSleepHours)
        }

        let validSleepGoal = sleepGoalHours.isFinite && sleepGoalHours > 0
        if !validSleepGoal {
            diagnostics.append(.invalidSleepGoal)
        }

        let sanitizedSteps = validCountedSteps ? countedSteps : 0
        let sanitizedSleepHours = validCountedSleepHours ? countedSleepHours : 0
        let stepsProgress = validStepGoal ? min(max(sanitizedSteps / stepGoal, 0), 1) : 0
        let sleepProgress = validSleepGoal ? min(max(sanitizedSleepHours / sleepGoalHours, 0), 1) : 0

        var normalizedHappeningIDs: [String] = []
        var seenHappeningIDs = Set<String>()
        for happeningID in happeningIDs {
            guard !happeningID.isEmpty else {
                diagnostics.append(.emptyHappeningID)
                continue
            }
            guard seenHappeningIDs.insert(happeningID).inserted else {
                continue
            }
            guard normalizedHappeningIDs.count < 10 else {
                diagnostics.append(.happeningIDLimitReached)
                continue
            }
            normalizedHappeningIDs.append(happeningID)
        }

        let clampedSpentColors = min(max(spentColors, 0), 100)
        let glitchProgress = pow(Double(clampedSpentColors) / 100, 2)

        return NormalizedDayMusicInput(
            stepsProgress: stepsProgress,
            sleepProgress: sleepProgress,
            happeningIDs: normalizedHappeningIDs,
            glitchProgress: glitchProgress,
            motionEnergy: 0.25 + 0.75 * stepsProgress,
            visualClarity: 0.35 + 0.55 * sleepProgress,
            diagnostics: diagnostics
        )
    }
}
#endif
