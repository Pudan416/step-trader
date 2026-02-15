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


// Local copy of settings structure (minimal fields needed for key decoding).
private struct StoredUnlockSettings: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
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
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            completionHandler(.close)
            return
        }
        
        // IMPORTANT: Check if this app's group is already unlocked
        if isAppCurrentlyUnlocked(application: application, defaults: defaults) {
            print("✅ ShieldAction: App is currently unlocked, allowing access")
            completionHandler(.close)
            return
        }
        
        let currentState = defaults.integer(forKey: SharedKeys.shieldState)
        
        switch action {
        case .primaryButtonPressed:
            if currentState == 0 {
                // First tap on "Unlock": switch to "waitingPush" state and send push
                defaults.set(1, forKey: SharedKeys.shieldState)
                sendUnlockNotification(for: application, using: defaults)
                completionHandler(.defer)
            } else {
                // In second state "Push not received" button — just resend push
                sendUnlockNotification(for: application, using: defaults)
                completionHandler(.defer)
            }
        case .secondaryButtonPressed:
            // Just in case — ask system to redraw the shield
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }
    
    /// Check if the app is unlocked within any group
    private func isAppCurrentlyUnlocked(application: ApplicationToken, defaults: UserDefaults) -> Bool {
        #if canImport(FamilyControls)
        let now = Date()
        
        // Check ticket groups (then legacy shield groups)
        guard let groupsData = defaults.data(forKey: SharedKeys.ticketGroups) ?? defaults.data(forKey: SharedKeys.legacyShieldGroups),
              let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: groupsData)
        else {
            return false
        }
        
        for group in groups {
            // Check if this group is unlocked
            let unlockKey = SharedKeys.groupUnlockKey(group.id)
            guard let unlockUntil = defaults.object(forKey: unlockKey) as? Date,
                  now < unlockUntil
            else {
                continue // Group not unlocked
            }
            
            // Group is unlocked — check if it contains this app
            if let selectionData = group.selectionData,
               let sel = try? JSONDecoder().decode(FamilyControls.FamilyActivitySelection.self, from: selectionData),
               sel.applicationTokens.contains(application) {
                print("✅ ShieldAction: App found in unlocked group \(group.name)")
                return true
            }
        }
        
        return false
        #else
        return false
        #endif
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
        completionHandler(.close)
    }
    
    // MARK: - Private helpers
    
    private func sendUnlockNotification(for application: ApplicationToken, using defaults: UserDefaults?) {
        // Get shared defaults from App Group (retry if nil)
        guard let defaults = defaults ?? UserDefaults(suiteName: SharedKeys.appGroupId) else {
            print("❌ ShieldAction: No UserDefaults for app group")
            return
        }
        
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        
        // Determine bundleId and groupId for the blocked app
        let resolved = resolveAppInfo(for: application, defaults: defaults)
        let blockedTargetName: String = {
            guard let name = resolved.bundleId, !name.isEmpty, !name.contains(".") else {
                return "This app"
            }
            return name
        }()
        
        content.title = "Proof"
        content.body = "\(blockedTargetName) is closed. Tap to spend exp."
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
        
        let request = UNNotificationRequest(
            identifier: "shield_unlock_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        center.add(request) { error in
            if let error = error {
                print("❌ ShieldAction: failed to schedule unlock notification: \(error)")
            } else {
                print("✅ ShieldAction: scheduled unlock notification (bundleId: \(resolved.bundleId ?? "nil"), groupId: \(resolved.groupId ?? "nil"))")
            }
        }
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
                        let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
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
    
    // Minimal structure for decoding ticket groups
    private struct ShieldGroupData: Codable {
        let id: String
        let name: String
        let selectionData: Data?
        
        enum CodingKeys: String, CodingKey {
            case id, name, selectionData
        }
    }
}
