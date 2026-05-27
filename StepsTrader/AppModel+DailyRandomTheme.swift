import Foundation
import SwiftUI

// MARK: - Daily Random Theme (Pro-only)
//
// Pro users can enable a "Daily Random Theme" mode where the app rolls a fresh
// `(GradientPalette, GradientStyle)` pair every calendar day. The chosen pair is:
//
//   1. Written into the **active** UserDefaults keys (`SharedKeys.gradientStyle`
//      and `.gradientPalette`) so `EnergyGradientBackground` — used app-wide —
//      picks it up automatically without any view-level wiring changes.
//   2. Mirrored to the App Group container so the wallpaper Shortcut intent
//      and widget render with the same palette as the live app.
//   3. Persisted onto today's `DayCanvas` via `GalleryView.saveCanvasLocally`,
//      so when the user opens the day later in `HistoryView` →
//      `DayCanvasViewerView`, that day reproduces with its own unique theme.
//
// The user's manual preference (chips in `SettingsAppearancePage`) is preserved
// in a separate pair of keys (`SharedKeys.userGradientStyle` / `.userGradientPalette`)
// so we can restore it cleanly when the toggle goes OFF.
//
// **Re-roll guard**: `applyDailyRandomThemeIfNeeded` is idempotent within a single
// **custom** day — it only rolls if `dailyRandomThemeLastRolledKey != todayDayKey`.
// `todayDayKey` is computed via `AppModel.dayKey(for:)` which respects the user's
// configured `dayEndHour`/`dayEndMinute` (e.g. day ends at 4am, not midnight) —
// so the gradient flips when the user's energy resets, NOT at calendar midnight.
// Manual re-roll (`rerollDailyTheme`) bypasses the guard.
extension AppModel {

    // MARK: - Public API

    /// Enable or disable daily random theme. Handles user-preference snapshot
    /// (on enable) and restore (on disable). When enabling, immediately rolls
    /// today's theme so the change is visible right away.
    @MainActor
    func setDailyRandomTheme(enabled: Bool) {
        let defaults = UserDefaults.standard
        let wasEnabled = defaults.bool(forKey: SharedKeys.dailyRandomThemeEnabled)
        guard enabled != wasEnabled else { return }

        if enabled {
            // Snapshot current active palette/style as the user preference,
            // so we can restore it later when daily-random is disabled.
            let activeStyle = defaults.string(forKey: SharedKeys.gradientStyle)
                ?? GradientStyle.radial.rawValue
            let activePalette = defaults.string(forKey: SharedKeys.gradientPalette)
                ?? GradientPalette.warmSunset.rawValue
            defaults.set(activeStyle, forKey: SharedKeys.userGradientStyle)
            defaults.set(activePalette, forKey: SharedKeys.userGradientPalette)

            defaults.set(true, forKey: SharedKeys.dailyRandomThemeEnabled)
            // Force a roll immediately by clearing the last-rolled key.
            defaults.removeObject(forKey: SharedKeys.dailyRandomThemeLastRolledKey)
            rollDailyRandomTheme()
        } else {
            defaults.set(false, forKey: SharedKeys.dailyRandomThemeEnabled)
            // Restore user preference into the active keys.
            let userStyle = defaults.string(forKey: SharedKeys.userGradientStyle)
                ?? GradientStyle.radial.rawValue
            let userPalette = defaults.string(forKey: SharedKeys.userGradientPalette)
                ?? GradientPalette.warmSunset.rawValue
            writeActiveTheme(styleRaw: userStyle, paletteRaw: userPalette)
            // Wipe last-rolled so re-enabling later starts fresh.
            defaults.removeObject(forKey: SharedKeys.dailyRandomThemeLastRolledKey)
        }
        objectWillChange.send()
    }

    /// Manual re-roll, bound to the "Re-roll today" button in
    /// `SettingsAppearancePage`. Always picks a fresh combination (no determinism)
    /// and updates today's last-rolled marker so the daily roll guard isn't
    /// triggered after a foreground.
    @MainActor
    func rerollDailyTheme() {
        rollDailyRandomTheme()
    }

    /// Idempotent within a calendar day. Call on app launch and on
    /// `scenePhase == .active`. No-ops if:
    ///   - Toggle is OFF, or
    ///   - User is no longer Pro (in which case we also gracefully turn the toggle
    ///     OFF and restore their user-preference theme), or
    ///   - We've already rolled for today's calendar day.
    @MainActor
    func applyDailyRandomThemeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SharedKeys.dailyRandomThemeEnabled) else { return }

        // Pro lapsed → graceful downgrade. Restore user preference and disable
        // the toggle so chips become tappable again.
        guard isPro else {
            setDailyRandomTheme(enabled: false)
            return
        }

        // Use the **custom-day** key (respects user's dayEndHour/Minute), not
        // a raw calendar-midnight key. Otherwise the roll fires at 00:00 while
        // the user's day is still going until e.g. 04:00, and they see the
        // gradient flip out from under them mid-evening.
        let todayKey = AppModel.dayKey(for: Date.now)
        let lastRolled = defaults.string(forKey: SharedKeys.dailyRandomThemeLastRolledKey) ?? ""
        guard lastRolled != todayKey else { return }
        rollDailyRandomTheme()
    }

    // MARK: - Internals

    /// Roll a random palette + style and write it everywhere. Avoids picking
    /// the exact same combination as last time when more than one option exists.
    @MainActor
    private func rollDailyRandomTheme() {
        let defaults = UserDefaults.standard
        let prevStyle = defaults.string(forKey: SharedKeys.gradientStyle)
        let prevPalette = defaults.string(forKey: SharedKeys.gradientPalette)

        let palettes = GradientPalette.allCases
        let styles = GradientStyle.allCases
        guard !palettes.isEmpty, !styles.isEmpty else { return }

        var newPalette = palettes.randomElement() ?? .warmSunset
        var newStyle = styles.randomElement() ?? .radial

        // Avoid trivial repeat re-rolls if the user has any choice.
        if palettes.count > 1, newPalette.rawValue == prevPalette {
            while newPalette.rawValue == prevPalette {
                newPalette = palettes.randomElement() ?? newPalette
            }
        }
        if styles.count > 1, newStyle.rawValue == prevStyle {
            while newStyle.rawValue == prevStyle {
                newStyle = styles.randomElement() ?? newStyle
            }
        }

        writeActiveTheme(styleRaw: newStyle.rawValue, paletteRaw: newPalette.rawValue)
        // Stamp with the custom-day key so the guard above can match.
        let todayKey = AppModel.dayKey(for: Date.now)
        defaults.set(todayKey, forKey: SharedKeys.dailyRandomThemeLastRolledKey)
    }

    /// Write the `(style, palette)` pair to both standard defaults and the
    /// app-group container so widgets / Shortcut intent stay in sync with
    /// the in-app `EnergyGradientBackground`.
    @MainActor
    private func writeActiveTheme(styleRaw: String, paletteRaw: String) {
        let defaults = UserDefaults.standard
        defaults.set(styleRaw, forKey: SharedKeys.gradientStyle)
        defaults.set(paletteRaw, forKey: SharedKeys.gradientPalette)

        if let group = UserDefaults(suiteName: SharedKeys.appGroupId) {
            group.set(styleRaw, forKey: SharedKeys.gradientStyle)
            group.set(paletteRaw, forKey: SharedKeys.gradientPalette)
        }
        // Nudge any observers that don't auto-update on UserDefaults writes.
        objectWillChange.send()
        syncUserPreferencesToSupabase()
    }
}
