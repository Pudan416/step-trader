import Foundation

/// Central answer to "what can a user do".
///
/// The app is free and every gate returns `true`. The functions survive their
/// own retirement on purpose: they keep the call sites reading as intent, and
/// they are the one place to reintroduce gating without hunting through views.
/// The `isPro` parameters are deliberately unused.
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
