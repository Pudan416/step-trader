import Foundation
import SwiftUI

/// Central source of truth for "what can a user do based on their subscription status".
///
/// Add new gates here, query them from views/stores. Don't sprinkle `isPro` checks
/// across the codebase — every gate (limit, locked option, feature flag) lives in
/// one place so changing the matrix later is a single-file edit.
///
/// Pro users (subscribed, lifetime, grandfathered) bypass all gates.
enum SubscriptionGate {

    // MARK: - Kill-switch

    /// While the app is under review and payments are not active, grant Pro
    /// to every user so all features are available for free.  Flip to `false`
    /// once IAP is approved and ready to go live.
    static let allFeaturesUnlocked = false

    // MARK: - Hard limits (Free tier)

    /// Maximum number of `TicketGroup`s a Free user can create.
    /// Existing groups beyond the limit (legacy users, downgrade after trial)
    /// are NOT removed — only blocking new creation.
    static let freeMaxBlockingGroups: Int = 2

    /// Number of past days unlocked in `HistoryView` for Free users.
    /// Older days (8…∞) render blurred behind a paywall. History itself is
    /// retained indefinitely for everyone — this only gates visibility, not storage.
    static let freeHistoryDayCount: Int = 7

    // MARK: - Allowed visual options for Free

    // Gradient palettes, gradient styles and canvas textures are all free for
    // everyone — see `isGradientPaletteAvailable` / `isGradientStyleAvailable` /
    // `isCanvasTextureAvailable` below. (Previously a subset was gated behind Pro.)

    // MARK: - Feature flags

    /// Free users cannot create custom energy activities (body/mind/heart).
    /// Existing custom activities (created during trial / by grandfathered users)
    /// remain visible and usable — only the "Add your own" button is locked.
    static let freeCanCreateCustomActivity: Bool = false

    /// Daily random theme (palette + style rolled per day, app-wide background
    /// changes daily, choice persisted into per-day `DayCanvas`) is free for everyone.
    static let freeCanUseDailyRandomTheme: Bool = true

    /// Assigning a custom shape type (circle/snowflake/rays/organic) to each energy
    /// category is free for everyone.
    static let freeCanCustomizeShapes: Bool = true

    // MARK: - Gate queries (use these from views/stores)

    /// Can the user create another blocking group?
    static func canAddBlockingGroup(isPro: Bool, currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < freeMaxBlockingGroups
    }

    /// Can the user create a custom energy card?
    static func canCreateCustomActivity(isPro: Bool) -> Bool {
        if isPro { return true }
        return freeCanCreateCustomActivity
    }

    /// Can the user log an ephemeral moment (one-time life event)?
    /// Moment entry is a Pro-only feature — the ✦ node in the radial fan is
    /// visible to all users but tapping it shows a paywall for free users.
    static func canAddMoment(isPro: Bool) -> Bool {
        return isPro
    }

    /// Can the user enable daily random theme?
    static func canUseDailyRandomTheme(isPro: Bool) -> Bool {
        if isPro { return true }
        return freeCanUseDailyRandomTheme
    }

    /// Can the user assign custom shapes to categories?
    static func canCustomizeShapes(isPro: Bool) -> Bool {
        if isPro { return true }
        return freeCanCustomizeShapes
    }

    /// Is this gradient palette available to the user? Free for everyone.
    static func isGradientPaletteAvailable(isPro: Bool, paletteRaw: String) -> Bool {
        return true
    }

    /// Is this gradient style available to the user? Free for everyone.
    static func isGradientStyleAvailable(isPro: Bool, styleRaw: String) -> Bool {
        return true
    }

    /// Is this canvas texture available to the user? Free for everyone.
    static func isCanvasTextureAvailable(isPro: Bool, textureRaw: String) -> Bool {
        return true
    }

    // NOTE: Sticker theme and PayGate background gates were removed —
    // sticker theme is hardcoded to index 0 everywhere, and PayGate uses a
    // single fixed palette (`PayGatePalette.background = .black`). Re-add
    // these gates only if/when the corresponding pickers ship in the UI.

    // MARK: - Onboarding paywall trigger

    /// UserDefaults key for "we already showed the post-onboarding paywall once".
    /// Don't spam: each user sees it exactly once, ever.
    static let postOnboardingPaywallShownKey = "paywall_postOnboardingShownAt_v1"

    /// Should we show the post-onboarding paywall right now?
    /// Returns `true` only if:
    /// - User is NOT Pro / grandfathered
    /// - We haven't shown it before on this device
    static func shouldShowPostOnboardingPaywall(
        isPro: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if isPro { return false }
        return defaults.object(forKey: postOnboardingPaywallShownKey) == nil
    }

    /// Mark the post-onboarding paywall as shown so it never appears again.
    static func markPostOnboardingPaywallShown(defaults: UserDefaults = .standard) {
        defaults.set(Date.now, forKey: postOnboardingPaywallShownKey)
    }
}
