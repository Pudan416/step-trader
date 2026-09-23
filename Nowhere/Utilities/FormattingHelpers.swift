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
        return k.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(k))K" : "\(k.formatted(.number.precision(.fractionLength(1))))K"
    }
    return "\(value)"
}
