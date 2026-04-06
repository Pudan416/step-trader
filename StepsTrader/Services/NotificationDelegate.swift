import Foundation
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

@MainActor
final class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    weak var model: AppModel?

    private func persistPayGateIntent(groupId: String? = nil, bundleId: String? = nil) {
        let defaults = UserDefaults.stepsTrader()
        defaults.set(true, forKey: SharedKeys.shouldShowPayGate)
        defaults.set(Date(), forKey: SharedKeys.payGateRequestedAt)
        if let groupId {
            defaults.set(groupId, forKey: SharedKeys.payGateTargetGroupId)
            defaults.removeObject(forKey: SharedKeys.payGateTargetBundleId)
        } else if let bundleId {
            defaults.set(bundleId, forKey: SharedKeys.payGateTargetBundleId)
            defaults.removeObject(forKey: SharedKeys.payGateTargetGroupId)
        } else {
            defaults.removeObject(forKey: SharedKeys.payGateTargetGroupId)
            defaults.removeObject(forKey: SharedKeys.payGateTargetBundleId)
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Handle expired notification - rebuild shields
        if let action = userInfo["action"] as? String, action == "expired" {
            AppLogger.notifications.debug("🔒 Access expired notification tapped - rebuilding shields")
            self.model?.rebuildFamilyControlsShield()
            completionHandler()
            return
        }
        
        if let action = userInfo["action"] as? String, action == "unlock" {
            let defaults = UserDefaults.stepsTrader()
            
            // User explicitly tapped a notification → clear any dismiss cooldown
            // so startPayGateSession won't suppress this intentional action.
            defaults.removeObject(forKey: SharedKeys.payGateDismissedUntil)
            
            // PRIORITY 1: If groupId present in notification, open directly by group
            if let directGroupId = userInfo["groupId"] as? String {
                AppLogger.notifications.debug("📲 Push notification: opening PayGate for group \(directGroupId)")
                persistPayGateIntent(groupId: directGroupId)
                self.model?.openPayGate(for: directGroupId)
                completionHandler()
                return
            }
            
            // PRIORITY 2: Use bundleId from notification or saved state
            let directBundleId = userInfo["bundleId"] as? String
            let sharedBundleId = defaults.string(forKey: SharedKeys.lastBlockedAppBundleId)
            let sharedGroupId = defaults.string(forKey: SharedKeys.lastBlockedGroupId)
            
            // If saved groupId exists, use it directly
            if let groupId = sharedGroupId, directBundleId == nil {
                AppLogger.notifications.debug("📲 Push notification: using saved groupId \(groupId)")
                persistPayGateIntent(groupId: groupId)
                self.model?.openPayGate(for: groupId)
                completionHandler()
                return
            }
            
            let bundleId = directBundleId ?? sharedBundleId
            
            if let bundleId {
                AppLogger.notifications.debug("📲 Push notification tapped for unlock: \(bundleId)")
                AppLogger.notifications.debug("   - directBundleId: \(directBundleId ?? "nil")")
                AppLogger.notifications.debug("   - sharedBundleId: \(sharedBundleId ?? "nil")")
                
                // Open paygate — find group by bundleId
                persistPayGateIntent(bundleId: bundleId)
                self.model?.openPayGateForBundleId(bundleId)
            } else {
                AppLogger.notifications.debug("⚠️ Push notification tapped for unlock, but bundleId not found")
                
                // Last fallback: open the first ticket group
                persistPayGateIntent(groupId: nil, bundleId: nil)
                if let model = self.model {
                    if let firstGroup = model.blockingStore.ticketGroups.first {
                        AppLogger.notifications.debug("🔄 Fallback: Using first shield group: \(firstGroup.name) (id: \(firstGroup.id))")
                        model.openPayGate(for: firstGroup.id)
                    } else {
                        AppLogger.notifications.debug("⚠️ Fallback: No shield groups available")
                    }
                } else {
                    AppLogger.notifications.debug("⚠️ Fallback: Model is nil")
                }
            }
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        if let action = userInfo["action"] as? String, action == "expired" {
            AppLogger.notifications.debug("🔒 Access expired notification delivered - rebuilding shields")
            self.model?.rebuildFamilyControlsShield()
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
