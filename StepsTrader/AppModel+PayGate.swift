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
    // MARK: - PayGate Opening
    func openPayGate(for groupId: String) {
        // Clear any stale error from a previous failed attempt — fresh session = fresh slate.
        payGateError = nil
        startPayGateSession(for: groupId)
    }
    
    @MainActor
    func startPayGateSession(for groupId: String) {
        if showPayGate, payGateTargetGroupId == groupId { return }

        let g = UserDefaults.stepsTrader()
        if !showPayGate,
           let until = g.object(forKey: SharedKeys.payGateDismissedUntil) as? Date,
           Date.now < until
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
        g.set(Date.now, forKey: SharedKeys.lastGroupPayGateOpen(groupId))

        // Create session
        let session = PayGateSession(id: groupId, groupId: groupId, startedAt: Date.now)
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
        defaults.set(Date.now, forKey: startedKey)

        let dayEndH = defaults.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndM = defaults.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let endOfDay = DayBoundary.nextBoundary(after: Date.now, dayEndHour: dayEndH, dayEndMinute: dayEndM)
        defaults.set(endOfDay, forKey: SharedKeys.usageBudgetExpiryKey(groupId))

        let monitoringStarted = startUsageBudgetMonitoring(groupId: groupId, minutes: totalMinutes)
        if !monitoringStarted {
            // DeviceActivity wouldn't start — refund the colors, clear the keys, and
            // surface a user-visible error before dismissing. Otherwise the user just
            // sees the balance bounce back with no explanation and assumes the
            // purchase silently failed. (§5.1)
            AppLogger.shield.error("❌ Monitoring failed after payment — refunding \(cost) colors")
            refund(cost: cost)
            defaults.removeObject(forKey: budgetKey)
            defaults.removeObject(forKey: initialKey)
            defaults.removeObject(forKey: startedKey)
            defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
            payGateError = String(
                localized: "Couldn't start the timer. Your colors were refunded — please try again in a moment.",
                comment: "PayGate – DeviceActivity monitoring failure, after refund"
            )
            dismissPayGate(reason: .programmatic)
            return
        }
        
        // NOTE: addSpentSteps records full `cost` (base + bonus) in per-app/per-day
        // dictionaries for analytics. This differs from spentStepsToday (set in pay())
        // which only tracks base-energy consumption. Both are intentional:
        // per-app = "total cost of this group", spentStepsToday = "base energy used".
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

    @discardableResult
    private func startUsageBudgetMonitoring(groupId: String, minutes: Int) -> Bool {
        let logDefaults = UserDefaults.stepsTrader()
        let iso = ISO8601DateFormatter()

        #if !canImport(DeviceActivity) || !canImport(FamilyControls)
        logDefaults.set("[\(iso.string(from: Date.now))] SKIP usageBudget_\(groupId) — DeviceActivity/FamilyControls not available", forKey: SharedKeys.lastStartMonitoringLog)
        return true
        #else
        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            logDefaults.set("[\(iso.string(from: Date.now))] SKIP usageBudget_\(groupId) — group not found", forKey: SharedKeys.lastStartMonitoringLog)
            return false
        }

        let center = DeviceActivityCenter()
        let activityName = DeviceActivityName("usageBudget_\(groupId)")

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]

        // Per-minute ticks so the in-app display updates every minute of actual usage
        for m in 1..<minutes {
            let tickName = DeviceActivityEvent.Name("usageBudgetTick_\(groupId)_\(m)")
            events[tickName] = DeviceActivityEvent(
                applications: group.selection.applicationTokens,
                categories: group.selection.categoryTokens,
                threshold: DateComponents(minute: m)
            )
        }

        // Widget milestone ticks at 25/50/75/90% — only these trigger widget reloads
        let widgetMilestoneFractions: [Double] = [0.25, 0.50, 0.75, 0.90]
        var seenWidgetMinutes = Set<Int>()
        for frac in widgetMilestoneFractions {
            let m = Int(Double(minutes) * frac)
            guard m >= 1, m < minutes, !seenWidgetMinutes.contains(m) else { continue }
            seenWidgetMinutes.insert(m)
            let widgetTickName = DeviceActivityEvent.Name("usageBudgetWidgetTick_\(groupId)_\(m)")
            events[widgetTickName] = DeviceActivityEvent(
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

        // Use a non-wrapping 0:0:0–23:59:59 schedule. The previous day-boundary-aligned
        // schedule (e.g. start=1:0:0 end=0:59:59) wraps around midnight; DeviceActivity
        // interprets end < start as "already ended" and fires intervalDidEnd immediately,
        // killing the monitor before any usage events can fire. Custom day boundary resets
        // are handled separately by clearAllUsageBudgets.
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )

        // Start-first pattern: avoid calling stopMonitoring before startMonitoring because
        // stopMonitoring generates an async intervalDidEnd callback that can arrive AFTER
        // the new startMonitoring's intervalDidStart, creating a race condition.
        // handlePayGatePaymentForGroup already stops the existing monitor when extending.
        let schedDesc = "start=0:0:0 end=23:59:59"
        do {
            try center.startMonitoring(activityName, during: schedule, events: events)
            let msg = "[\(iso.string(from: Date.now))] OK usageBudget_\(groupId) \(minutes)m events=\(events.count) apps=\(group.selection.applicationTokens.count) sched=[\(schedDesc)] activities=\(center.activities.map(\.rawValue))"
            logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
            return true
        } catch {
            center.stopMonitoring([activityName])
            do {
                try center.startMonitoring(activityName, during: schedule, events: events)
                let msg = "[\(iso.string(from: Date.now))] OK (retry) usageBudget_\(groupId) \(minutes)m events=\(events.count) apps=\(group.selection.applicationTokens.count) sched=[\(schedDesc)] activities=\(center.activities.map(\.rawValue))"
                logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
                return true
            } catch {
                let msg = "[\(iso.string(from: Date.now))] FAIL usageBudget_\(groupId) — \(error.localizedDescription) sched=[\(schedDesc)]"
                logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
                return false
            }
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
            var minutes = defaults.integer(forKey: minutesKey)
            guard minutes > 0 else {
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }
            var budgetInPrefs = defaults.integer(forKey: SharedKeys.usageBudgetKey(group.id))
            guard budgetInPrefs > 0 else {
                AppLogger.shield.debug("📡 Dropping stale widget pending for \(group.name) — no usageBudget in prefs (extension cleared keys?)")
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                continue
            }

            // Wall-clock correction: the widget set the budget N minutes ago but couldn't
            // start DeviceActivity monitoring. Subtract elapsed time so the budget is accurate.
            if let started = defaults.object(forKey: SharedKeys.usageBudgetStartedKey(group.id)) as? Date {
                let elapsedMinutes = Int(Date.now.timeIntervalSince(started) / 60)
                if elapsedMinutes > 0 {
                    minutes = max(0, minutes - elapsedMinutes)
                    budgetInPrefs = max(0, budgetInPrefs - elapsedMinutes)
                    defaults.set(budgetInPrefs, forKey: SharedKeys.usageBudgetKey(group.id))
                    defaults.set(minutes, forKey: SharedKeys.usageBudgetInitialKey(group.id))
                    AppLogger.shield.debug("📡 Wall-clock correction for widget budget \(group.name): elapsed \(elapsedMinutes)m, adjusted to \(minutes)m")
                }
            }

            guard minutes > 0, budgetInPrefs > 0 else {
                AppLogger.shield.debug("📡 Widget budget fully elapsed for \(group.name) after wall-clock correction — clearing")
                defaults.removeObject(forKey: pendingKey)
                defaults.removeObject(forKey: minutesKey)
                clearUsageBudgetPrefsForGroup(group.id)
                continue
            }

            AppLogger.shield.debug("📡 Starting DeviceActivity monitoring for widget-initiated budget: \(group.name) \(minutes)m")
            startUsageBudgetMonitoring(groupId: group.id, minutes: minutes)
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: minutesKey)
        }

        for group in ticketGroups {
            let spendTrackingKey = SharedKeys.pendingSpendTrackingKey(group.id)
            let spendAmountKey = SharedKeys.pendingSpendAmountKey(group.id)
            let spendWindowKey = SharedKeys.pendingSpendWindowKey(group.id)
            let spendMinutesKey = SharedKeys.pendingSpendMinutesKey(group.id)
            guard defaults.bool(forKey: spendTrackingKey) else { continue }
            let amount = defaults.integer(forKey: spendAmountKey)
            guard amount > 0 else {
                defaults.removeObject(forKey: spendTrackingKey)
                defaults.removeObject(forKey: spendAmountKey)
                defaults.removeObject(forKey: spendWindowKey)
                defaults.removeObject(forKey: spendMinutesKey)
                continue
            }
            AppLogger.shield.debug("📡 Syncing widget spend tracking: \(group.name) \(amount) colors")
            addSpentSteps(amount, for: "group_\(group.id)")

            let window = defaults.string(forKey: spendWindowKey).flatMap { AccessWindow(rawValue: $0) }
            let pendingMinutes = defaults.integer(forKey: spendMinutesKey)
            logPaymentTransaction(
                amount: amount,
                target: "group_\(group.id)",
                targetName: group.name,
                window: window,
                minutes: pendingMinutes > 0 ? pendingMinutes : nil,
                balanceBefore: self.totalStepsBalance + amount,
                balanceAfter: self.totalStepsBalance
            )

            defaults.removeObject(forKey: spendTrackingKey)
            defaults.removeObject(forKey: spendAmountKey)
            defaults.removeObject(forKey: spendWindowKey)
            defaults.removeObject(forKey: spendMinutesKey)
        }
    }

    /// Stops `usageBudget_*` DeviceActivity names when UserDefaults has no active budget for that group.
    /// Orphans appear when prefs were cleared (e.g. `usageBudgetDone`) but stopMonitoring failed,
    /// or pending-widget handoff started monitoring without matching prefs.
    func reconcileOrphanUsageBudgetMonitors() {
        #if canImport(DeviceActivity)
        let center = DeviceActivityCenter()
        let defaults = UserDefaults.stepsTrader()
        let prefix = "usageBudget_"
        var toStop: [DeviceActivityName] = []
        for activity in center.activities {
            let raw = activity.rawValue
            guard raw.hasPrefix(prefix) else { continue }
            let groupId = String(raw.dropFirst(prefix.count))
            if defaults.integer(forKey: SharedKeys.usageBudgetKey(groupId)) <= 0 {
                toStop.append(activity)
            }
        }
        guard !toStop.isEmpty else { return }
        center.stopMonitoring(toStop)
        AppLogger.shield.debug("🧹 Stopped orphan usageBudget monitor(s): \(toStop.map(\.rawValue).joined(separator: ", "))")
        #endif
    }

    /// After `intervalDidEnd` stops monitors without clearing prefs, restart DeviceActivity for any group
    /// that still has budget + valid wall clock but no registered `usageBudget_*` activity.
    func ensureUsageBudgetMonitoringForActiveGroups() {
        #if canImport(DeviceActivity) && canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        let center = DeviceActivityCenter()
        for group in ticketGroups {
            let gid = group.id
            var remaining = defaults.integer(forKey: SharedKeys.usageBudgetKey(gid))
            if remaining <= 0 { continue }

            if !ShieldRebuildHelper.isUsageBudgetWallClockActive(defaults: defaults, groupId: gid) {
                AppLogger.shield.debug("🧹 Clearing expired wall-clock usage budget for \(group.name)")
                clearUsageBudgetPrefsForGroup(gid)
                continue
            }

            let activityName = DeviceActivityName("usageBudget_\(gid)")
            if center.activities.contains(activityName) { continue }

            // Wall-clock correction: DeviceActivity wasn't running (e.g. monitor lost
            // after intervalDidEnd race, or widget unlock before app foregrounded).
            // Subtract elapsed wall-clock minutes so the budget reflects real time passed.
            if let started = defaults.object(forKey: SharedKeys.usageBudgetStartedKey(gid)) as? Date {
                let elapsedMinutes = Int(Date.now.timeIntervalSince(started) / 60)
                if elapsedMinutes > 0 {
                    remaining = max(0, remaining - elapsedMinutes)
                    defaults.set(remaining, forKey: SharedKeys.usageBudgetKey(gid))
                    AppLogger.shield.debug("🔁 Wall-clock correction for \(group.name): elapsed \(elapsedMinutes)m, adjusted remaining to \(remaining)m")
                }
            }

            guard remaining > 0 else {
                AppLogger.shield.debug("🔁 Budget fully elapsed for \(group.name) after wall-clock correction — clearing")
                clearUsageBudgetPrefsForGroup(gid)
                continue
            }

            defaults.set(remaining, forKey: SharedKeys.usageBudgetInitialKey(gid))
            AppLogger.shield.debug("🔁 Resuming usageBudget monitor for \(group.name) (\(remaining)m)")
            startUsageBudgetMonitoring(groupId: gid, minutes: remaining)
        }
        #endif
    }

    private func clearUsageBudgetPrefsForGroup(_ groupId: String) {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        #if canImport(DeviceActivity)
        DeviceActivityCenter().stopMonitoring([DeviceActivityName("usageBudget_\(groupId)")])
        #endif
    }

    
    // MARK: - PayGate Dismissal
    func dismissPayGate(reason: PayGateDismissReason = .userDismiss) {
        showPayGate = false
        payGateTargetGroupId = nil
        payGateSessions.removeAll()
        currentPayGateSessionId = nil
        let g = UserDefaults.stepsTrader()
        let now = Date.now
        if reason == .userDismiss {
            // Cooldown to prevent instant re-open loops when the user dismisses PayGate.
            g.set(now.addingTimeInterval(10), forKey: SharedKeys.payGateDismissedUntil)
            g.set(now, forKey: SharedKeys.lastPayGateAction)
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
        let minutes: Int?
        let balanceBefore: Int
        let balanceAfter: Int
    }

    private func logPaymentTransaction(amount: Int, target: String, targetName: String?, window: AccessWindow?, minutes: Int? = nil, balanceBefore: Int, balanceAfter: Int) {
        let transaction = PaymentTransaction(
            id: UUID().uuidString,
            timestamp: Date.now,
            amount: amount,
            target: target,
            targetName: targetName,
            window: window?.rawValue,
            minutes: minutes ?? window?.minutes,
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
