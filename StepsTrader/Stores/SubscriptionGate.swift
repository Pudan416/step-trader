import Foundation

/// Central answer to "what can a user do".
///
/// The app is free and every gate returns `true`. The functions survive their
/// own retirement on purpose, by product decision, but views no longer consult
/// most of them: only `canUseDailyRandomTheme` still has a production call site
/// (`AppModel+DailyRandomTheme.swift`). The other seven exist solely so
/// `SubscriptionGateTests` keeps compiling against a stable API shape; nothing
/// in the app reads their return value.
///
/// Reintroducing gating is therefore NOT a matter of flipping a return value
/// here — e.g. changing `canAddBlockingGroup` to `currentCount < 2` would do
/// nothing, because no view calls it. Restoring a limit means re-adding the
/// call site in the relevant view (or view model) first, then changing the
/// gate's body. The `isPro` parameters are deliberately unused.
enum SubscriptionGate {

    /// Blocking groups are unlimited.
    static func canAddBlockingGroup(isPro: Bool, currentCount: Int) -> Bool { true }

    /// Custom energy activities are available to everyone.
    static func canCreateCustomActivity(isPro: Bool) -> Bool { true }

    /// Moments are available to everyone.
    static func canAddMoment(isPro: Bool) -> Bool { true }

    /// The daily random theme is available to everyone.
    static func canUseDailyRandomTheme(isPro: Bool) -> Bool { true }

    /// Per-category shape customisation is available to everyone.
    static func canCustomizeShapes(isPro: Bool) -> Bool { true }

    /// Every gradient palette is available.
    static func isGradientPaletteAvailable(isPro: Bool, paletteRaw: String) -> Bool { true }

    /// Every gradient style is available.
    static func isGradientStyleAvailable(isPro: Bool, styleRaw: String) -> Bool { true }

    /// Every canvas texture is available.
    static func isCanvasTextureAvailable(isPro: Bool, textureRaw: String) -> Bool { true }
}
