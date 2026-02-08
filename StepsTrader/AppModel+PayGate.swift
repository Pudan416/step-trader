import Foundation
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(DeviceActivity)
import DeviceActivity
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
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
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
        if let group = findTicketGroup(for: bundleId) {
            Task { @MainActor in
                startPayGateSession(for: group.id)
            }
        } else {
            print("⚠️ PayGate: Could not find group for bundleId \(bundleId)")
        }
    }
    
    // MARK: - PayGate Payment Handling
    @MainActor
    func handlePayGatePaymentForGroup(groupId: String, window: AccessWindow, costOverride: Int?) async {
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            print("⚠️ PayGate: Group \(groupId) not found for payment")
            return
        }
        
        // Get cost - use override if provided, otherwise use group's cost for the window
        let cost = costOverride ?? group.cost(for: window)
        
        print("💰 Attempting to pay \(cost) experience for group \(group.name)")
        print("💰 Current balance: \(totalStepsBalance) (base: \(stepsBalance), bonus: \(bonusSteps))")
        
        // Pay the cost
        guard pay(cost: cost) else {
            message = "Not enough experience"
            print("❌ Payment failed - not enough experience")
            return
        }
        
        print("✅ Payment successful! New balance: \(totalStepsBalance) (base: \(stepsBalance), bonus: \(bonusSteps))")
        
        // Force UI update immediately - trigger on next run loop
        await MainActor.run {
            objectWillChange.send()
        }
        
        // Small delay to let SwiftUI process the state change
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Force another update after delay
        await MainActor.run {
            objectWillChange.send()
        }
        
        // Set group-level unlock timestamp
        let defaults = UserDefaults.stepsTrader()
        let now = Date()
        if let until = accessWindowExpiration(window, now: now) {
            defaults.set(until, forKey: "groupUnlock_\(groupId)")
            print("🔓 Group \(group.name) unlocked until \(until)")
            
            let remainingSeconds = Int(until.timeIntervalSince(now))
            
            // Schedule notification 1 minute before expiration
            scheduleUnlockExpiryNotification(groupName: group.name, expiresAt: until)
            
            // Schedule shield rebuild when unlock expires
            scheduleTicketRebuild(after: remainingSeconds, groupId: groupId)
        }
        
        // Track spent steps for analytics (use group id as identifier)
        addSpentSteps(cost, for: "group_\(groupId)")
        
        // Log payment transaction for history (capture balance before payment)
        let balanceBeforePayment = totalStepsBalance + cost
        logPaymentTransaction(
            amount: cost,
            target: "group_\(groupId)",
            targetName: group.name,
            window: window,
            balanceBefore: balanceBeforePayment,
            balanceAfter: totalStepsBalance
        )
        
        // CRITICAL: Rebuild shield to actually remove the block from all apps in the group
        rebuildFamilyControlsShield()
        
        // Another small delay before dismissing to ensure UI has updated
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Dismiss pay gate
        dismissPayGate(reason: .programmatic)
    }
    
    // MARK: - Scheduled Ticket/Block Rebuild
    private func scheduleTicketRebuild(after seconds: Int, groupId: String) {
        // Cancel any existing rebuild task for this group
        unlockExpiryTasks[groupId]?.cancel()
        
        // Schedule DeviceActivity interval that ends at unlock expiry
        // This ensures the extension gets called even if app is in background
        scheduleUnlockExpiryActivity(groupId: groupId, expiresInSeconds: seconds)
        
        // Also keep local Task for immediate rebuild when app is in foreground
        let task = Task { @MainActor in
            do {
                // Wait until unlock expires
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                
                guard !Task.isCancelled else { return }
                
                // Clear the unlock key
                let defaults = UserDefaults.stepsTrader()
                let unlockKey = "groupUnlock_\(groupId)"
                defaults.removeObject(forKey: unlockKey)
                
                print("⏰ Unlock expired for group \(groupId), clearing unlock key and rebuilding block...")
                
                // Rebuild shield to restore blocking
                rebuildFamilyControlsShield()
                
                // Clean up the task
                unlockExpiryTasks.removeValue(forKey: groupId)
            } catch {
                // Task was cancelled
                print("🚫 Block rebuild task cancelled for group \(groupId)")
                unlockExpiryTasks.removeValue(forKey: groupId)
            }
        }
        
        unlockExpiryTasks[groupId] = task
    }
    
    /// Schedule a DeviceActivity interval that ends when the unlock expires.
    /// For intervals >= 15 min: interval ends at expiry → intervalDidEnd in extension.
    /// For intervals < 15 min: 15-min window with warningTime so intervalWillEndWarning fires at expiry (extension clears unlock and rebuilds shield without app).
    private func scheduleUnlockExpiryActivity(groupId: String, expiresInSeconds: Int) {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("unlockExpiry_\(groupId)")
        let calendar = Calendar.current
        let now = Date()
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        
        let schedule: DeviceActivitySchedule
        if expiresInSeconds >= 900 {
            // Long unlock: interval ends exactly at expiry
            let expiryDate = now.addingTimeInterval(TimeInterval(expiresInSeconds))
            let endComponents = calendar.dateComponents([.hour, .minute, .second], from: expiryDate)
            schedule = DeviceActivitySchedule(
                intervalStart: startComponents,
                intervalEnd: endComponents,
                repeats: false
            )
            print("📅 Scheduled unlock expiry activity for group \(groupId) in \(expiresInSeconds)s (interval end)")
        } else {
            // Short unlock: 15-min minimum interval; warningTime so extension gets intervalWillEndWarning at expiry
            let endDate = now.addingTimeInterval(900)
            let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)
            let secondsBeforeEnd = 900 - expiresInSeconds
            let warningTime = DateComponents(second: secondsBeforeEnd)
            schedule = DeviceActivitySchedule(
                intervalStart: startComponents,
                intervalEnd: endComponents,
                repeats: false,
                warningTime: warningTime
            )
            print("📅 Scheduled unlock expiry activity for group \(groupId) in \(expiresInSeconds)s (warning in \(secondsBeforeEnd)s)")
        }
        
        center.stopMonitoring([activityName])
        do {
            try center.startMonitoring(activityName, during: schedule)
        } catch {
            print("❌ Failed to schedule unlock expiry activity: \(error)")
        }
        #endif
    }
    
    // MARK: - Expiry Notifications
    private func scheduleUnlockExpiryNotification(groupName: String, expiresAt: Date) {
        let now = Date()
        let totalSeconds = Int(expiresAt.timeIntervalSince(now))
        
        // Schedule notification 1 minute before expiration (if unlock is longer than 1 min)
        if totalSeconds > 60 {
            let fireIn = totalSeconds - 60
            scheduleGroupExpiryPush(groupName: groupName, fireInSeconds: fireIn, minutesRemaining: 1)
        }
        
        // Also schedule at expiration
        scheduleGroupExpiryPush(groupName: groupName, fireInSeconds: totalSeconds, minutesRemaining: 0)
    }
    
    private func scheduleGroupExpiryPush(groupName: String, fireInSeconds: Int, minutesRemaining: Int) {
        guard fireInSeconds > 0 else { return }
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = "ACCESS_EXPIRED"
        
        if minutesRemaining > 0 {
            content.title = "⏱️ \(groupName)"
            content.body = "Access ends in \(minutesRemaining) min. Save my work!"
        } else {
            content.title = "🔒 \(groupName)"
            content.body = "Access ended. Apps are blocked again."
            // Add action to rebuild shields when time expires
            content.userInfo = [
                "action": "expired",
                "groupName": groupName
            ]
        }
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(fireInSeconds),
            repeats: false
        )
        
        let identifier = "groupUnlock-\(minutesRemaining)min-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule expiry notification: \(error)")
            } else {
                print("📤 Scheduled \(groupName) expiry notification in \(fireInSeconds)s")
            }
        }
    }
    
    @MainActor
    func handlePayGatePayment(for bundleId: String, window: AccessWindow) async {
        let cost = unlockSettings(for: bundleId).entryCostSteps
        
        print("💰 handlePayGatePayment for \(bundleId), cost: \(cost)")
        print("💰 Current balance: \(totalStepsBalance) (base: \(stepsBalance), bonus: \(bonusSteps))")
        
        // Pay the cost
        guard pay(cost: cost) else {
            message = "Not enough experience"
            print("❌ Payment failed - not enough experience")
            return
        }
        
        print("✅ Payment successful! New balance: \(totalStepsBalance) (base: \(stepsBalance), bonus: \(bonusSteps))")
        
        // Log payment transaction for history
        let balanceBeforePayment = totalStepsBalance + cost
        logPaymentTransaction(
            amount: cost,
            target: bundleId,
            targetName: nil,
            window: window,
            balanceBefore: balanceBeforePayment,
            balanceAfter: totalStepsBalance
        )
        
        addSpentSteps(cost, for: bundleId)
        applyAccessWindow(window, for: bundleId)
        rebuildFamilyControlsShield()
        
        // Force UI update
        objectWillChange.send()
        
        // Small delay to let SwiftUI process
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        // Force another update
        objectWillChange.send()
        
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
        g.removeObject(forKey: "payGateTargetBundleId_v1")
    }
    
    // MARK: - Payment Transaction Logging
    struct PaymentTransaction: Codable {
        let id: String
        let timestamp: Date
        let amount: Int
        let target: String
        let targetName: String?
        let window: String?
        let balanceBefore: Int
        let balanceAfter: Int
    }
    
    private func logPaymentTransaction(amount: Int, target: String, targetName: String?, window: AccessWindow?, balanceBefore: Int, balanceAfter: Int) {
        let transaction = PaymentTransaction(
            id: UUID().uuidString,
            timestamp: Date(),
            amount: amount,
            target: target,
            targetName: targetName,
            window: window?.rawValue,
            balanceBefore: balanceBefore,
            balanceAfter: balanceAfter
        )
        
        let defaults = UserDefaults.stepsTrader()
        var transactions: [PaymentTransaction] = []
        
        // Load existing transactions
        if let data = defaults.data(forKey: "paymentTransactions_v1"),
           let decoded = try? JSONDecoder().decode([PaymentTransaction].self, from: data) {
            transactions = decoded
        }
        
        // Add new transaction
        transactions.append(transaction)
        
        // Keep only last 1000 transactions to prevent storage bloat
        if transactions.count > 1000 {
            transactions = Array(transactions.suffix(1000))
        }
        
        // Save transactions
        if let data = try? JSONEncoder().encode(transactions) {
            defaults.set(data, forKey: "paymentTransactions_v1")
            defaults.synchronize()
            print("📝 Logged payment transaction: \(amount) for \(target) (balance: \(balanceBefore) → \(balanceAfter))")
        }
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
