import Foundation
import SwiftUI

enum SettingsAccountPresentation: Equatable {
    case signedOut
    case signedIn(displayName: String, initials: String, avatarData: Data?)

    static func initials(for displayName: String) -> String {
        let words = displayName.split(whereSeparator: \Character.isWhitespace)
        guard !words.isEmpty else { return "U" }
        if words.count == 1 {
            return String(words[0].prefix(2)).uppercased()
        }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

struct SettingsYourDaySummary: Equatable {
    let stepsTarget: Int
    let sleepTargetHours: Double
    let dayStartMinutes: Int

    init(stepsTarget: Double, sleepTargetHours: Double, dayEndHour: Int, dayEndMinute: Int) {
        self.stepsTarget = max(0, Int(stepsTarget.rounded()))
        self.sleepTargetHours = max(0, sleepTargetHours)
        self.dayStartMinutes = min(max(dayEndHour, 0), 23) * 60
            + min(max(dayEndMinute, 0), 59)
    }

    func stepsText(locale: Locale = .current) -> String {
        stepsTarget.formatted(.number.locale(locale))
    }

    func sleepText(locale: Locale = .current) -> String {
        let hours = sleepTargetHours.formatted(
            .number.locale(locale).precision(.fractionLength(0...1))
        )
        return String(localized: "\(hours) h", comment: "Settings Your day – sleep target summary")
    }

    func dayStartText(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1,
                                 hour: dayStartMinutes / 60,
                                 minute: dayStartMinutes % 60)
        )!
        return date.formatted(
            Date.FormatStyle(
                date: .omitted,
                time: .shortened,
                locale: locale,
                timeZone: timeZone
            )
        )
    }
}

enum SettingsGridLayout {
    static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }
}

enum SettingsYourDayLayout {
    static func stacksMetrics(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

enum SettingsLocalizedCasing {
    static func uppercase(_ value: String, locale: Locale = .current) -> String {
        value.uppercased(with: locale)
    }
}
