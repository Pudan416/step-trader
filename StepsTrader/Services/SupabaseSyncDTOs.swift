import Foundation

func loadAnalyticsQueueFromDefaults() -> [AnalyticsEventPayload] {
    let g = UserDefaults.stepsTrader()
    guard let data = g.data(forKey: SharedKeys.analyticsEventsQueue),
          let decoded = try? JSONDecoder().decode([AnalyticsEventPayload].self, from: data) else {
        return []
    }
    return decoded
}

// MARK: - Sync Error

enum SyncError: Error {
    case misconfigured
    case networkError
}

// MARK: - DTOs for Supabase

struct CustomActivityRow: Codable {
    let id: String
    let userId: String
    let titleEn: String
    let titleRu: String?
    let category: String
    let icon: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case titleEn = "title_en"
        case titleRu = "title_ru"
        case category
        case icon
    }
}

struct DailySelectionsRow: Codable {
    let userId: String
    let dayKey: String
    let activityIds: [String]
    let restIds: [String]
    let joysIds: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case activityIds = "activity_ids"
        case restIds = "recovery_ids"
        case joysIds = "joys_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        activityIds = try container.decodeIfPresent([String].self, forKey: .activityIds) ?? []
        restIds = try container.decodeIfPresent([String].self, forKey: .restIds) ?? []
        joysIds = try container.decodeIfPresent([String].self, forKey: .joysIds) ?? []
    }

    init(userId: String, dayKey: String, activityIds: [String], restIds: [String], joysIds: [String]) {
        self.userId = userId
        self.dayKey = dayKey
        self.activityIds = activityIds
        self.restIds = restIds
        self.joysIds = joysIds
    }
}

struct DailyStatsRow: Codable {
    let userId: String
    let dayKey: String
    let stepsCount: Int
    let sleepHours: Double
    let baseEnergy: Int
    let bonusEnergy: Int
    let remainingBalance: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case stepsCount = "steps_count"
        case sleepHours = "sleep_hours"
        case baseEnergy = "base_energy"
        case bonusEnergy = "bonus_energy"
        case remainingBalance = "remaining_balance"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        stepsCount = try container.decodeIfPresent(Int.self, forKey: .stepsCount) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        baseEnergy = try container.decodeIfPresent(Int.self, forKey: .baseEnergy) ?? 0
        bonusEnergy = try container.decodeIfPresent(Int.self, forKey: .bonusEnergy) ?? 0
        remainingBalance = try container.decodeIfPresent(Int.self, forKey: .remainingBalance) ?? 0
    }
    
    init(userId: String, dayKey: String, stepsCount: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int) {
        self.userId = userId
        self.dayKey = dayKey
        self.stepsCount = stepsCount
        self.sleepHours = sleepHours
        self.baseEnergy = baseEnergy
        self.bonusEnergy = bonusEnergy
        self.remainingBalance = remainingBalance
    }
}

struct DailySpentRow: Codable {
    let userId: String
    let dayKey: String
    let totalSpent: Int
    let spentByApp: [String: Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case totalSpent = "total_spent"
        case spentByApp = "spent_by_app"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        totalSpent = try container.decodeIfPresent(Int.self, forKey: .totalSpent) ?? 0
        spentByApp = try container.decodeIfPresent([String: Int].self, forKey: .spentByApp) ?? [:]
    }
    
    init(userId: String, dayKey: String, totalSpent: Int, spentByApp: [String: Int]) {
        self.userId = userId
        self.dayKey = dayKey
        self.totalSpent = totalSpent
        self.spentByApp = spentByApp
    }
}

struct AnalyticsEventPayload: Codable, Equatable {
    let id: String
    let eventName: String
    let dayKey: String
    let properties: [String: String]
    let occurredAt: Date
}

struct AnalyticsEventInsertRow: Codable {
    let userId: String
    let eventName: String
    let dayKey: String
    let properties: [String: String]
    let eventId: String
    let occurredAt: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case eventName = "event_name"
        case dayKey = "day_key"
        case properties
        case eventId = "event_id"
        case occurredAt = "occurred_at"
    }
}

