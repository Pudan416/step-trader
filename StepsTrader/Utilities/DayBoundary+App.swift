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

    /// Display-only helper: returns a `Date` representing the end of the
    /// calendar day named by `dayKey` (e.g. "2026-05-26" → 23:59:59 on that
    /// calendar date). Used as a fallback `lastModified` timestamp for the
    /// canvas viewer when a past day's canvas wasn't explicitly stamped.
    ///
    /// Not the same as "next custom-day boundary" — this is purely for
    /// display sorting / formatting. For real day-boundary arithmetic use
    /// `nextBoundary(after:dayEndHour:dayEndMinute:)`.
    static func endOfCalendarDay(forDayKey dayKey: String) -> Date {
        let date = CachedFormatters.dayKey.date(from: dayKey) ?? .now
        return Calendar.current.date(
            bySettingHour: 23, minute: 59, second: 59, of: date
        ) ?? date
    }
}
