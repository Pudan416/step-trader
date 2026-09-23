import Foundation

/// An evening is a local calendar window, independent of the custom canvas
/// reset hour. A 04:00 reset must never turn 01:00 into an evening reminder.
enum EveningReflection {
    static let hour = 20
    static let notificationPrefix = "eveningReflection-"

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func isEligible(at date: Date, isCanvasEmpty: Bool, dismissedDay: String,
                           calendar: Calendar = .current) -> Bool {
        isCanvasEmpty && calendar.component(.hour, from: date) >= hour
            && dismissedDay != dayKey(for: date, calendar: calendar)
    }

    /// A rolling, bounded set of one-shot requests can be cancelled for just
    /// today's canvas without disabling future evenings. Refreshed on launch,
    /// foreground, canvas edits and preference changes.
    static func reminderDates(after now: Date, enabled: Bool, dismissedDay: String,
                              calendar: Calendar = .current,
                              isCanvasEmpty: (Date) -> Bool) -> [Date] {
        guard enabled else { return [] }
        return (0..<14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now,
                  isEligible(at: fire, isCanvasEmpty: isCanvasEmpty(fire),
                             dismissedDay: dismissedDay, calendar: calendar) else { return nil }
            return fire
        }
    }

    static func questionIndex(for date: Date, calendar: Calendar = .current) -> Int {
        (calendar.ordinality(of: .day, in: .era, for: date) ?? 0) % 3
    }
}
