import Foundation

enum EnergyDefaults {
    static let maxBaseEnergy: Int = 100

    static let sleepTargetHours: Double = 8
    static let sleepMaxPoints: Int = 20
    static let assumedSleepPoints: Int = 10
    static let stepsTarget: Double = 10_000
    static let stepsMaxPoints: Int = 20

    /// English titles for the 31 options that existed before happenings.
    ///
    /// Kept solely so a saved day whose element ids predate the change still
    /// renders a real label instead of a raw id. `AppModel.resolveOptionTitle`
    /// falls through to this when the happening catalog has no entry, and
    /// `HappeningStore.reconstituteOrphans` uses the same route. Nothing writes
    /// these ids any more — do not add to this table.
    static let legacyOptionTitles: [String: String] = [
        "body_walking": "Walking",
        "body_physical_effort": "Physical Effort",
        "body_stretching": "Stretching",
        "body_resting": "Resting",
        "body_breathing": "Breathing",
        "body_touch": "Touch",
        "body_balance": "Balance",
        "body_repetition": "Repetition",
        "body_warming": "Warming",
        "body_stillness": "Stillness",
        "body_healing": "Healing",

        "mind_focusing": "Focusing",
        "mind_learning": "Learning",
        "mind_thinking": "Thinking",
        "mind_planning": "Planning",
        "mind_writing": "Writing",
        "mind_observing": "Observing",
        "mind_questioning": "Questioning",
        "mind_ordering": "Ordering",
        "mind_remembering": "Remembering",
        "mind_screen_detox": "Screen Detoxing",

        "heart_joy": "Joy",
        "heart_calm": "Calm",
        "heart_gratitude": "Gratitude",
        "heart_connection": "Connection",
        "heart_care": "Care",
        "heart_wonder": "Wonder",
        "heart_trust": "Trust",
        "heart_vulnerability": "Vulnerability",
        "heart_belonging": "Belonging",
        "heart_peace": "Peace",
    ]

    /// Localized title for a legacy option id, or nil if it is not one.
    /// Resolves through `option.title.<id>` exactly as the old model did, so
    /// translated copy already in the catalog keeps working.
    static func legacyTitle(for optionId: String) -> String? {
        guard let fallback = legacyOptionTitles[optionId] else { return nil }
        return Bundle.main.localizedString(
            forKey: "option.title.\(optionId)", value: fallback, table: nil
        )
    }
}

enum DayEndOptions {
    static let minuteStep: Int = 15

    static var allowedMinutes: [Int] {
        var result: [Int] = []
        for m in stride(from: 21 * 60, to: 24 * 60, by: minuteStep) { result.append(m) }
        for m in stride(from: 0, through: 3 * 60, by: minuteStep) { result.append(m) }
        return result
    }

    static func nearestAllowed(to current: Int) -> Int {
        let allowed = allowedMinutes
        let normalized = ((current % (24 * 60)) + (24 * 60)) % (24 * 60)
        return allowed.min { lhs, rhs in
            wrappedDistance(from: normalized, to: lhs) < wrappedDistance(from: normalized, to: rhs)
        } ?? (23 * 60)
    }

    private static func wrappedDistance(from a: Int, to b: Int) -> Int {
        let d = abs(a - b)
        return min(d, 24 * 60 - d)
    }
}
