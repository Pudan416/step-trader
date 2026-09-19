import Foundation
#if canImport(DeviceActivity)
import DeviceActivity
#endif

/// Why a usage-budget monitor refused to start.
///
/// `DeviceActivity` caps an app and its extensions at twenty concurrently monitored
/// activities. The ceiling counts open windows, not rows in the list, so reaching it
/// is unlikely — but it must fail legibly rather than leaving an app the user paid
/// to block sitting open.
enum UsageBudgetMonitoringError: Equatable, Sendable {
    case excessiveActivities

    /// Screen Time access is missing or was revoked. `ManagedSettingsStore` writes are
    /// inert in that state, so a purchase has to be refused up front — charging first
    /// would take colors for an unlock that cannot happen, with nothing to show for it.
    case notAuthorized

    case other(String)

    static func classify(_ error: Error) -> UsageBudgetMonitoringError {
        #if canImport(DeviceActivity)
        if let monitoring = error as? DeviceActivityCenter.MonitoringError,
           case .excessiveActivities = monitoring {
            return .excessiveActivities
        }
        #endif
        return .other(error.localizedDescription)
    }

    var userFacingMessage: String {
        switch self {
        case .excessiveActivities:
            String(
                localized: "Too many windows are open at once. Close one and try again — your colors were refunded.",
                comment: "Unlock failure – DeviceActivity activity cap reached"
            )
        case .notAuthorized:
            String(
                localized: "Nowhere doesn't have Screen Time access, so it can't open your feeds. Grant it in Settings and try again — you weren't charged.",
                comment: "Unlock failure – Family Controls authorization missing or revoked, refused before any charge"
            )
        case .other:
            String(
                localized: "Couldn't start the timer. Your colors were refunded — please try again in a moment.",
                comment: "Unlock failure – generic monitoring failure, after refund"
            )
        }
    }
}
