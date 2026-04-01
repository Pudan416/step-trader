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
        startPayGateSession(for: groupId)
    }
    
    @MainActor
    func startPayGateSession(for groupId: String) {
        if showPayGate, payGateTargetGroupId == groupId { return }

        let g = UserDefaults.stepsTrader()
        if !showPayGate,
           let until = g.object(forKey: payGateDismissedUntilKey) as? Date,
           Date() < until
        {
            AppLogger.shield.debug("🚫 PayGate suppressed after dismiss (\(String(format: "%.1f", until.timeIntervalSinceNow))s left), ignoring start for group \(groupId)")
            return
        }

        // Verify the group exists
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            AppLogger.shield.debug("⚠️ PayGate: Group \(groupId) not found")
            return
        }
        
        payGateTargetGroupId = groupId
        showPayGate = true
        g.set(Date(), forKey: SharedKeys.lastGroupPayGateOpen(groupId))

        // Create session
        let session = PayGateSession(id: groupId, groupId: groupId, startedAt: Date())
        payGateSessions[groupId] = session
        currentPayGateSessionId = groupId
        
        AppLogger.shield.debug("🎯 PayGate session started for group: \(group.name) (\(groupId))")
    }
    
    func openPayGateForBundleId(_ bundleId: String) {
        // Find the group containing this app
        if let group = findTicketGroup(for: bundleId) {
            startPayGateSession(for: group.id)
        } else {
            AppLogger.shield.debug("⚠️ PayGate: Could not find group for bundleId \(bundleId)")
        }
    }
    
    // MARK: - PayGate Payment Handling
    @MainActor
    func handlePayGatePaymentForGroup(groupId: String, window: AccessWindow, costOverride: Int?) async {
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            AppLogger.shield.debug("⚠️ PayGate: Group \(groupId) not found for payment")
            return
        }
        
        let cost = costOverride ?? group.cost(for: window)
        let minutes = window.minutes
        
        AppLogger.shield.debug("💰 Attempting to pay \(cost) colors for \(minutes) min (usage budget) for group \(group.name)")
        
        guard pay(cost: cost) else {
            AppLogger.shield.debug("❌ Payment failed - not enough colors")
            return
        }
        
        AppLogger.shield.debug("✅ Payment successful! New balance: \(self.totalStepsBalance)")
        
        let defaults = UserDefaults.stepsTrader()
        let budgetKey = SharedKeys.usageBudgetKey(groupId)
        let startedKey = SharedKeys.usageBudgetStartedKey(groupId)

        let existingBudget = defaults.integer(forKey: budgetKey)
        if existingBudget > 0 {
            #if canImport(DeviceActivity)
            DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(groupId)")])
            #endif
        }
        let totalMinutes = existingBudget + minutes
        let initialKey = SharedKeys.usageBudgetInitialKey(groupId)

        defaults.set(totalMinutes, forKey: budgetKey)
        defaults.set(totalMinutes, forKey: initialKey)
        defaults.set(Date(), forKey: startedKey)
        defaults.set(Date().addingTimeInterval(TimeInterval(totalMinutes * 60)), forKey: SharedKeys.usageBudgetExpiryKey(groupId))

        startUsageBudgetMonitoring(groupId: groupId, minutes: totalMinutes)
        
        addSpentSteps(cost, for: "group_\(groupId)")
        
        let balanceBeforePayment = self.totalStepsBalance + cost
        logPaymentTransaction(
            amount: cost,
            target: "group_\(groupId)",
            targetName: group.name,
            window: window,
            balanceBefore: balanceBeforePayment,
            balanceAfter: self.totalStepsBalance
        )
        
        ShieldRebuildHelper.rebuild()
        rebuildFamilyControlsShield()
        dismissPayGate(reason: .programmatic)
    }

    private func startUsageBudgetMonitoring(groupId: String, minutes: Int) {
        let logDefaults = UserDefaults.stepsTrader()
        let iso = ISO8601DateFormatter()

        #if !canImport(DeviceActivity) || !canImport(FamilyControls)
        logDefaults.set("[\(iso.string(from: Date()))] SKIP usageBudget_\(groupId) — DeviceActivity/FamilyControls not available", forKey: SharedKeys.lastStartMonitoringLog)
        return
        #else
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            logDefaults.set("[\(iso.string(from: Date()))] SKIP usageBudget_\(groupId) — group not found", forKey: SharedKeys.lastStartMonitoringLog)
            return
        }

        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("usageBudget_\(groupId)")

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // Milestone ticks instead of per-minute to avoid event explosion
        let milestoneFractions: [Double] = [0.50, 0.75, 0.90]
        var seen = Set<Int>()
        for frac in milestoneFractions {
            let m = Int(Double(minutes) * frac)
            guard m >= 1, m < minutes, !seen.contains(m) else { continue }
            seen.insert(m)
            let tickName = DeviceActivityEvent.Name("usageBudgetTick_\(groupId)_\(m)")
            events[tickName] = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: group.selection.categoryTokens,
                threshold: DateComponents(minute: m)
            )
        }

        let doneName = DeviceActivityEvent.Name("usageBudgetDone_\(groupId)")
        events[doneName] = DeviceActivityEvent(
            applications: group.selection.applicationTokens,
            categories: group.selection.categoryTokens,
            threshold: DateComponents(minute: minutes)
        )

        let dayEndH = logDefaults.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndM = logDefaults.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let endH = dayEndM > 0 ? dayEndH : (dayEndH + 23) % 24
        let endM = dayEndM > 0 ? dayEndM - 1 : 59

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: dayEndH, minute: dayEndM, second: 0),
            intervalEnd: DateComponents(hour: endH, minute: endM, second: 59),
            repeats: true
        )

        center.stopMonitoring([activityName])

        let schedDesc = "start=\(dayEndH):\(dayEndM):0 end=\(endH):\(endM):59"
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            let msg = "[\(iso.string(from: Date()))] OK usageBudget_\(groupId) \(minutes)m events=\(events.count) apps=\(group.selection.applicationTokens.count) sched=[\(schedDesc)] activities=\(center.activities.map(\.rawValue))"
            logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
        } catch {
            let msg = "[\(iso.string(from: Date()))] FAIL usageBudget_\(groupId) — \(error.localizedDescription) sched=[\(schedDesc)]"
            logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
        }
        #endif
    }

    // MARK: - Pending Widget Budget Monitoring

    func startPendingWidgetBudgetMonitoring() {
        let defaults = UserDefaults.stepsTrader()
        for group in ticketGroups {
            let pendingKey = "pendingBudgetMonitoring_\(group.id)"
            let minutesKey = "pendingBudgetMinutes_\(group.id)"
            guard defaults.bool(forKey: pendingKey) else { continue }
            let minutes = defaults.integer(forKey: minutesKey)
            guard minutes > 0 else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }
            AppLogger.shield.debug("📡 Starting DeviceActivity monitoring for widget-initiated budget: \(group.name) \(minutes)m")
            startUsageBudgetMonitoring(groupId: group.id, minutes: minutes)
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: minutesKey)
        }

        for group in ticketGroups {
            let spendTrackingKey = "pendingSpendTracking_\(group.id)"
            let spendAmountKey = "pendingSpendAmount_\(group.id)"
            guard defaults.bool(forKey: spendTrackingKey) else { continue }
            let amount = defaults.integer(forKey: spendAmountKey)
            guard amount > 0 else {
                defaults.removeObject(forKey: spendTrackingKey)
                defaults.removeObject(forKey: spendAmountKey)
                continue
            }
            AppLogger.shield.debug("📡 Syncing widget spend tracking: \(group.name) \(amount) colors")
            addSpentSteps(amount, for: "group_\(group.id)")
            defaults.removeObject(forKey: spendTrackingKey)
            defaults.removeObject(forKey: spendAmountKey)
        }
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
        g.removeObject(forKey: SharedKeys.shouldShowPayGate)
        g.removeObject(forKey: SharedKeys.payGateTargetGroupId)
        g.removeObject(forKey: SharedKeys.payGateTargetBundleId)
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

        let url = PersistenceManager.paymentTransactionsFileURL
        var transactions: [PaymentTransaction] = []

        if (try? url.checkResourceIsReachable()) == true, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PaymentTransaction].self, from: data) {
            transactions = decoded
        } else {
            let defaults = UserDefaults.stepsTrader()
            if let data = defaults.data(forKey: "paymentTransactions_v1"),
               let decoded = try? JSONDecoder().decode([PaymentTransaction].self, from: data) {
                transactions = decoded
                if let fileData = try? JSONEncoder().encode(decoded) {
                    try? fileData.write(to: url, options: .atomic)
                }
                defaults.removeObject(forKey: "paymentTransactions_v1")
            }
        }

        transactions.append(transaction)
        if transactions.count > 1000 {
            transactions = Array(transactions.suffix(1000))
        }

        if let data = try? JSONEncoder().encode(transactions) {
            try? data.write(to: url, options: .atomic)
            AppLogger.shield.debug("📝 Logged payment transaction: \(amount) for \(target) (balance: \(balanceBefore) → \(balanceAfter))")
        }
    }
    
}
