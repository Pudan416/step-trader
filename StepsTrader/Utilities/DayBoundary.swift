import Foundation

struct DayBoundary {
    /// Single source of truth for reading stored day-end hour/minute from UserDefaults.
    /// Checks app group first, then standard defaults, then falls back to midnight (0, 0).
    static func storedDayEnd() -> (hour: Int, minute: Int) {
        let g = UserDefaults.stepsTrader()
        let s = UserDefaults.standard
        let hour = (g.object(forKey: "dayEndHour_v1") as? Int)
            ?? (s.object(forKey: "dayEndHour_v1") as? Int)
            ?? 0
        let minute = (g.object(forKey: "dayEndMinute_v1") as? Int)
            ?? (s.object(forKey: "dayEndMinute_v1") as? Int)
            ?? 0
        return (hour, minute)
    }

    static func currentDayStart(
        for date: Date,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let clampedHour = max(0, min(23, dayEndHour))
        let clampedMinute = max(0, min(59, dayEndMinute))
        if clampedHour == 0 && clampedMinute == 0 {
            return calendar.startOfDay(for: date)
        }

        var comps = DateComponents()
        comps.hour = clampedHour
        comps.minute = clampedMinute
        let cutoffToday = calendar.nextDate(
            after: calendar.startOfDay(for: date),
            matching: comps,
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
        guard let cutoffToday else {
            return calendar.startOfDay(for: date)
        }
        if date >= cutoffToday {
            return cutoffToday
        } else if let prev = calendar.date(byAdding: .day, value: -1, to: cutoffToday) {
            return prev
        } else {
            return calendar.startOfDay(for: date)
        }
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

    static func nextBoundary(
        after date: Date,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> Date {
        let clampedHour = max(0, min(23, dayEndHour))
        let clampedMinute = max(0, min(59, dayEndMinute))
        let todayCutoff = calendar.date(
            bySettingHour: clampedHour,
            minute: clampedMinute,
            second: 0,
            of: date
        ) ?? calendar.startOfDay(for: date)
        if date < todayCutoff { return todayCutoff }
        return calendar.date(byAdding: .day, value: 1, to: todayCutoff) ?? todayCutoff
    }
}
