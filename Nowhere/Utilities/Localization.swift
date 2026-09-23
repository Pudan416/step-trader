// Localization.swift — shared locale utilities.
import Foundation

/// Convert an ISO 3166-1 alpha-2 country code to its flag emoji.
func countryFlag(_ countryCode: String) -> String {
    let base: UInt32 = 127397
    var flag = ""
    for scalar in countryCode.uppercased().unicodeScalars {
        if let unicode = UnicodeScalar(base + scalar.value) {
            flag.append(String(unicode))
        }
    }
    return flag
}
