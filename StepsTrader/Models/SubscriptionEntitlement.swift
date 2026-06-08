import Foundation

/// Single source of truth for RevenueCat product / entitlement identifiers.
/// These MUST match values configured in:
///   - RevenueCat dashboard (project "nowhere test")
///   - App Store Connect (or the local `Configuration.storekit` file for sim testing)
enum SubscriptionIDs {
    /// The single entitlement that gates "Pro" features in the app.
    /// Configure this entitlement in RC dashboard → Entitlements.
    static let proEntitlement = "premium"

    /// Default offering identifier used when fetching packages.
    /// `current` is RC's special token — the offering you mark as current in dashboard.
    /// Override only if you A/B test multiple offerings.
    static let currentOffering: String? = nil

    /// Product identifiers — must match RevenueCat dashboard, App Store Connect,
    /// and the local `.storekit` file exactly.
    enum Product {
        static let monthly = "pro_monthly"
        static let annual = "pro_annual"
        /// Non-consumable IAP — one-time, forever.
        static let lifetime = "pro_lifetime"
    }

    /// All paywall product IDs, in display-priority order (annual first for default selection).
    static let allProductIdentifiers: [String] = [
        Product.annual,
        Product.monthly,
        Product.lifetime
    ]

    /// Custom RC subscriber attributes used for analytics / segmentation.
    enum Attribute {
        static let grandfathered = "is_grandfathered"
        static let grandfatheredAt = "grandfathered_at"
        static let appLaunchCount = "app_launch_count_at_grandfather"
        static let supabaseUserID = "supabase_user_id"
    }

    /// Build numbers (CFBundleVersion, integer) BELOW this threshold are considered
    /// pre-paywall builds. A user whose receipt's `originalApplicationVersion` is
    /// below this number gets grandfathered into Pro for free, even after a fresh
    /// reinstall (the data lives in the Apple receipt, not on-device).
    ///
    /// SET THIS to the CFBundleVersion of the *last build shipped before the paywall*.
    /// Leaving it at 0 disables receipt-based grandfather restore (only the local
    /// `UserDefaults.standard[isGrandfathered]` flag is honoured).
    ///
    /// Example: if v1.5 (build 42) was the last pre-paywall build, set this to `43`.
    ///
    /// Set to 0: there was never a public free build (builds ≤13 shipped only to
    /// TestFlight/review, never the App Store), so there are no legitimate
    /// pre-paywall users to grandfather. Disabling receipt-based restore removes
    /// the risk of a new production install self-grandfathering if a paywall build
    /// ever ships with a build number below the threshold. TestFlight testers who
    /// already used the app keep Pro via the local `isGrandfathered` flag.
    static let grandfatherBeforeBuild: Int = 0
}
