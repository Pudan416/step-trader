import Foundation

// MARK: - Proactive Activity Suggestions (HealthKit + behavioral signals → Canvas)
extension AppModel {

    /// All pending suggestions from every source, filtered and deduped.
    var pendingActivitySuggestions: [ActivitySuggestion] {
        get {
            let addedOptionIds = Set(todayAdditions.map(\.optionId))
            return _pendingActivitySuggestions.filter { !$0.isSatisfied(by: addedOptionIds) }
        }
        set {
            _pendingActivitySuggestions = newValue
            objectWillChange.send()
        }
    }

    // Keep backward compat — the GalleryView reads this
    var pendingWorkoutSuggestions: [DetectedWorkout] {
        _pendingWorkoutSuggestions
    }

    /// Main refresh: gathers signals from all sources and builds the unified suggestion list.
    func refreshActivitySuggestions() async {
        let alreadyAdded = Set(todayAdditions.map(\.optionId))
        let dismissed = dismissedSuggestionIds

        var suggestions: [ActivitySuggestion] = []

        // 1. Workouts from HealthKit
        let workouts = await healthStore.fetchTodayWorkouts()
        let workoutSuggestions = buildWorkoutSuggestions(
            workouts,
            dismissed: dismissed
        )
        suggestions.append(contentsOf: workoutSuggestions)

        // 2. Mindful minutes from HealthKit
        let mindfulMinutes = await healthStore.fetchTodayMindfulMinutes()
        if mindfulMinutes >= 3,
           !dismissed.contains("mindful_\(Int(mindfulMinutes))") {
            suggestions.append(.fromMindfulMinutes(mindfulMinutes))
        }

        // 3. Low screen time signal (from existing app tracking)
        if shouldSuggestLowScreenTime(dismissed: dismissed) {
            suggestions.append(.fromLowScreenTime())
        }

        // 4. Generic morning resting stays behind concrete detected events in
        // the visual stack, so a fresh HealthKit activity leads.
        if !dismissed.contains("morning_resting") {
            suggestions.append(.fromMorningResting())
        }

        let satisfiedSuggestionIds = suggestions
            .filter { $0.isSatisfied(by: alreadyAdded) }
            .map(\.id)
        suggestions.removeAll { $0.isSatisfied(by: alreadyAdded) }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("ui-testing-suggestion-stack") {
            suggestions = [
                .fromMindfulMinutes(12),
                .fromMorningResting(),
                .fromLowScreenTime()
            ]
        }
        #endif

        let previousIds = Set(_pendingActivitySuggestions.map(\.id))
        let currentIds = Set(suggestions.map(\.id))
        let removedIds = Array(
            previousIds.subtracting(currentIds).union(satisfiedSuggestionIds)
        )
        (notificationService as? NotificationManager)?
            .removeActivityDetectedNotifications(suggestionIds: removedIds)

        let newSuggestions = suggestions.filter { !previousIds.contains($0.id) }
        for suggestion in newSuggestions where suggestion.source.isWorkout {
            (notificationService as? NotificationManager)?
                .sendActivityDetectedNotification(for: suggestion)
        }

        pendingActivitySuggestions = suggestions
        _pendingWorkoutSuggestions = workouts.filter { $0.durationMinutes >= 5 }
    }

    // Keep old name working for bootstrap/foreground calls
    func refreshWorkoutSuggestions() async {
        await refreshActivitySuggestions()
    }

    // MARK: - Workout Suggestions

    private func buildWorkoutSuggestions(
        _ workouts: [DetectedWorkout],
        dismissed: Set<String>
    ) -> [ActivitySuggestion] {
        let filtered = workouts.filter { workout in
            guard workout.suggestedOptionId != nil else { return false }
            if dismissed.contains("workout_\(workout.id.uuidString)") { return false }
            if workout.durationMinutes < 5 { return false }
            return true
        }

        // Deduplicate by option (keep longest per option)
        var bestByOption: [String: DetectedWorkout] = [:]
        for w in filtered {
            guard let optionId = w.suggestedOptionId else { continue }
            if let existing = bestByOption[optionId] {
                if w.durationMinutes > existing.durationMinutes {
                    bestByOption[optionId] = w
                }
            } else {
                bestByOption[optionId] = w
            }
        }

        return bestByOption.values
            .sorted { $0.startDate > $1.startDate }
            .compactMap { ActivitySuggestion.fromWorkout($0) }
    }

    // MARK: - Low Screen Time Signal

