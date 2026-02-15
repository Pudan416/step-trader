import Foundation
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

// Minimal settings copy for decoding appUnlockSettings_v1
private struct StoredUnlockSettingsForNotification: Codable {
    let entryCostSteps: Int?
    let minuteTariffEnabled: Bool?
    let familyControlsModeEnabled: Bool?
}

// Minimal structure for decoding ticket groups
private struct ShieldGroupDataForNotification: Codable {
    let id: String
    let name: String
    let selectionData: Data?
    
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var model: AppModel?

    private enum PayGateIntentKeys {
        static let shouldShowPayGate = "shouldShowPayGate"
        static let payGateTargetGroupId = "payGateTargetGroupId"
        static let payGateTargetBundleId = "payGateTargetBundleId_v1"
        static let payGateRequestedAt = "payGateRequestedAt_v1"
    }
    
    private func persistPayGateIntent(groupId: String? = nil, bundleId: String? = nil) {
        let defaults = UserDefaults.stepsTrader()
        defaults.set(true, forKey: PayGateIntentKeys.shouldShowPayGate)
        defaults.set(Date(), forKey: PayGateIntentKeys.payGateRequestedAt)
        if let groupId {
            defaults.set(groupId, forKey: PayGateIntentKeys.payGateTargetGroupId)
            defaults.removeObject(forKey: PayGateIntentKeys.payGateTargetBundleId)
        } else if let bundleId {
            defaults.set(bundleId, forKey: PayGateIntentKeys.payGateTargetBundleId)
            defaults.removeObject(forKey: PayGateIntentKeys.payGateTargetGroupId)
        } else {
            defaults.removeObject(forKey: PayGateIntentKeys.payGateTargetGroupId)
            defaults.removeObject(forKey: PayGateIntentKeys.payGateTargetBundleId)
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle expired notification - rebuild shields
        if let action = userInfo["action"] as? String, action == "expired" {
            print("🔒 Access expired notification tapped - rebuilding shields")
            Task { @MainActor in
                self.model?.purgeExpiredAccessWindows()
                self.model?.rebuildFamilyControlsShield()
            }
            completionHandler()
            return
        }
        
        if let action = userInfo["action"] as? String, action == "unlock" {
            let defaults = UserDefaults.stepsTrader()
            
            // User explicitly tapped a notification → clear any dismiss cooldown
            // so startPayGateSession won't suppress this intentional action.
            defaults.removeObject(forKey: "payGateDismissedUntil_v1")
            
            // PRIORITY 1: If groupId present in notification, open directly by group
            if let directGroupId = userInfo["groupId"] as? String {
                print("📲 Push notification: opening PayGate for group \(directGroupId)")
                persistPayGateIntent(groupId: directGroupId)
                Task { @MainActor in
                    self.model?.openPayGate(for: directGroupId)
                }
                completionHandler()
                return
            }
            
            // PRIORITY 2: Use bundleId from notification or saved state
            let directBundleId = userInfo["bundleId"] as? String
            let sharedBundleId = defaults.string(forKey: "lastBlockedAppBundleId")
            let sharedGroupId = defaults.string(forKey: "lastBlockedGroupId")
            
            // If saved groupId exists, use it directly
            if let groupId = sharedGroupId, directBundleId == nil {
                print("📲 Push notification: using saved groupId \(groupId)")
                persistPayGateIntent(groupId: groupId)
                Task { @MainActor in
                    self.model?.openPayGate(for: groupId)
                }
                completionHandler()
                return
            }
            
            let bundleId = directBundleId ?? sharedBundleId
            
            if let bundleId {
                print("📲 Push notification tapped for unlock: \(bundleId)")
                print("   - directBundleId: \(directBundleId ?? "nil")")
                print("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                
                // Open paygate — find group by bundleId
                persistPayGateIntent(bundleId: bundleId)
                Task { @MainActor in
                    self.model?.openPayGateForBundleId(bundleId)
                }
            } else {
                print("⚠️ Push notification tapped for unlock, but bundleId not found")
                
                // Last fallback: open the first ticket group
                persistPayGateIntent(groupId: nil, bundleId: nil)
                Task { @MainActor in
                    guard let model = self.model else { 
                        print("⚠️ Fallback: Model is nil")
                        return 
                    }
                    
                    if let firstGroup = model.blockingStore.ticketGroups.first {
                        print("🔄 Fallback: Using first shield group: \(firstGroup.name) (id: \(firstGroup.id))")
                        model.openPayGate(for: firstGroup.id)
                    } else {
                        print("⚠️ Fallback: No shield groups available")
                    }
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // If this is an "expired" notification, rebuild shields immediately
        if let action = userInfo["action"] as? String, action == "expired" {
            print("🔒 Access expired notification delivered - rebuilding shields")
            Task { @MainActor in
                // Clear expired unlocks and rebuild
                self.model?.purgeExpiredAccessWindows()
                self.model?.rebuildFamilyControlsShield()
            }
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
