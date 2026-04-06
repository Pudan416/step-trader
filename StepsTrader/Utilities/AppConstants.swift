import Foundation

enum AppConstants {
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
