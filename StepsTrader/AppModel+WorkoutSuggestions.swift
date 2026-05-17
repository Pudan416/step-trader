import Foundation

// MARK: - Proactive Activity Suggestions (HealthKit + behavioral signals → Canvas)
extension AppModel {

    /// All pending suggestions from every source, filtered and deduped.
    var pendingActivitySuggestions: [ActivitySuggestion] {
        get { _pendingActivitySuggestions }
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
        let alreadyAdded = Set(dailyActivitySelections + dailyRestSelections + dailyJoysSelections)
        let dismissed = dismissedSuggestionIds

        var suggestions: [ActivitySuggestion] = []

        // 1. Workouts from HealthKit
        let workouts = await healthStore.fetchTodayWorkouts()
        let workoutSuggestions = buildWorkoutSuggestions(workouts, alreadyAdded: alreadyAdded, dismissed: dismissed)
        suggestions.append(contentsOf: workoutSuggestions)

        // 2. Mindful minutes from HealthKit
        let mindfulMinutes = await healthStore.fetchTodayMindfulMinutes()
        if mindfulMinutes >= 3,
           !alreadyAdded.contains("body_resting"),
           !dismissed.contains("mindful_\(Int(mindfulMinutes))"),
           !isDailyLimitReached(for: .body) {
            suggestions.append(.fromMindfulMinutes(mindfulMinutes))
        }

        // 3. Morning resting — every new day, suggest adding "Resting" to canvas
        if !alreadyAdded.contains("body_resting"),
           !dismissed.contains("morning_resting"),
           !isDailyLimitReached(for: .body) {
            suggestions.insert(.fromMorningResting(), at: 0)
        }

        // 4. Low screen time signal (from existing app tracking)
        if shouldSuggestLowScreenTime(alreadyAdded: alreadyAdded, dismissed: dismissed) {
            suggestions.append(.fromLowScreenTime())
        }

        let previousIds = Set(_pendingActivitySuggestions.map(\.id))
        let newSuggestions = suggestions.filter { !previousIds.contains($0.id) }

        for suggestion in newSuggestions where suggestion.source.isWorkout {
            (notificationService as? NotificationManager)?
                .sendActivityDetectedNotification(title: suggestion.title, subtitle: suggestion.subtitle)
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
        alreadyAdded: Set<String>,
        dismissed: Set<String>
    ) -> [ActivitySuggestion] {
        let filtered = workouts.filter { workout in
            guard let optionId = workout.suggestedOptionId else { return false }
            if dismissed.contains("workout_\(workout.id.uuidString)") { return false }
            if alreadyAdded.contains(optionId) { return false }
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

    private func shouldSuggestLowScreenTime(alreadyAdded: Set<String>, dismissed: Set<String>) -> Bool {
        guard !alreadyAdded.contains("mind_screen_detox") else { return false }
        guard !dismissed.contains("low_screen_time") else { return false }
        guard !isDailyLimitReached(for: .mind) else { return false }

        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 14 else { return false }

        // Only meaningful when user has blocked apps configured
        guard !blockingStore.ticketGroups.isEmpty else { return false }

        let totalSpent = appStepsSpentToday.values.reduce(0, +)
        guard totalSpent == 0 else { return false }

        // Extra confidence: user walked at least 3000 steps (active day, not just idle)
        return stepsToday >= 3000
    }

    // MARK: - Accept / Dismiss

    func acceptActivitySuggestion(_ suggestion: ActivitySuggestion) {
        let category = suggestion.category
        let optionId = suggestion.optionId

        if !isDailySelected(optionId, category: category) &&
           !isDailyLimitReached(for: category) {
            toggleDailySelection(optionId: optionId, category: category)
        }

        pendingActivitySuggestions.removeAll { $0.id == suggestion.id }
    }

    func dismissActivitySuggestion(_ suggestion: ActivitySuggestion) {
        var dismissed = dismissedSuggestionIds
        dismissed.insert(suggestion.id)
        saveDismissedSuggestionIds(dismissed)
        pendingActivitySuggestions.removeAll { $0.id == suggestion.id }
    }

    func dismissAllActivitySuggestions() {
        var dismissed = dismissedSuggestionIds
        for s in pendingActivitySuggestions {
            dismissed.insert(s.id)
        }
        saveDismissedSuggestionIds(dismissed)
        pendingActivitySuggestions = []
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
