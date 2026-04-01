//
//  ShieldActionExtension.swift
//  ShieldAction
//
//  Created by Konstantin Pudan on 24.01.2026.
//

import Foundation
import ManagedSettings
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

private func makeISO8601Formatter() -> ISO8601DateFormatter {
    ISO8601DateFormatter()
}

// Override the functions below to customize the shield actions used in various situations.
// The system provides a default response for any functions that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logToDefaults("🔵 handle() called — action: \(action == .primaryButtonPressed ? "primary" : "secondary")")
        
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            logToDefaults("❌ Could not open app group defaults")
            completionHandler(.close)
            return
        }
        
        switch action {
        case .primaryButtonPressed:
            let resolved = resolveAppInfo(for: application, defaults: defaults)
            logToDefaults("📋 resolved bundleId=\(resolved.bundleId ?? "nil") groupId=\(resolved.groupId ?? "nil")")
            
            let lastRequestKey = "shieldUnlockLastRequestedAt"
            let now = Date()
            if let last = defaults.object(forKey: lastRequestKey) as? Date,
               now.timeIntervalSince(last) < 3 {
                logToDefaults("⏳ Debounced — notification already sent recently")
                completionHandler(.defer)
                return
            }
            defaults.set(now, forKey: lastRequestKey)
            
            persistPayGateIntent(groupId: resolved.groupId, bundleId: resolved.bundleId, defaults: defaults)
            sendUnlockNotification(for: resolved, defaults: defaults) {
                completionHandler(.defer)
            }
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
        completionHandler(.close)
    }
    
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logToDefaults("🔵 handle(category) called — action: \(action == .primaryButtonPressed ? "primary" : "secondary")")

        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            logToDefaults("❌ Could not open app group defaults")
            completionHandler(.close)
            return
        }

        switch action {
        case .primaryButtonPressed:
            let resolved = resolveCategoryInfo(for: category, defaults: defaults)
            logToDefaults("📋 category resolved groupId=\(resolved.groupId ?? "nil") groupName=\(resolved.groupName ?? "nil")")

            let lastRequestKey = "shieldUnlockLastRequestedAt"
            let now = Date()
            if let last = defaults.object(forKey: lastRequestKey) as? Date,
               now.timeIntervalSince(last) < 3 {
                logToDefaults("⏳ Debounced — notification already sent recently")
                completionHandler(.defer)
                return
            }
            defaults.set(now, forKey: lastRequestKey)

            persistPayGateIntent(groupId: resolved.groupId, bundleId: nil, defaults: defaults)
            sendUnlockNotification(for: (bundleId: resolved.groupName, groupId: resolved.groupId), defaults: defaults) {
                completionHandler(.defer)
            }
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }
    
    // MARK: - Private helpers
    
    private func persistPayGateIntent(groupId: String?, bundleId: String?, defaults: UserDefaults) {
        defaults.set(true, forKey: SharedKeys.shouldShowPayGate)
        defaults.set(Date(), forKey: SharedKeys.payGateRequestedAt)
        if let groupId {
            defaults.set(groupId, forKey: SharedKeys.payGateTargetGroupId)
            defaults.removeObject(forKey: SharedKeys.payGateTargetBundleId)
        } else if let bundleId {
            defaults.set(bundleId, forKey: SharedKeys.payGateTargetBundleId)
            defaults.removeObject(forKey: SharedKeys.payGateTargetGroupId)
        }
        defaults.set(0, forKey: SharedKeys.shieldState)
        logToDefaults("💾 PayGate intent persisted (groupId=\(groupId ?? "nil"), bundleId=\(bundleId ?? "nil"))")
    }
    
    private func sendUnlockNotification(for resolved: (bundleId: String?, groupId: String?), defaults: UserDefaults, then done: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        
        let blockedTargetName: String = {
            guard let name = resolved.bundleId, !name.isEmpty, !name.contains(".") else {
                return NSLocalizedString("This app", comment: "Fallback name for blocked app in notification")
            }
            return name
        }()
        
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Nowhere", comment: "App name used in notification title")
        content.body = String(format: NSLocalizedString("%@ is closed. Tap to spend colors and unlock it.", comment: "Shield notification body"), blockedTargetName)
        content.sound = .default
        content.categoryIdentifier = "UNLOCK_APP"
        
        var userInfo: [String: Any] = ["action": "unlock"]
        if let bundleId = resolved.bundleId {
            userInfo["bundleId"] = bundleId
        }
        if let groupId = resolved.groupId {
            userInfo["groupId"] = groupId
        }
        content.userInfo = userInfo
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "shield_unlock_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        center.add(request) { [self] error in
            if let error = error {
                self.logToDefaults("❌ Notification failed: \(error.localizedDescription)")
            } else {
                self.logToDefaults("✅ Notification committed")
            }
            done()
        }
    }
    
    private func logToDefaults(_ message: String) {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else { return }
        let ts = makeISO8601Formatter().string(from: Date())
        let entry = "[\(ts)] \(message)"
        var logs = defaults.stringArray(forKey: SharedKeys.shieldActionLogs) ?? []
        logs.append(entry)
        if logs.count > 20 { logs = Array(logs.suffix(20)) }
        defaults.set(logs, forKey: SharedKeys.shieldActionLogs)
    }
    
    /// Determine groupId for a blocked category by iterating ticket groups.
    private func resolveCategoryInfo(for category: ActivityCategoryToken, defaults: UserDefaults) -> (groupId: String?, groupName: String?) {
        #if canImport(FamilyControls)
        if let groupsData = defaults.data(forKey: SharedKeys.ticketGroups) ?? defaults.data(forKey: SharedKeys.legacyShieldGroups),
           let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData) {
            for group in groups {
                if let selectionData = group.selectionData,
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
                   sel.categoryTokens.contains(category) {
                    defaults.set(group.id, forKey: SharedKeys.lastBlockedGroupId)
                    return (groupId: group.id, groupName: group.name)
                }
            }
        }
        return (groupId: nil, groupName: nil)
        #else
        return (groupId: nil, groupName: nil)
        #endif
    }

    /// Determine bundleId and groupId of the blocked app.
    private func resolveAppInfo(for application: ApplicationToken, defaults: UserDefaults) -> (bundleId: String?, groupId: String?) {
        #if canImport(FamilyControls)
        // 1) Check ticket groups (ticketGroups_v1 then shieldGroups_v1)
        if let groupsData = defaults.data(forKey: SharedKeys.ticketGroups) ?? defaults.data(forKey: SharedKeys.legacyShieldGroups),
           let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData) {
            for group in groups {
                if let selectionData = group.selectionData,
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
                   sel.applicationTokens.contains(application) {
                    // Found group with this app — get name/bundleId
                    if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: application, requiringSecureCoding: true) {
                        let tokenKey = SharedKeys.fcAppNameKey(tokenData.base64EncodedString())
                        if let appName = defaults.string(forKey: tokenKey) {
                            // Save for fallback
                            defaults.set(appName, forKey: SharedKeys.lastBlockedAppBundleId)
                            defaults.set(group.id, forKey: SharedKeys.lastBlockedGroupId)
                            return (bundleId: appName, groupId: group.id)
                        }
                    }
                    // Even if name not found, return groupId
                    defaults.set(group.id, forKey: SharedKeys.lastBlockedGroupId)
                    return (bundleId: nil, groupId: group.id)
                }
            }
        }
        
        // 2) Check lastBlockedAppBundleId and verify selection still contains this token
        if let existing = defaults.string(forKey: SharedKeys.lastBlockedAppBundleId) {
            let key = SharedKeys.timeAccessSelectionKey(existing)
            if let data = defaults.data(forKey: key),
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: data),
               sel.applicationTokens.contains(application) {
                let groupId = defaults.string(forKey: SharedKeys.lastBlockedGroupId)
                return (bundleId: existing, groupId: groupId)
            }
        }
        
        // 3) Search in appUnlockSettings_v1
        if let data = defaults.data(forKey: SharedKeys.appUnlockSettings),
           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
            for (appId, _) in decoded {
                let key = SharedKeys.timeAccessSelectionKey(appId)
                if let selData = defaults.data(forKey: key),
                   let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selData),
                   sel.applicationTokens.contains(application) {
                    defaults.set(appId, forKey: SharedKeys.lastBlockedAppBundleId)
                    return (bundleId: appId, groupId: nil)
                }
            }
        }
        
        // 4) Nothing found — clear stale values to avoid using incorrect data
        defaults.removeObject(forKey: SharedKeys.lastBlockedAppBundleId)
        defaults.removeObject(forKey: SharedKeys.lastBlockedGroupId)
        
        return (bundleId: nil, groupId: nil)
        #else
        return (bundleId: nil, groupId: nil)
        #endif
    }
    
}
