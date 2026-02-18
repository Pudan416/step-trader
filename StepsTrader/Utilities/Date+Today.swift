import Foundation

extension Date {
    static var startOfToday: Date {
        let (hour, minute) = DayBoundary.storedDayEnd()
        return DayBoundary.currentDayStart(for: Date(), dayEndHour: hour, dayEndMinute: minute)
    }

    var isToday: Bool {
        let (hour, minute) = DayBoundary.storedDayEnd()
        let selfKey = DayBoundary.dayKey(for: self, dayEndHour: hour, dayEndMinute: minute)
        let todayKey = DayBoundary.dayKey(for: Date(), dayEndHour: hour, dayEndMinute: minute)
        return selfKey == todayKey
    }
}
