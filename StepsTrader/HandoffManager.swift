import Foundation
import UIKit

// §5.8: re-entrancy guard for attemptOpenScheme. Two simultaneous handoffs to
// the same bundleId (rare but possible via fast Shortcuts automation) used to
// race on the `lastAppOpenedFromStepsTrader` UserDefaults write — second open
// would overwrite the first. Now skipped if already opening that bundleId.
// File-scope `@MainActor` keeps the set safe; all callers are @MainActor.
@MainActor
private var _openingBundleIds: Set<String> = []

// MARK: - Handoff Manager Extension for AppModel
extension AppModel {

    func handleHandoffContinue() {
        guard let token = handoffToken else {
            AppLogger.app.error("❌ handleHandoffContinue called but no handoffToken found")
            return
        }

        guard !token.isExpired else {
            AppLogger.app.warning("⏰ Handoff token expired, cancelling")
            handleHandoffCancel()
            return
        }

        AppLogger.app.debug("🚀 User continued with handoff for \(token.targetAppName)")
        AppLogger.app.debug(
            "🚀 Before - showHandoffProtection: \(self.showHandoffProtection), handoffToken: \(self.handoffToken?.targetAppName ?? "nil")"
        )

        let userDefaults = UserDefaults.stepsTrader()

        // Hide protection screen
        showHandoffProtection = false
        handoffToken = nil
        AppLogger.app.debug(
            "🚀 After - showHandoffProtection: \(self.showHandoffProtection), handoffToken: \(self.handoffToken?.targetAppName ?? "nil")"
        )

        // Remove token
        userDefaults.removeObject(forKey: SharedKeys.handoffToken)
        AppLogger.app.debug("🚀 Removed handoff token from UserDefaults")

        // Open target app
        AppLogger.app.debug("🚀 Opening target app: \(token.targetBundleId)")
        openTargetApp(bundleId: token.targetBundleId)
    }

    func handleHandoffCancel() {
        AppLogger.app.info("User cancelled handoff")

        // Hide protection screen
        showHandoffProtection = false
        handoffToken = nil

        // Remove token
        let userDefaults = UserDefaults.stepsTrader()
        userDefaults.removeObject(forKey: SharedKeys.handoffToken)
    }

    private func openTargetApp(bundleId: String) {
        // §5.8: re-entrancy guard — drop if we're already mid-open for this bundleId.
        guard !_openingBundleIds.contains(bundleId) else {
            AppLogger.app.debug("🚀 Skipping duplicate open for \(bundleId) — already in flight")
            return
        }
        _openingBundleIds.insert(bundleId)

        let userDefaults = UserDefaults.stepsTrader()
        let now = Date.now
        userDefaults.set(now, forKey: SharedKeys.lastAppOpenedFromStepsTrader(bundleId))

        AppLogger.app.debug("🚀 Opening \(bundleId) from HandoffManager and setting protection flag at \(now)")

        let schemes = TargetResolver.primaryAndFallbackSchemes(for: bundleId)
        guard !schemes.isEmpty else {
            AppLogger.app.error("❌ No URL schemes found for \(bundleId), skipping handoff")
            _openingBundleIds.remove(bundleId)
            return
        }
        attemptOpenScheme(schemes: schemes, index: 0, bundleId: bundleId)
    }

    /// Try each URL scheme in order until one succeeds (audit fix #42)
    private func attemptOpenScheme(schemes: [String], index: Int, bundleId: String) {
        guard index < schemes.count else {
            AppLogger.app.error("❌ All URL schemes failed for \(bundleId)")
            _openingBundleIds.remove(bundleId)
            return
        }
        guard let url = URL(string: schemes[index]) else {
            attemptOpenScheme(schemes: schemes, index: index + 1, bundleId: bundleId)
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            if success {
                AppLogger.app.debug("✅ Opened \(bundleId) via \(schemes[index])")
                _openingBundleIds.remove(bundleId)
            } else {
                AppLogger.app.debug("⚠️ Scheme \(schemes[index]) failed for \(bundleId), trying next")
                Task { @MainActor in
                    self?.attemptOpenScheme(schemes: schemes, index: index + 1, bundleId: bundleId)
                }
            }
        }
    }
}
