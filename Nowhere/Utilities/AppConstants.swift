import Foundation

enum AppConstants {
    enum URLs {
        /// iCloud Shortcuts share link for the wallpaper-update shortcut
        /// surfaced in `SettingsShortcutPage`. Force-unwrap is safe — this is
        /// a static literal verified at compile time. (CODE_AUDIT.md §9.5)
        // swiftlint:disable:next force_unwrapping
        static let wallpaperShortcut = URL(string: "https://www.icloud.com/shortcuts/e32b44858d5f4c829b35c9f8ad5f2756")!
    }

    enum Timing {
        /// How long a HandoffToken remains valid (seconds)
        static let handoffTokenExpiry: TimeInterval = 60

        /// Cooldown after PayGate is dismissed before it can reappear (seconds)
        static let payGateDismissCooldown: TimeInterval = 10

        /// Delay before refetching sleep data after day boundary (seconds)
        static let sleepRefetchDelay: TimeInterval = 60

        /// Interval for the periodic day-boundary / cleanup check (seconds)
        static let cleanupTimerInterval: TimeInterval = 30

        /// Proactively refresh a session token when it expires within this many seconds
        static let sessionRefreshThreshold: TimeInterval = 60
    }
}
