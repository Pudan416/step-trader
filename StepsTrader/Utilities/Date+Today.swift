import Foundation

extension Date {
    static var startOfToday: Date { AppModel.currentDayStartForDefaults(Date()) }
    var isToday: Bool { AppModel.dayKey(for: self) == AppModel.dayKey(for: Date()) }
}
