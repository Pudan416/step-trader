import Foundation

struct PastDaySnapshot: Codable, Equatable {
    var inkEarned: Int
    var inkSpent: Int
    /// Every happening logged that day, flat. Replaces the three per-category
    /// arrays; `init(from:)` still reads both older shapes.
    var happeningIds: [String]
    var steps: Int
    var sleepHours: Double
    var stepsTarget: Double
    var sleepTargetHours: Double

    enum CodingKeys: String, CodingKey {
        case inkEarned
        case inkSpent
        case experienceEarned
        case experienceSpent
        case happeningIds
        case bodyIds
        case mindIds
        case heartIds
        case steps
        case sleepHours
        case stepsTarget
        case sleepTargetHours
        case controlGained
        case controlSpent
        case activityIds
        case creativityIds
        case recoveryIds
        case restIds
        case joysIds
        case moments
    }

    init(
        inkEarned: Int,
        inkSpent: Int,
        happeningIds: [String],
        steps: Int = 0,
        sleepHours: Double = 0,
        stepsTarget: Double = EnergyDefaults.stepsTarget,
        sleepTargetHours: Double = EnergyDefaults.sleepTargetHours
    ) {
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.happeningIds = happeningIds
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let earned = try container.decodeIfPresent(Int.self, forKey: .inkEarned) {
            inkEarned = earned
        } else if let earned = try container.decodeIfPresent(Int.self, forKey: .experienceEarned) {
            inkEarned = earned
        } else {
            inkEarned = (try? container.decodeIfPresent(Int.self, forKey: .controlGained)) ?? 0
        }
        if let spent = try container.decodeIfPresent(Int.self, forKey: .inkSpent) {
            inkSpent = spent
        } else if let spent = try container.decodeIfPresent(Int.self, forKey: .experienceSpent) {
            inkSpent = spent
        } else {
            inkSpent = (try? container.decodeIfPresent(Int.self, forKey: .controlSpent)) ?? 0
        }

        if let flat = try container.decodeIfPresent([String].self, forKey: .happeningIds) {
            happeningIds = flat
        } else {
            // Two older generations, concatenated in the order they were shown:
            // body → mind → heart, each with its own pre-rename alias.
            let body = try (container.decodeIfPresent([String].self, forKey: .bodyIds)
                ?? container.decodeIfPresent([String].self, forKey: .activityIds)) ?? []

            var mind = (try container.decodeIfPresent([String].self, forKey: .mindIds)) ?? []
            if mind.isEmpty {
                let creativity = (try container.decodeIfPresent([String].self, forKey: .creativityIds)) ?? []
                let recovery = (try container.decodeIfPresent([String].self, forKey: .recoveryIds)) ?? []
                let rest = (try container.decodeIfPresent([String].self, forKey: .restIds)) ?? []
                mind = creativity + recovery + rest
            }

            let heart = try (container.decodeIfPresent([String].self, forKey: .heartIds)
                ?? container.decodeIfPresent([String].self, forKey: .joysIds)) ?? []

            happeningIds = body + mind + heart
        }

        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        stepsTarget = try container.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTargetHours = try container.decodeIfPresent(Double.self, forKey: .sleepTargetHours) ?? EnergyDefaults.sleepTargetHours
    }

    /// Writes only the flat key. The three category keys are read-only from
    /// here on — writing them would mean deciding which happening is "body",
    /// and that question no longer has an answer.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inkEarned, forKey: .inkEarned)
        try container.encode(inkSpent, forKey: .inkSpent)
        try container.encode(happeningIds, forKey: .happeningIds)
        try container.encode(steps, forKey: .steps)
        try container.encode(sleepHours, forKey: .sleepHours)
        try container.encode(stepsTarget, forKey: .stepsTarget)
        try container.encode(sleepTargetHours, forKey: .sleepTargetHours)
    }
}