struct TicketGroupSyncRow: Equatable {
    let bundleId: String
    let mode: String
    let name: String
    let templateApp: String?
    let stickerThemeIndex: Int
    let enabledIntervals: [String]
    let settingsJson: Data

    static func from(group: TicketGroup) -> TicketGroupSyncRow {
        let mode = "ticket"
        let settingsData = (try? JSONEncoder().encode(group.settings)) ?? Data("{}".utf8)
        return TicketGroupSyncRow(
            bundleId: "group:\(group.id)",
            mode: mode,
            name: group.name,
            templateApp: group.templateApp,
            stickerThemeIndex: group.stickerThemeIndex,
            enabledIntervals: group.enabledIntervals.map(\.rawValue).sorted(),
            settingsJson: settingsData
        )
    }
}

struct TicketGroupSyncInsertRow: Codable {
    let userId: String
    let bundleId: String
    let mode: String
    let name: String?
    let templateApp: String?
    let stickerThemeIndex: Int
    let enabledIntervals: [String]
    let settingsJson: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case bundleId = "bundle_id"
        case mode
        case name
        case templateApp = "template_app"
        case stickerThemeIndex = "sticker_theme_index"
        case enabledIntervals = "enabled_intervals"
        case settingsJson = "settings_json"
    }
}

/// Lightweight wrapper for encoding arbitrary JSON values in Codable structs.
enum AnyCodableValue: Codable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)
    case array([String])
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool must be checked before Int — NSJSONSerialization stores bools as NSNumber,
        // so decode(Int.self) succeeds on true/false and silently returns 1/0.
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode([String].self) { self = .array(v) }
        else { self = .string(try container.decode(String.self)) }
    }
}

struct DaySnapshotRow: Codable {
    let userId: String
    let dayKey: String
    let inkEarned: Int
    let inkSpent: Int
    let bodyIds: [String]
    let mindIds: [String]
    let heartIds: [String]
    let steps: Int
    let sleepHours: Double
    let stepsTarget: Double
    let sleepTargetHours: Double
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case inkEarned = "experience_earned"
        case inkSpent = "experience_spent"
        case bodyIds = "body_ids"
        case mindIds = "mind_ids"
        case heartIds = "heart_ids"
        case steps
        case sleepHours = "sleep_hours"
        case stepsTarget = "steps_target"
        case sleepTargetHours = "sleep_target_hours"
    }
    
    init(userId: String, dayKey: String, inkEarned: Int, inkSpent: Int,
         bodyIds: [String], mindIds: [String], heartIds: [String],
         steps: Int, sleepHours: Double, stepsTarget: Double, sleepTargetHours: Double) {
        self.userId = userId
        self.dayKey = dayKey
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.bodyIds = bodyIds
        self.mindIds = mindIds
        self.heartIds = heartIds
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        inkEarned = try c.decodeIfPresent(Int.self, forKey: .inkEarned) ?? 0
        inkSpent = try c.decodeIfPresent(Int.self, forKey: .inkSpent) ?? 0
        bodyIds = try c.decodeIfPresent([String].self, forKey: .bodyIds) ?? []
        mindIds = try c.decodeIfPresent([String].self, forKey: .mindIds) ?? []
        heartIds = try c.decodeIfPresent([String].self, forKey: .heartIds) ?? []
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try c.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        stepsTarget = try c.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTargetHours = try c.decodeIfPresent(Double.self, forKey: .sleepTargetHours) ?? EnergyDefaults.sleepTargetHours
    }
}

