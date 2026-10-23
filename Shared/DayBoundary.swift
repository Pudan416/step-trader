import Foundation

/// Pure date-math helpers shared across all targets (main app, DeviceActivityMonitor,
/// UnlockWidgetExtension). No dependency on CachedFormatters or UserDefaults.
enum DayBoundary {
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

    /// True when `anchor` (e.g. persisted `dailyEnergyAnchor`) is for a different custom day than `date`.
    /// Main app resets energy when it launches; the widget can run first, so defaults/snapshot can lag.
    static func isPersistedDayBehind(
        anchor: Date?,
        relativeTo date: Date,
        dayEndHour: Int,
        dayEndMinute: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard let anchor else { return false }
        let anchorStart = currentDayStart(for: anchor, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute, calendar: calendar)
        let dateStart = currentDayStart(for: date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute, calendar: calendar)
        return anchorStart != dateStart
    }
}
