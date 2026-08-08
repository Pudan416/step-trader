import Foundation

/// Single routing authority for the scalar user-preference keys that
/// `restoreFromServer` used to write by hand across three UserDefaults domains
/// — `.standard`, the shared app-group suite (`UserDefaults.stepsTrader()`),
/// and a hand-mirrored copy of the two theme keys the widgets read (§M3).
///
/// Before this, adding a preference meant remembering its domain in every
/// place that touched it, and the restore block was ~25 unlabelled `set(_:)`
/// calls where a single wrong suite silently broke a restored setting. Routing
/// now lives in exactly one place, and `PreferencesStoreTests` asserts every
/// key lands in the suite it's read back from, so a mis-route fails CI instead
/// of shipping.
///
/// Scope is deliberately the *pure UserDefaults-backed scalars*. Preferences
/// that are also `@Published` model state (day boundary, preferred options,
/// canvas slots) stay with their caller because applying them needs the
/// MainActor `AppModel`; the widget-presence flags are push-only and never
/// restored, so they're not here either.
enum PreferencesStore {

    /// The scalar preferences restored from the server, decoupled from their
    /// storage domains.
    struct Scalars: Equatable {
        var stepsTarget: Double
        var sleepTarget: Double
        var restDayOverride: Bool
        var hasWallpaperShortcut: Bool
        var wallpaperShortcutUses: Int
        var notifyOneMinBefore: Bool
        var notifyWhenTimerOver: Bool
        var notifyCanvasReminder: Bool
        var canvasReminderHour: Int
        var canvasReminderMinute: Int
        var notifyDayResetWarning: Bool
        var dayResetWarningHours: Int
        var canvasOverlayStyle: String
        var gradientStyle: String
        var gradientPalette: String
        var userGradientStyle: String
        var userGradientPalette: String
        var dailyRandomThemeEnabled: Bool
        /// Legacy per-category shapes. Still restored during rollout because
        /// older builds sharing this App Group read them, and because they are
        /// what seeds `allowedCanvasShapes` on a device that has never had it.
        var bodyCanvasShape: String
        var mindCanvasShape: String
        var heartCanvasShape: String
        /// The shape set that replaces the three above. Empty means the device
        /// has no server-side value yet; seeding from the legacy keys handles it.
        var allowedCanvasShapes: [String] = []
    }

    // Keys stored as bare string literals elsewhere in the codebase (not yet in
    // SharedKeys). Kept in one place so the routing table is self-contained.
    static let hasWallpaperShortcutKey = "hasWallpaperShortcut"
    static let wallpaperShortcutUsesKey = "wallpaperShortcutUses"

    /// Apply restored scalar preferences to their backing domains.
    ///
    /// `group` is the app-group suite (extensions + app share it); `standard`
    /// holds the appearance keys the main app reads; `appGroupMirror` receives a
    /// copy of the two active-theme keys so the widget/shield extensions render
    /// the same gradient. The three parameters are injectable so the routing is
    /// unit-testable against isolated suites.
    static func applyScalars(
        _ s: Scalars,
        group: UserDefaults = .stepsTrader(),
        standard: UserDefaults = .standard,
        appGroupMirror: UserDefaults? = UserDefaults(suiteName: SharedKeys.appGroupId)
    ) {
        // App-group suite: targets, rest-day, wallpaper shortcut, notifications, overlay.
        group.set(s.stepsTarget, forKey: SharedKeys.userStepsTarget)
        group.set(s.sleepTarget, forKey: SharedKeys.userSleepTarget)
        group.set(s.restDayOverride, forKey: SharedKeys.restDayOverrideEnabled)
        group.set(s.hasWallpaperShortcut, forKey: hasWallpaperShortcutKey)
        group.set(s.wallpaperShortcutUses, forKey: wallpaperShortcutUsesKey)
        group.set(s.notifyOneMinBefore, forKey: SharedKeys.notifyOneMinBefore)
        group.set(s.notifyWhenTimerOver, forKey: SharedKeys.notifyWhenTimerOver)
        group.set(s.notifyCanvasReminder, forKey: SharedKeys.notifyCanvasReminder)
        group.set(s.canvasReminderHour, forKey: SharedKeys.canvasReminderHour)
        group.set(s.canvasReminderMinute, forKey: SharedKeys.canvasReminderMinute)
        group.set(s.notifyDayResetWarning, forKey: SharedKeys.notifyDayResetWarning)
        group.set(s.dayResetWarningHours, forKey: SharedKeys.dayResetWarningHours)
        group.set(s.canvasOverlayStyle, forKey: SharedKeys.canvasOverlayStyle)

        // Standard suite: appearance (gradient style/palette + canvas shapes).
        standard.set(s.gradientStyle, forKey: SharedKeys.gradientStyle)
        standard.set(s.gradientPalette, forKey: SharedKeys.gradientPalette)
        standard.set(s.userGradientStyle, forKey: SharedKeys.userGradientStyle)
        standard.set(s.userGradientPalette, forKey: SharedKeys.userGradientPalette)
        standard.set(s.dailyRandomThemeEnabled, forKey: SharedKeys.dailyRandomThemeEnabled)
        standard.set(s.bodyCanvasShape, forKey: SharedKeys.bodyCanvasShape)
        standard.set(s.mindCanvasShape, forKey: SharedKeys.mindCanvasShape)
        standard.set(s.heartCanvasShape, forKey: SharedKeys.heartCanvasShape)
        // Only write when the server actually had a value. Writing an empty
        // array would look like a deliberate empty set and defeat the seeding
        // path in `CanvasShapeType.allowedByUser`.
        if !s.allowedCanvasShapes.isEmpty {
            standard.set(s.allowedCanvasShapes, forKey: SharedKeys.allowedCanvasShapes)
        }

        // Mirror the active theme into the app group so widgets/extensions match.
        appGroupMirror?.set(s.gradientStyle, forKey: SharedKeys.gradientStyle)
        appGroupMirror?.set(s.gradientPalette, forKey: SharedKeys.gradientPalette)
    }
}
