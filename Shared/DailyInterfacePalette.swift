import Foundation
import SwiftUI

/// A small color handoff; extensions never need to render or load a personal canvas.
struct DailyInterfacePalette: Codable, Equatable {
    struct RGB: Codable, Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
        var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    }

    let dayKey: String
    let accent: RGB
    let ink: RGB

    static let storageKey = "dailyInterfacePalette.v1"
    static let fallback = Self(
        dayKey: "",
        accent: RGB(red: 220 / 255, green: 229 / 255, blue: 220 / 255),
        ink: RGB(red: 43 / 255, green: 48 / 255, blue: 48 / 255)
    )

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let palette = try? JSONDecoder().decode(Self.self, from: data),
              palette.accent.isValid, palette.ink.isValid else { return .fallback }
        return palette
    }

    /// Returns true only when extensions need a new timeline.
    @discardableResult
    func save(to defaults: UserDefaults) -> Bool {
        guard accent.isValid, ink.isValid,
              Self.load(from: defaults) != self,
              let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}
