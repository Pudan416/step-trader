import Foundation

struct PastDaySnapshot: Codable, Equatable {
    var inkEarned: Int
    var inkSpent: Int
    var bodyIds: [String]
    var mindIds: [String]
    var heartIds: [String]
    var steps: Int
    var sleepHours: Double
    var stepsTarget: Double
    var sleepTargetHours: Double
    /// Ephemeral one-time moments logged for this day.
    /// Their IDs also appear in bodyIds/mindIds/heartIds for energy accounting.
    /// Labels are local-only — not synced to Supabase yet.
    var moments: [EphemeralMoment]

    enum CodingKeys: String, CodingKey {
        case inkEarned
        case inkSpent
        case experienceEarned
        case experienceSpent
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
        bodyIds: [String],
        mindIds: [String],
        heartIds: [String],
        steps: Int = 0,
        sleepHours: Double = 0,
        stepsTarget: Double = EnergyDefaults.stepsTarget,
        sleepTargetHours: Double = EnergyDefaults.sleepTargetHours,
        moments: [EphemeralMoment] = []
    ) {
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.bodyIds = bodyIds
        self.mindIds = mindIds
        self.heartIds = heartIds
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
        self.moments = moments
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
        if let v = try container.decodeIfPresent([String].self, forKey: .bodyIds) {
            bodyIds = v
        } else {
            bodyIds = (try container.decodeIfPresent([String].self, forKey: .activityIds)) ?? []
        }
        if let v = try container.decodeIfPresent([String].self, forKey: .mindIds) {
            mindIds = v
        } else {
            let creativity = (try container.decodeIfPresent([String].self, forKey: .creativityIds)) ?? []
            let recovery = (try container.decodeIfPresent([String].self, forKey: .recoveryIds)) ?? []
            let rest = (try container.decodeIfPresent([String].self, forKey: .restIds)) ?? []
            var merged = creativity + recovery
            if !rest.isEmpty {
                let miscategorized = rest.filter { id in
                    if let opt = EnergyDefaults.options.first(where: { $0.id == id }) {
                        return opt.category != .mind
                    }
                    return id.hasPrefix("body_") || id.hasPrefix("heart_")
                }
                if !miscategorized.isEmpty {
                    AppLogger.app.debug("⚠️ Legacy restIds includes non-mind options: \(miscategorized.joined(separator: ", "))")
                }
                merged.append(contentsOf: rest)
            }
            mindIds = merged
        }
        if let v = try container.decodeIfPresent([String].self, forKey: .heartIds) {
            heartIds = v
        } else {
            heartIds = (try container.decodeIfPresent([String].self, forKey: .joysIds)) ?? []
        }
        steps = try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        stepsTarget = try container.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTargetHours = try container.decodeIfPresent(Double.self, forKey: .sleepTargetHours) ?? EnergyDefaults.sleepTargetHours
        moments = try container.decodeIfPresent([EphemeralMoment].self, forKey: .moments) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inkEarned, forKey: .inkEarned)
        try container.encode(inkSpent, forKey: .inkSpent)
        try container.encode(bodyIds, forKey: .bodyIds)
        try container.encode(mindIds, forKey: .mindIds)
        try container.encode(heartIds, forKey: .heartIds)
        try container.encode(steps, forKey: .steps)
        try container.encode(sleepHours, forKey: .sleepHours)
        try container.encode(stepsTarget, forKey: .stepsTarget)
        try container.encode(sleepTargetHours, forKey: .sleepTargetHours)
        try container.encode(moments, forKey: .moments)
    }
}

struct DayCanvasSlot: Codable, Equatable {
    var category: EnergyCategory?
    var optionId: String?
}
