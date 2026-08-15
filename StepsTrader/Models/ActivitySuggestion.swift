import Foundation
import HealthKit
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
        "health_workout_\(activityType)"
    }

    static func displayName(for activityType: UInt) -> String {
        switch HKWorkoutActivityType(rawValue: activityType) {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "Strength Training"
        case .crossTraining: "Cross Training"
        case .stairClimbing, .stairs, .stepTraining: "Stair Climbing"
        case .coreTraining: "Core Training"
        case .swimming: "Swimming"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .taiChi: "Tai Chi"
        case .flexibility: "Flexibility"
        case .hiking: "Hiking"
        case .dance, .cardioDance, .socialDance: "Dance"
        case .highIntensityIntervalTraining: "HIIT"
        case .mindAndBody: "Mind & Body"
        case .boxing, .kickboxing: "Boxing"
        case .tennis: "Tennis"
        case .rowing: "Rowing"
        case .climbing: "Climbing"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .cooldown: "Cooldown"
        case .other: "Workout"
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
        switch HKWorkoutActivityType(rawValue: activityType) {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .hiking: "figure.hiking"
        case .dance, .cardioDance, .socialDance: "figure.dance"
        case .highIntensityIntervalTraining: "flame.fill"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "dumbbell.fill"
        case .climbing: "figure.climbing"
        case .tennis: "figure.tennis"
        case .soccer: "soccerball"
        case .basketball: "figure.basketball"
        case .rowing: "figure.rowing"
        case .boxing, .kickboxing: "figure.boxing"
        case .taiChi: "figure.taichi"
        default: "figure.run"
        }
    }
}
