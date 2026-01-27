import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - PayGate Management
extension AppModel {
    // MARK: - PayGate Keys
    private var payGateDismissedUntilKey: String { "payGateDismissedUntil_v1" }
    
    // MARK: - PayGate Opening
    func openPayGate(for groupId: String) {
        Task { @MainActor in
            startPayGateSession(for: groupId)
        }
    }
    
    @MainActor
    func startPayGateSession(for groupId: String) {
        let g = UserDefaults.stepsTrader()
        if !showPayGate,
           let until = g.object(forKey: payGateDismissedUntilKey) as? Date,
           Date() < until
        {
            print("🚫 PayGate suppressed after dismiss (\(String(format: "%.1f", until.timeIntervalSinceNow))s left), ignoring start for group \(groupId)")
            return
        }

        // Проверяем, существует ли группа
        guard let group = shieldGroups.first(where: { $0.id == groupId }) else {
            print("⚠️ PayGate: Group \(groupId) not found")
            return
        }
        
        payGateTargetGroupId = groupId
        showPayGate = true
        
        // Создаем сессию
        let session = PayGateSession(id: groupId, groupId: groupId, startedAt: Date())
        payGateSessions[groupId] = session
        currentPayGateSessionId = groupId
        
        print("🎯 PayGate session started for group: \(group.name) (\(groupId))")
    }
    
    func openPayGateForBundleId(_ bundleId: String) {
        // Ищем группу, которая содержит это приложение
        if let group = findShieldGroup(for: bundleId) {
            Task { @MainActor in
                startPayGateSession(for: group.id)
            }
        } else {
            print("⚠️ PayGate: Could not find group for bundleId \(bundleId)")
        }
    }
    
    // MARK: - PayGate Payment Handling
    func handlePayGatePaymentForGroup(groupId: String, window: AccessWindow, costOverride: Int?) async {
        guard let group = shieldGroups.first(where: { $0.id == groupId }) else {
            print("⚠️ PayGate: Group \(groupId) not found for payment")
            return
        }
        
        // Get cost - use override if provided, otherwise use group's cost for the window
        let cost = costOverride ?? group.cost(for: window)
        
        // Pay the cost
        guard pay(cost: cost) else {
            message = "Not enough control"
            return
        }
        
        // Find a bundle ID from the group to apply access window
        #if canImport(FamilyControls)
        let userDefaults = UserDefaults.stepsTrader()
        for token in group.selection.applicationTokens {
            if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                if let appName = userDefaults.string(forKey: tokenKey) {
                    let bundleId = TargetResolver.bundleId(from: appName) ?? appName
                    addSpentSteps(cost, for: bundleId)
                    applyAccessWindow(window, for: bundleId)
                    break
                }
            }
        }
        #endif
        
        // Also set group-level unlock
        let defaults = UserDefaults.stepsTrader()
        if let until = accessWindowExpiration(window, now: Date()) {
            defaults.set(until, forKey: "groupUnlock_\(groupId)")
        }
        
        // Dismiss pay gate
        dismissPayGate(reason: .programmatic)
    }
    
    func handlePayGatePayment(for bundleId: String, window: AccessWindow) async {
        let cost = unlockSettings(for: bundleId).entryCostSteps
        
        // Pay the cost
        guard pay(cost: cost) else {
            message = "Not enough control"
            return
        }
        
        addSpentSteps(cost, for: bundleId)
        applyAccessWindow(window, for: bundleId)
        
        // Dismiss pay gate
        dismissPayGate(reason: .programmatic)
    }
    
    // MARK: - PayGate Dismissal
    func dismissPayGate(reason: PayGateDismissReason = .userDismiss) {
        showPayGate = false
        payGateTargetGroupId = nil
        payGateSessions.removeAll()
        currentPayGateSessionId = nil
        let g = UserDefaults.stepsTrader()
        let now = Date()
        if reason == .userDismiss {
            // Cooldown to prevent instant re-open loops when the user dismisses PayGate.
            g.set(now.addingTimeInterval(10), forKey: payGateDismissedUntilKey)
            g.set(now, forKey: "lastPayGateAction")
        }
        g.removeObject(forKey: "shouldShowPayGate")
        g.removeObject(forKey: "payGateTargetGroupId")
    }
    
    // MARK: - Automation Recording
    func recordAutomationOpen(bundleId: String, spentSteps: Int? = nil) {
        let defaults = UserDefaults.stepsTrader()
        var dict: [String: Date] = [:]
        if let data = defaults.data(forKey: "automationLastOpened_v1"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            dict = decoded
        }
        dict[bundleId] = Date()
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: "automationLastOpened_v1")
        }
        
        // Mark as configured and clear pending once opened
        var configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        if !configured.contains(bundleId) {
            configured.append(bundleId)
            defaults.set(configured, forKey: "automationConfiguredBundles")
        }
        var pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        if let idx = pending.firstIndex(of: bundleId) {
            pending.remove(at: idx)
            defaults.set(pending, forKey: "automationPendingBundles")
        }
        if let pendingData = defaults.data(forKey: "automationPendingTimestamps_v1"),
           var ts = try? JSONDecoder().decode([String: Date].self, from: pendingData) {
            ts.removeValue(forKey: bundleId)
            if let data = try? JSONEncoder().encode(ts) {
                defaults.set(data, forKey: "automationPendingTimestamps_v1")
            }
        }
    }
}