    private func shouldSuggestLowScreenTime(dismissed: Set<String>) -> Bool {
        guard !dismissed.contains("low_screen_time") else { return false }

        let hour = Calendar.current.component(.hour, from: Date.now)
        guard hour >= 14 else { return false }

        // Only meaningful when user has blocked apps configured
        guard !blockingStore.ticketGroups.isEmpty else { return false }

        let totalSpent = appStepsSpentToday.values.reduce(0, +)
        guard totalSpent == 0 else { return false }

        // Extra confidence: user walked at least 3000 steps (active day, not just idle)
        return stepsToday >= 3000
    }

    // MARK: - Accept / Dismiss

    /// Removes suggestions whose real-world event has since been added by any
    /// path (palette, routine, sync, or suggestion tap).
    func removeSatisfiedActivitySuggestions() {
        let addedOptionIds = Set(todayAdditions.map(\.optionId))
        let removedIds = _pendingActivitySuggestions
            .filter { $0.isSatisfied(by: addedOptionIds) }
            .map(\.id)
        guard !removedIds.isEmpty else { return }

        let removedSet = Set(removedIds)
        pendingActivitySuggestions.removeAll { removedSet.contains($0.id) }
        (notificationService as? NotificationManager)?
            .removeActivityDetectedNotifications(suggestionIds: removedIds)
    }

    @discardableResult
    func acceptActivitySuggestion(_ suggestion: ActivitySuggestion) -> String? {
        let optionId: String
        if case .workout(let workout) = suggestion.source {
            guard let workoutOptionId = workout.suggestedOptionId,
                  installExternalPaletteHappening(
                    id: workoutOptionId,
                    title: workout.activityName
                  ) != nil else {
                return nil
            }
            optionId = workoutOptionId
        } else {
            optionId = suggestion.optionId
        }
        guard canAddHappening(id: optionId) else {
            removeSatisfiedActivitySuggestions()
            return nil
        }
        pendingActivitySuggestions.removeAll { $0.id == suggestion.id }
        (notificationService as? NotificationManager)?
            .removeActivityDetectedNotifications(suggestionIds: [suggestion.id])
        return optionId
    }

    func dismissActivitySuggestion(_ suggestion: ActivitySuggestion) {
        var dismissed = dismissedSuggestionIds
        dismissed.insert(suggestion.id)
        saveDismissedSuggestionIds(dismissed)
        pendingActivitySuggestions.removeAll { $0.id == suggestion.id }
        (notificationService as? NotificationManager)?
            .removeActivityDetectedNotifications(suggestionIds: [suggestion.id])
    }

    func dismissAllActivitySuggestions() {
        var dismissed = dismissedSuggestionIds
        for s in pendingActivitySuggestions {
            dismissed.insert(s.id)
        }
        let removedIds = pendingActivitySuggestions.map(\.id)
        saveDismissedSuggestionIds(dismissed)
        pendingActivitySuggestions = []
        (notificationService as? NotificationManager)?
            .removeActivityDetectedNotifications(suggestionIds: removedIds)
    }

    // Legacy wrappers for GalleryView (keep existing calls working)
    func acceptWorkoutSuggestion(_ workout: DetectedWorkout) {
        if let suggestion = pendingActivitySuggestions.first(where: {
            if case .workout(let w) = $0.source { return w.id == workout.id }
            return false
        }) {
            acceptActivitySuggestion(suggestion)
        }
    }

    func dismissWorkoutSuggestion(_ workout: DetectedWorkout) {
        if let suggestion = pendingActivitySuggestions.first(where: {
            if case .workout(let w) = $0.source { return w.id == workout.id }
            return false
        }) {
            dismissActivitySuggestion(suggestion)
        }
    }

    func dismissAllWorkoutSuggestions() {
        dismissAllActivitySuggestions()
    }

    /// Called on day boundary reset.
    func clearDismissedWorkouts() {
        UserDefaults.stepsTrader().removeObject(forKey: Self.dismissedSuggestionsKey)
        pendingActivitySuggestions = []
        _pendingWorkoutSuggestions = []
    }

    // MARK: - Persistence

    private static let dismissedSuggestionsKey = "dismissedSuggestionIds_v1"

    private var dismissedSuggestionIds: Set<String> {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: Self.dismissedSuggestionsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveDismissedSuggestionIds(_ ids: Set<String>) {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(ids) {
            g.set(data, forKey: Self.dismissedSuggestionsKey)
        }
    }
}
