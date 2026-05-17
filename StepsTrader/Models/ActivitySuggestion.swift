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
    var suggestedCategory: EnergyCategory { Self.mapToCategory(activityType: activityType) }
    var activityName: String { Self.displayName(for: activityType) }

    private static func mapToOptionId(activityType: UInt) -> String? {
        switch activityType {
        case 37: return "body_walking"
        case 52: return "body_walking"
        case 13: return "body_physical_effort"
        case 46: return "body_physical_effort"
        case 50: return "body_physical_effort"
        case 20: return "body_physical_effort"
        case 35: return "body_physical_effort"
        case 16: return "body_physical_effort"
        case 56: return "body_physical_effort"
        case 24: return "body_stretching"
        case 36: return "body_physical_effort"
        case 57: return "body_stretching"
        case 63: return "body_stretching"
        case 38: return "body_physical_effort"
        case 17: return "body_physical_effort"
        case 47: return "body_physical_effort"
        case 62: return "body_resting"
        case 6:  return "body_physical_effort"
        case 25: return "body_physical_effort"
        case 32: return "body_physical_effort"
        case 10: return "body_physical_effort"
        case 55: return "body_physical_effort"
        case 4:  return "body_physical_effort"
        case 15: return nil
        case 3000: return nil
        default:
            AppLogger.app.debug("⚠️ DetectedWorkout.mapToOptionId: no mapping for HKWorkoutActivityType raw=\(activityType, privacy: .public) (name=\(displayName(for: activityType), privacy: .public))")
            return nil
        }
    }

    private static func mapToCategory(activityType: UInt) -> EnergyCategory {
        switch activityType {
        case 62: return .body
        default: return .body
        }
    }

    static func displayName(for activityType: UInt) -> String {
        switch activityType {
        case 37: return "Walking"
        case 52: return "Running"
        case 13: return "Cycling"
        case 46: return "Strength Training"
        case 50: return "Strength Training"
        case 20: return "Cross Training"
        case 35: return "Stair Climbing"
        case 16: return "Core Training"
        case 56: return "Swimming"
        case 24: return "Yoga"
        case 36: return "Pilates"
        case 57: return "Tai Chi"
        case 63: return "Flexibility"
        case 38: return "Hiking"
        case 17: return "Dance"
        case 47: return "HIIT"
        case 62: return "Mind & Body"
        case 6:  return "Boxing"
        case 25: return "Tennis"
        case 32: return "Rowing"
        case 10: return "Climbing"
        case 55: return "Soccer"
        case 4:  return "Basketball"
        case 15: return "Cooldown"
        case 3000: return "Other"
        default: return "Workout"
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
    let category: EnergyCategory
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
            category: workout.suggestedCategory,
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
            optionId: "body_resting",
            category: .body,
            source: .mindfulSession(minutes: minutes),
            title: "Mindful Session",
            subtitle: "\(mins) min today",
            icon: "brain.head.profile.fill"
        )
    }

    static func fromLowScreenTime() -> ActivitySuggestion {
        ActivitySuggestion(
            id: "low_screen_time",
            optionId: "mind_screen_detox",
            category: .mind,
            source: .lowScreenTime,
            title: "Screen Detoxing",
            subtitle: "Low screen time today",
            icon: "iphone.slash"
        )
    }

    static func fromMorningResting() -> ActivitySuggestion {
        ActivitySuggestion(
            id: "morning_resting",
            optionId: "body_resting",
            category: .body,
            source: .morningResting,
            title: String(localized: "Resting", comment: "Morning resting suggestion – title"),
            subtitle: String(localized: "You slept — add it to your canvas", comment: "Morning resting suggestion – subtitle"),
            icon: "bed.double.fill"
        )
    }

    private static func workoutIcon(for activityType: UInt) -> String {
        switch activityType {
        case 37: return "figure.walk"
        case 52: return "figure.run"
        case 13: return "figure.outdoor.cycle"
        case 56: return "figure.pool.swim"
        case 24: return "figure.yoga"
        case 36: return "figure.pilates"
        case 38: return "figure.hiking"
        case 17: return "figure.dance"
        case 47: return "flame.fill"
        case 46, 50: return "dumbbell.fill"
        case 10: return "figure.climbing"
        case 25: return "figure.tennis"
        case 55: return "soccerball"
        case 4:  return "figure.basketball"
        case 32: return "figure.rowing"
        case 6:  return "figure.boxing"
        case 57: return "figure.taichi"
        default: return "figure.run"
        }
    }
}
