import Foundation
import SwiftUI

enum SettingsAccountPresentation: Equatable {
    case signedOut
    case signedIn(displayName: String, initials: String, avatarData: Data?)

    static func initials(for displayName: String) -> String {
        initials(for: displayName, locale: .current)
    }

    static func initials(for displayName: String, locale: Locale) -> String {
        let words = displayName.split(whereSeparator: \Character.isWhitespace)
        guard !words.isEmpty else { return "U" }
        if words.count == 1 {
            return SettingsLocalizedCasing.uppercase(
                String(words[0].prefix(2)),
                locale: locale
            )
        }
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined()
        return SettingsLocalizedCasing.uppercase(initials, locale: locale)
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
    static let minimumCardWidth: CGFloat = 164
    static let spacing: CGFloat = 12

    static func columnCount(
        for dynamicTypeSize: DynamicTypeSize,
        availableWidth: CGFloat
    ) -> Int {
        guard !dynamicTypeSize.isAccessibilitySize else { return 1 }
        let twoColumnWidth = minimumCardWidth * 2 + spacing
        return availableWidth >= twoColumnWidth ? 2 : 1
    }

    static func cardWidth(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        let count = max(columnCount, 1)
        let totalSpacing = spacing * CGFloat(count - 1)
        return max(0, (availableWidth - totalSpacing) / CGFloat(count))
    }
}

enum SettingsCardAppearance {
    /// A dark matte wash keeps card content independent of the animated palette.
    static let surfaceOpacity = 0.70
    static let captionOpacity = 0.78
    static let outlineOpacity = 0.55
}

struct SettingsSRGBColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    fileprivate func composited(
        over background: SettingsSRGBColor,
        opacity: Double
    ) -> SettingsSRGBColor {
        let alpha = min(max(opacity, 0), 1)
        return SettingsSRGBColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha)
        )
    }

    fileprivate var relativeLuminance: Double {
        func linearize(_ component: Double) -> Double {
            let clamped = min(max(component, 0), 1)
            return clamped <= 0.04045
                ? clamped / 12.92
                : pow((clamped + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }
}

enum SettingsCardContrast {
    struct Measurement: Equatable {
        let captionToSurface: Double
        let outlineToSurface: Double
        let surfaceToBackground: Double
    }

    /// Mirrors the concrete SwiftUI tokens used by `SettingsCardSurface` and
    /// the small Your day captions. Measuring against white is deliberately
    /// stricter than any single palette swatch and covers additive brightening.
    static func measure(over background: SettingsSRGBColor) -> Measurement {
        let black = SettingsSRGBColor(red: 0, green: 0, blue: 0)
        let primaryText = SettingsSRGBColor(red: 0.95, green: 0.95, blue: 0.95)
        let surface = black.composited(
            over: background,
            opacity: SettingsCardAppearance.surfaceOpacity
        )
        let caption = primaryText.composited(
            over: surface,
            opacity: SettingsCardAppearance.captionOpacity
        )
        let outline = primaryText.composited(
            over: surface,
            opacity: SettingsCardAppearance.outlineOpacity
        )

        return Measurement(
            captionToSurface: contrastRatio(caption, surface),
            outlineToSurface: contrastRatio(outline, surface),
            surfaceToBackground: contrastRatio(surface, background)
        )
    }

    private static func contrastRatio(
        _ first: SettingsSRGBColor,
        _ second: SettingsSRGBColor
    ) -> Double {
        let lighter = max(first.relativeLuminance, second.relativeLuminance)
        let darker = min(first.relativeLuminance, second.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
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
