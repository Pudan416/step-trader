import Foundation
import SwiftUI

struct DetectedWorkout: Identifiable, Equatable {
    let id: UUID
    let activityType: UInt
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
    let caloriesBurned: Double?
    let distance: Double?

    var suggestedOptionId: String? { Self.mapToOptionId(activityType: activityType) }
    var activityName: String { Self.displayName(for: activityType) }

    private static func mapToOptionId(activityType: UInt) -> String? {
        switch activityType {
        case 37, 52: return "happening_walk"
        case 13: return "happening_workout"
        case 46, 50, 20, 35, 16, 56, 24, 36, 57, 63, 38, 17, 47, 62, 6, 25, 32, 10, 55, 4:
            return "happening_workout"
        case 15: return nil
        case 3000: return nil
        default:
            AppLogger.app.debug("⚠️ DetectedWorkout.mapToOptionId: no mapping for HKWorkoutActivityType raw=\(activityType, privacy: .public) (name=\(displayName(for: activityType), privacy: .public))")
            return nil
        }
    }

    static func displayName(for activityType: UInt) -> String {
        switch activityType {
        case 37: "Walking"
        case 52: "Running"
        case 13: "Cycling"
        case 46: "Strength Training"
        case 50: "Strength Training"
        case 20: "Cross Training"
        case 35: "Stair Climbing"
        case 16: "Core Training"
        case 56: "Swimming"
        case 24: "Yoga"
        case 36: "Pilates"
        case 57: "Tai Chi"
        case 63: "Flexibility"
        case 38: "Hiking"
        case 17: "Dance"
        case 47: "HIIT"
        case 62: "Mind & Body"
        case 6:  "Boxing"
        case 25: "Tennis"
        case 32: "Rowing"
        case 10: "Climbing"
        case 55: "Soccer"
        case 4:  "Basketball"
        case 15: "Cooldown"
        case 3000: "Other"
        default: "Workout"
        }
    }
}

enum SuggestionSource: Equatable {
    case workout(DetectedWorkout)
    case mindfulSession(minutes: Double)
    case lowScreenTime
    case morningResting

    var isWorkout: Bool {
        if case .workout = self { return true }
        return false
    }
}

struct ActivitySuggestion: Identifiable, Equatable {
    let id: String
    let optionId: String
    let source: SuggestionSource
    let title: String
    let subtitle: String
    let icon: String

    static func fromWorkout(_ workout: DetectedWorkout) -> ActivitySuggestion? {
        guard let optionId = workout.suggestedOptionId else { return nil }
        var subtitle = "\(workout.durationMinutes) min"
        if let cal = workout.caloriesBurned, cal > 0 {
            subtitle += " · \(Int(cal)) kcal"
        }
        return ActivitySuggestion(
            id: "workout_\(workout.id.uuidString)",
            optionId: optionId,
            source: .workout(workout),
            title: workout.activityName,
            subtitle: subtitle,
            icon: workoutIcon(for: workout.activityType)
        )
    }

    static func fromMindfulMinutes(_ minutes: Double) -> ActivitySuggestion {
        let mins = Int(minutes)
        return ActivitySuggestion(
            id: "mindful_\(mins)",
            optionId: "happening_did_nothing",
            source: .mindfulSession(minutes: minutes),
            title: "Mindful Session",
            subtitle: "\(mins) min today",
            icon: "brain.head.profile.fill"
        )
    }

    static func fromLowScreenTime() -> ActivitySuggestion {
        ActivitySuggestion(
            id: "low_screen_time",
            optionId: "happening_did_nothing",
            source: .lowScreenTime,
            title: "Screen Detoxing",
            subtitle: "Low screen time today",
            icon: "iphone.slash"
        )
    }

    static func fromMorningResting() -> ActivitySuggestion {
        ActivitySuggestion(
            id: "morning_resting",
            optionId: "happening_slept_well",
            source: .morningResting,
            title: String(localized: "Resting", comment: "Morning resting suggestion – title"),
            subtitle: String(localized: "You slept — add it to your canvas", comment: "Morning resting suggestion – subtitle"),
            icon: "bed.double.fill"
        )
    }

    private static func workoutIcon(for activityType: UInt) -> String {
        switch activityType {
        case 37: "figure.walk"
        case 52: "figure.run"
        case 13: "figure.outdoor.cycle"
        case 56: "figure.pool.swim"
        case 24: "figure.yoga"
        case 36: "figure.pilates"
        case 38: "figure.hiking"
        case 17: "figure.dance"
        case 47: "flame.fill"
        case 46, 50: "dumbbell.fill"
        case 10: "figure.climbing"
        case 25: "figure.tennis"
        case 55: "soccerball"
        case 4:  "figure.basketball"
        case 32: "figure.rowing"
        case 6:  "figure.boxing"
        case 57: "figure.taichi"
        default: "figure.run"
        }
    }
}
