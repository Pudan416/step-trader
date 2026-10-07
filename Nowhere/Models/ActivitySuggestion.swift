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
        // NS_ENUM accepts unknown raw values too. Restrict new suggestions to
        // documented HealthKit workout kinds; historical IDs still resolve separately.
        guard (1...80).contains(activityType)
                || (82...84).contains(activityType)
                || activityType == HKWorkoutActivityType.other.rawValue else { return nil }
        let id = HappeningDefaults.canonicalID("health_workout_\(activityType)")
        return HappeningDefaults.selectableHappening(id: id)?.id
    }

    static func displayName(for activityType: UInt) -> String {
        switch HKWorkoutActivityType(rawValue: activityType) {
        case .americanFootball: "Football"
        case .archery: "Archery"
        case .australianFootball: "Aussie Rules"
        case .badminton: "Badminton"
        case .baseball: "Baseball"
        case .bowling: "Bowling"
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .elliptical: "Elliptical"
        case .equestrianSports: "Horse Riding"
        case .fencing: "Fencing"
        case .fishing: "Fishing"
        case .golf: "Golf"
        case .gymnastics: "Gymnastics"
        case .handball: "Handball"
        case .hockey: "Hockey"
        case .hunting: "Hunting"
        case .lacrosse: "Lacrosse"
        case .martialArts: "Martial Arts"
        case .paddleSports: "Paddle Sports"
        case .play: "Play"
        case .preparationAndRecovery: "Recovery"
        case .racquetball: "Racquetball"
        case .rugby: "Rugby"
        case .sailing: "Sailing"
        case .skatingSports: "Skating"
        case .snowSports: "Snow Sports"
        case .softball: "Softball"
        case .squash: "Squash"
        case .surfingSports: "Surfing"
        case .tableTennis: "Table Tennis"
        case .volleyball: "Volleyball"
        case .waterFitness: "Water Fitness"
        case .waterPolo: "Water Polo"
        case .waterSports: "Water Sports"
        case .wrestling: "Wrestling"
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
        default: "Workout \(activityType)"
        }
    }
}

enum SuggestionSource: Equatable {
    case workout(DetectedWorkout)
    case mindfulSession(minutes: Double)
    case lowScreenTime

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

    /// Canvas happenings that make this suggestion redundant.
    ///
    /// The first id is what a tap adds today. The remaining ids bridge the
    /// old category model and the built-in happenings that express the same
    /// real-world event. Keeping the equivalence here prevents refresh,
    /// rendering and manual canvas additions from inventing different rules.
    var satisfyingOptionIds: Set<String> {
        var ids: Set<String> = [optionId]

        switch source {
        case .workout(let workout):
            ids.insert("health_workout_\(workout.activityType)")
            if HappeningDefaults.canonicalID(optionId) == "event_workout" {
                ids.formUnion(["happening_workout", "body_physical_effort"])
            }
            if HKWorkoutActivityType(rawValue: workout.activityType) == .walking {
                ids.formUnion(["happening_walk", "body_walking"])
            }
        case .mindfulSession:
            ids.insert("body_resting")
        case .lowScreenTime:
            ids.insert("mind_screen_detox")
        }

        return ids
    }

    func isSatisfied(by addedOptionIds: Set<String>) -> Bool {
        let expected = Set(satisfyingOptionIds.map(HappeningDefaults.canonicalID))
        let added = Set(addedOptionIds.map(HappeningDefaults.canonicalID))
        return !expected.isDisjoint(with: added)
    }

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
            title: "Low screen time",
            subtitle: "Low screen time today",
            icon: "iphone.slash"
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
