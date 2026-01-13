//
//  ShieldActionExtension.swift
//  ShieldAction
//
//  Created by Konstantin Pudan on 12.01.2026.
//

import ManagedSettings
import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

fileprivate func stepsTraderDefaults() -> UserDefaults {
    let groupId = "group.personal-project.StepsTrader"
    return UserDefaults(suiteName: groupId) ?? .standard
}

    private struct StoredUnlockSettings: Codable {
        let familyControlsModeEnabled: Bool?
        let minuteTariffEnabled: Bool?
    }

// Make sure this class name matches the NSExtensionPrincipalClass in Info.plist.
class ShieldActionExtension: ShieldActionDelegate {
    private let store = ManagedSettingsStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            let bundleId = Application(token: application).bundleIdentifier
            if !isMinuteModeEnabled(bundleId: bundleId) {
                logAction(bundleId: bundleId)
            }
            allowOneSession(excluding: application, reenableAfter: isMinuteModeEnabled(bundleId: bundleId) ? nil : 10.0)
            completionHandler(.close)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            logAction(bundleId: nil)
            allowOneSession(excluding: nil)
            completionHandler(.close)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            logAction(bundleId: nil)
            allowOneSession(excluding: nil)
            completionHandler(.close)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    private func allowOneSession(excluding token: ApplicationToken?) {
        allowOneSession(excluding: token, reenableAfter: 10.0)
    }

    private func allowOneSession(excluding token: ApplicationToken?, reenableAfter: TimeInterval?) {
        let combined = rebuildCombinedSelection()
        if let token {
            var apps = combined.applicationTokens
            apps.remove(token)
            store.shield.applications = apps
        } else {
            store.shield.applications = combined.applicationTokens
        }
        // Temporarily drop category shielding to avoid blocking the allowed app.
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        guard let reenableAfter else { return }
        // Re-enable full shield shortly after to block on next launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + reenableAfter) { [weak self] in
            self?.reenableShieldFromStoredSelections()
        }
    }

    private func isMinuteModeEnabled(bundleId: String?) -> Bool {
        guard let bundleId else { return false }
        let g = stepsTraderDefaults()
        guard let data = g.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data),
              let settings = decoded[bundleId]
        else { return false }
        return (settings.familyControlsModeEnabled ?? false) || (settings.minuteTariffEnabled ?? false)
    }

    private func rebuildCombinedSelection() -> FamilyActivitySelection {
        #if canImport(FamilyControls)
        let g = stepsTraderDefaults()
        guard let data = g.data(forKey: "appUnlockSettings_v1"),
              let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data)
        else { return FamilyActivitySelection() }

        var combined = FamilyActivitySelection()
        for (bundleId, settings) in decoded {
            let enabled = settings.familyControlsModeEnabled ?? false
            if !enabled { continue }
            let key = "timeAccessSelection_v1_\(bundleId)"
            if let selectionData = g.data(forKey: key),
               let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData) {
                combined.applicationTokens.formUnion(selection.applicationTokens)
                combined.categoryTokens.formUnion(selection.categoryTokens)
            }
        }
        return combined

        #else
        return FamilyActivitySelection()
        #endif
    }

    private func reenableShieldFromStoredSelections() {
        #if canImport(FamilyControls)
        let combined = rebuildCombinedSelection()
        if combined.applicationTokens.isEmpty && combined.categoryTokens.isEmpty {
            return
        }
        store.shield.applications = combined.applicationTokens
        store.shield.applicationCategories = combined.categoryTokens.isEmpty
            ? nil
            : .specific(combined.categoryTokens)
        #endif
    }

    private func logAction(bundleId: String?) {
        let g = stepsTraderDefaults()
        let now = Date()
        if let last = g.object(forKey: "payGateLastOpen") as? Date,
           now.timeIntervalSince(last) < 1 {
            return
        }
        g.set(now, forKey: "payGateLastOpen")
        if let bundleId {
            g.set(bundleId, forKey: "payGateTargetBundleId")
            g.set(bundleId, forKey: "shortcutTarget")
        }
        g.set(true, forKey: "shouldShowPayGate")
        g.set(true, forKey: "shortcutTriggered")
        g.set(now, forKey: "shortcutTriggerTime")
    }
}
