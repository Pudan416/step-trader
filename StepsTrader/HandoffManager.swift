import Foundation
import UIKit

// §5.8: re-entrancy guard for openTargetApp. Two simultaneous handoffs to the same
// bundleId (rare but possible via fast Shortcuts automation) used to race on the
// `lastAppOpenedFromStepsTrader` UserDefaults write — second open would overwrite
// the first. Now skipped if already opening that bundleId.
// File-scope `@MainActor` keeps the set safe; all callers are @MainActor.
@MainActor
private var _openingBundleIds: Set<String> = []

/// Single entry point for re-opening a blocked target app. Tries the app's
/// Apple-verified Universal Links first — iOS routes those to the exact app that
/// owns the domain, so a third-party app squatting a custom scheme (the Standoff 2 /
/// `x://` collision) can't intercept them — and falls back to custom URL schemes
/// only if no installed app claims the link. Used by the widget deep link, the
/// ticket card tap, and the handoff-continue screen so every path behaves the same.
@MainActor
enum AppLauncher {
    static func open(bundleId: String, completion: ((Bool) -> Void)? = nil) {
        var candidates: [(url: URL, universalOnly: Bool)] = []
        for link in TargetResolver.universalLinks(forBundleId: bundleId) {
            if let url = URL(string: link) { candidates.append((url, true)) }
        }
        for scheme in TargetResolver.primaryAndFallbackSchemes(for: bundleId) {
            if let url = URL(string: scheme) { candidates.append((url, false)) }
        }
        attempt(candidates, index: 0, completion: completion)
    }

    private static func attempt(
        _ candidates: [(url: URL, universalOnly: Bool)],
        index: Int,
        completion: ((Bool) -> Void)?
    ) {
        guard index < candidates.count else {
            completion?(false)
            return
        }
        let (url, universalOnly) = candidates[index]
        // `universalLinksOnly` makes `open` report failure (instead of dumping the
        // user in Safari) when the target app isn't installed / doesn't claim the
        // link, so we can cleanly fall through to the next candidate.
        let options: [UIApplication.OpenExternalURLOptionsKey: Any] =
            universalOnly ? [.universalLinksOnly: true] : [:]
        UIApplication.shared.open(url, options: options) { success in
            Task { @MainActor in
                if success {
                    completion?(true)
                } else {
                    attempt(candidates, index: index + 1, completion: completion)
                }
            }
        }
    }
}

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

        // Universal Link first, then custom schemes (see AppLauncher).
        AppLauncher.open(bundleId: bundleId) { success in
            if success {
                AppLogger.app.debug("✅ Opened \(bundleId)")
            } else {
                AppLogger.app.error("❌ Could not open \(bundleId) via any Universal Link or URL scheme")
            }
            _openingBundleIds.remove(bundleId)
        }
    }
}
