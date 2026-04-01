import Foundation

extension DayBoundary {
    /// Single source of truth for reading stored day-end hour/minute from UserDefaults.
    /// Checks app group first, then standard defaults, then falls back to midnight (0, 0).
    static func storedDayEnd() -> (hour: Int, minute: Int) {
        let g = UserDefaults.stepsTrader()
        let s = UserDefaults.standard
        let hour = (g.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? (s.object(forKey: SharedKeys.dayEndHour) as? Int)
            ?? 0
        let minute = (g.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? (s.object(forKey: SharedKeys.dayEndMinute) as? Int)
            ?? 0
        return (hour, minute)
    }

    static func dayKey(
        for date: Date,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> String {
        let dayStart = currentDayStart(
            for: date,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute,
            calendar: calendar
        )
        return CachedFormatters.dayKey.string(from: dayStart)
    }
}
