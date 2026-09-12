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
        let artwork = GateArtworkStore(defaults: g).takeHandoff(for: groupId) ?? .random()
        let session = PayGateSession(id: groupId, groupId: groupId, startedAt: Date.now, artwork: artwork)
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
    /// How long a shield-tap unlock request stays actionable.
    ///
    /// Long enough to survive a push the user notices a few minutes late, short enough
    /// that abandoning the tap does not ambush them the next time they open the app.
    static let payGateRequestMaxAge: TimeInterval = 15 * 60

    /// `payGateRequestedAt` has been written by both ShieldAction and NotificationDelegate
    /// since the flag was introduced, and read by nobody — so a tap the user walked away
    /// from still opened the PayGate days later, on top of whatever they had actually
    /// opened the app to do.
    ///
    /// A missing timestamp counts as fresh, so flags written before this rule existed
    /// still work once. A timestamp in the future counts as fresh too: that means the
    /// clock moved backwards, not that the request is stale.
    static func isPayGateRequestFresh(requestedAt: Date?, now: Date = Date()) -> Bool {
        guard let requestedAt else { return true }
        return now.timeIntervalSince(requestedAt) <= payGateRequestMaxAge
    }

    @MainActor
    @discardableResult
    func handlePayGatePaymentForGroup(groupId: String, window: AccessWindow, costOverride: Int?) async -> Bool {
        // Checked before anything else, including whether the group exists: without
        // Screen Time access every ManagedSettingsStore write below is inert, so the
        // purchase cannot succeed no matter what else is true. The cached flag only
        // refreshes on foreground and revocation arrives without notice, so re-read it
        // rather than trusting it.
        familyControlsService.refreshAuthorizationStatus()
        guard familyControlsService.isAuthorized else {
            AppLogger.shield.error("❌ PayGate: Screen Time access missing — refusing before charging")
            payGateError = UsageBudgetMonitoringError.notAuthorized.userFacingMessage
            dismissPayGate(reason: .programmatic)
            return false
        }

        guard let group = ticketGroups.first(where: { $0.id == groupId }) else {
            AppLogger.shield.debug("⚠️ PayGate: Group \(groupId) not found for payment")
            return false
        }
        
        // A paid continuation that could not register is resumed before a new
        // charge. Never turn recovery into another purchase.
        let store = UserDefaults.stepsTrader()
        if ShieldRebuildHelper.hasRecoverableUsageBudget(defaults: store, groupId: groupId),
           let session = UsageBudgetSession.load(from: store, groupId: groupId) {
            if let failure = startUsageBudgetMonitoring(groupId: groupId, minutes: session.remainingMinutes) {
                payGateError = failure.userFacingMessage
                dismissPayGate(reason: .programmatic)
                return false
            }
            ShieldRebuildHelper.rebuild()
            rebuildFamilyControlsShield()
            dismissPayGate(reason: .programmatic)
            return true
        }

        let cost = costOverride ?? group.cost(for: window)
        let minutes = window.minutes
        
        AppLogger.shield.debug("💰 Attempting to pay \(cost) colors for \(minutes) min (usage budget) for group \(group.name)")
        
        guard pay(cost: cost) else {
            AppLogger.shield.debug("❌ Payment failed - not enough colors")
            return false
        }
        
        AppLogger.shield.debug("✅ Payment successful! New balance: \(self.totalStepsBalance)")
        
        let defaults = UserDefaults.stepsTrader()
        do {
            try ShieldRebuildHelper.purchaseUsageBudget(defaults: defaults, groupId: groupId, minutes: minutes)
        } catch {
            refund(cost: cost)
            payGateError = UsageBudgetMonitoringError.classify(error).userFacingMessage
            dismissPayGate(reason: .programmatic)
            return false
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
        return true
    }

    /// Returns nil only after the usage thresholds has been registered.
    @discardableResult
    private func startUsageBudgetMonitoring(groupId: String, minutes: Int) -> UsageBudgetMonitoringError? {
        #if canImport(DeviceActivity) && canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        do {
            try ShieldRebuildHelper.startUsageBudgetMonitoring(defaults: defaults, groupId: groupId)
            defaults.set("OK usage thresholds usageBudget_\(groupId), \(minutes)m", forKey: SharedKeys.lastStartMonitoringLog)
            return nil
        } catch {
            defaults.set("FAIL usage thresholds usageBudget_\(groupId): \(error.localizedDescription)", forKey: SharedKeys.lastStartMonitoringLog)
            return UsageBudgetMonitoringError.classify(error)
        }
        #else
        return .other("Device Activity is unavailable")
        #endif
    }

    // MARK: - Pending Widget Budget Monitoring

    func startPendingWidgetBudgetMonitoring() {
        let defaults = UserDefaults.stepsTrader()
        ShieldRebuildHelper.startPendingWidgetBudgets()

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
    /// that still has budget valid for this custom day but no registered `usageBudget_*` activity.
    func ensureUsageBudgetMonitoringForActiveGroups() {
        #if canImport(DeviceActivity) && canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()
        let center = DeviceActivityCenter()
        for group in ticketGroups {
            let gid = group.id
            guard defaults.integer(forKey: SharedKeys.usageBudgetKey(gid)) > 0 else { continue }
            let remaining = ShieldRebuildHelper.remainingUsageBudget(defaults: defaults, groupId: gid)
            guard remaining > 0,
                  let expiry = ShieldRebuildHelper.usageBudgetDeadline(defaults: defaults, groupId: gid),
                  let desired = ShieldRebuildHelper.usageBudgetSchedule(endingAt: expiry) else {
                clearUsageBudgetPrefsForGroup(gid)
                continue
            }
            let name = DeviceActivityName("usageBudget_\(gid)")
            if let current = center.schedule(for: name),
               !current.repeats, current.intervalEnd == desired.intervalEnd,
               let session = UsageBudgetSession.load(from: defaults, groupId: gid),
               !session.needsNextSegment, !session.monitoringFailed,
               ShieldRebuildHelper.usageSelectionMatches(defaults: defaults, groupId: gid, session: session),
               center.events(for: name)[DeviceActivityEvent.Name(session.eventName(minute: session.initialMinutes))] != nil {
                continue
            }
            // Do not replace a healthy monitor on app launch: Apple's partial
            // usage lives there. Recover only absent/obsolete registrations.
            if let failure = startUsageBudgetMonitoring(groupId: gid, minutes: remaining) {
                payGateError = failure.userFacingMessage
            }
        }
        #endif
    }

    private func clearUsageBudgetPrefsForGroup(_ groupId: String) {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.usageBudgetKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(groupId))
        defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
        defaults.removeObject(forKey: UsageBudgetSession.key(groupId))
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
