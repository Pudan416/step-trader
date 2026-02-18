import SwiftUI

// MARK: - Number Formatting

/// Grouped decimal formatting (e.g. 1,234,567). Uses cached NumberFormatter.
func formatGroupedNumber(_ value: Int) -> String {
    CachedFormatters.decimalGrouped.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// Compact number formatting with K-suffix (e.g. 1.5K, 250).
func formatCompactNumber(_ value: Int) -> String {
    if value >= 1000 {
        let k = Double(value) / 1000.0
        return k.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(k))K" : String(format: "%.1fK", k)
    }
    return "\(value)"
}

// MARK: - Time Formatting

/// Formats remaining time from seconds as a human-readable countdown.
/// - `>= 3600`: "1h 05m"
/// - `>= 60`:   "5m 03s"
/// - `< 60`:    "45s"
func formatRemainingTime(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%dh %02dm", h, m)
    } else if m > 0 {
        return String(format: "%dm %02ds", m, s)
    }
    return String(format: "%ds", s)
}

/// Short m:ss countdown (no hours component). For ticket timer overlays.
func formatMinuteTimer(_ seconds: TimeInterval) -> String {
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - EnergyCategory Helpers

extension EnergyCategory {
    /// The canonical accent color for this category.
    var color: Color {
        switch self {
        case .body:  return .green
        case .mind:  return .purple
        case .heart: return .orange
        }
    }

    /// The default hex color for new options in this category.
    var defaultColorHex: String {
        switch self {
        case .body:  return "#C3143B"
        case .mind:  return "#7652AF"
        case .heart: return "#FEAAC2"
        }
    }
}