struct UserPreferencesRow: Decodable {
    let userId: String
    let stepsTarget: Double
    let sleepTarget: Double
    let dayEndHour: Int
    let dayEndMinute: Int
    let restDayOverride: Bool
    let preferredBody: [String]
    let preferredMind: [String]
    let preferredHeart: [String]
    let canvasSlots: AnyCodable?
    let hasWallpaperShortcut: Bool
    let wallpaperShortcutUses: Int
    let notifyOneMinBefore: Bool
    let notifyWhenTimerOver: Bool
    let notifyCanvasReminder: Bool
    let canvasReminderHour: Int
    let canvasReminderMinute: Int
    let notifyDayResetWarning: Bool
    let dayResetWarningHours: Int
    let hasMediumWidget: Bool
    let hasLargeWidget: Bool
    let lastOpenedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case stepsTarget = "steps_target"
        case sleepTarget = "sleep_target"
        case dayEndHour = "day_end_hour"
        case dayEndMinute = "day_end_minute"
        case restDayOverride = "rest_day_override"
        case preferredBody = "preferred_body"
        case preferredMind = "preferred_mind"
        case preferredHeart = "preferred_heart"
        case canvasSlots = "gallery_slots"
        case hasWallpaperShortcut = "has_wallpaper_shortcut"
        case wallpaperShortcutUses = "wallpaper_shortcut_uses"
        case notifyOneMinBefore = "notify_one_min_before"
        case notifyWhenTimerOver = "notify_when_timer_over"
        case notifyCanvasReminder = "notify_canvas_reminder"
        case canvasReminderHour = "canvas_reminder_hour"
        case canvasReminderMinute = "canvas_reminder_minute"
        case notifyDayResetWarning = "notify_day_reset_warning"
        case dayResetWarningHours = "day_reset_warning_hours"
        case hasMediumWidget = "has_medium_widget"
        case hasLargeWidget = "has_large_widget"
        case lastOpenedAt = "last_opened_at"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        stepsTarget = try c.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTarget = try c.decodeIfPresent(Double.self, forKey: .sleepTarget) ?? EnergyDefaults.sleepTargetHours
        dayEndHour = try c.decodeIfPresent(Int.self, forKey: .dayEndHour) ?? 0
        dayEndMinute = try c.decodeIfPresent(Int.self, forKey: .dayEndMinute) ?? 0
        restDayOverride = try c.decodeIfPresent(Bool.self, forKey: .restDayOverride) ?? false
        preferredBody = try c.decodeIfPresent([String].self, forKey: .preferredBody) ?? []
        preferredMind = try c.decodeIfPresent([String].self, forKey: .preferredMind) ?? []
        preferredHeart = try c.decodeIfPresent([String].self, forKey: .preferredHeart) ?? []
        canvasSlots = try c.decodeIfPresent(AnyCodable.self, forKey: .canvasSlots)
        hasWallpaperShortcut = try c.decodeIfPresent(Bool.self, forKey: .hasWallpaperShortcut) ?? false
        wallpaperShortcutUses = try c.decodeIfPresent(Int.self, forKey: .wallpaperShortcutUses) ?? 0
        notifyOneMinBefore = try c.decodeIfPresent(Bool.self, forKey: .notifyOneMinBefore) ?? true
        notifyWhenTimerOver = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenTimerOver) ?? true
        notifyCanvasReminder = try c.decodeIfPresent(Bool.self, forKey: .notifyCanvasReminder) ?? true
        canvasReminderHour = try c.decodeIfPresent(Int.self, forKey: .canvasReminderHour) ?? 21
        canvasReminderMinute = try c.decodeIfPresent(Int.self, forKey: .canvasReminderMinute) ?? 0
        notifyDayResetWarning = try c.decodeIfPresent(Bool.self, forKey: .notifyDayResetWarning) ?? true
        dayResetWarningHours = try c.decodeIfPresent(Int.self, forKey: .dayResetWarningHours) ?? 1
        hasMediumWidget = try c.decodeIfPresent(Bool.self, forKey: .hasMediumWidget) ?? false
        hasLargeWidget = try c.decodeIfPresent(Bool.self, forKey: .hasLargeWidget) ?? false
        lastOpenedAt = try c.decodeIfPresent(String.self, forKey: .lastOpenedAt)
    }
}

/// Row returned when reading canvas from Supabase. canvas_json is raw JSON (Any).
struct DayCanvasReadRow: Decodable {
    let canvasJson: Any
    
    enum CodingKeys: String, CodingKey {
        case canvasJson = "canvas_json"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawJSON = try container.decode(AnyCodable.self, forKey: .canvasJson)
        canvasJson = rawJSON.value
    }
}

/// Wrapper to decode arbitrary JSON from Supabase JSONB columns.
struct AnyCodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}
