import Foundation

extension Date {
    static var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
}
