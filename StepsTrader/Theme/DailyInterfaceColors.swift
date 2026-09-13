import Observation
import SwiftUI
import WidgetKit

/// Observation tracks reads even through AppColors/AppTheme computed properties.
/// Existing screens therefore update in place on Remix, palette edits and day rollover.
@Observable
final class DailyInterfaceColors {
    static let shared = DailyInterfaceColors()
    private(set) var palette: DailyInterfacePalette
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
        self.palette = DailyInterfacePalette.load(from: defaults)
    }

    @MainActor
    func update(_ chrome: CanvasChromePalette, dayKey: String, reloadWidgets: () -> Void = {
        WidgetCenter.shared.reloadAllTimelines()
    }) {
        func rgb(_ value: DayObjectRGB) -> DailyInterfacePalette.RGB {
            .init(red: Double(value.sRGB.x), green: Double(value.sRGB.y), blue: Double(value.sRGB.z))
        }
        let next = DailyInterfacePalette(dayKey: dayKey, accent: rgb(chrome.accent), ink: rgb(chrome.onAccent))
        if palette != next { palette = next }
        if next.save(to: defaults) { reloadWidgets() }
    }
}
