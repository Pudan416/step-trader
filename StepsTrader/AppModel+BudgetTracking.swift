import Foundation

// MARK: - Budget & Day Management
extension AppModel {
    /// Public entry point for changing the custom day-end time from Settings.
    ///
    /// The settings pickers can emit this rapidly (one call per picker step, plus
    /// an extra call from `sync*FromStorage` on appear), so the real work is
    /// debounced into a single `commitDayEnd`. Critically, a day-end change must
    /// NOT reset the current day's economy: the old implementation called
    /// `checkDayBoundary()` here, which — because changing the boundary shifts the
    /// computed day key — was treated as a rollover and wiped `spentStepsToday`,
    /// selections, base energy, the canvas, and active usage budgets. That was
    /// both a data-loss bug and an exploit (toggling the setting refunded spent
    /// colors → free unlocks). We now re-anchor the current day in place instead.
    func updateDayEnd(hour: Int, minute: Int) {
        let clampedHour = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))
        // No-op guard: nothing changed → don't churn timers/sync/anchor.
        if clampedHour == dayEndHour && clampedMinute == dayEndMinute { return }

        dayEndCommitTask?.cancel()
        dayEndCommitTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.commitDayEnd(hour: clampedHour, minute: clampedMinute)
        }
    }

    /// Atomically apply a new day-end: update the in-memory + persisted boundary,
    /// re-anchor the current day (preserving progress), then reschedule the
    /// boundary timer + day-reset warning and sync preferences.
    private func commitDayEnd(hour: Int, minute: Int) {
        // Re-check: the value may have settled back to the current one across the
        // debounce window.
        if hour == dayEndHour && minute == dayEndMinute { return }

        dayEndHour = hour
        dayEndMinute = minute
        // Persists SharedKeys.dayEndHour/Minute to the App Group (the single
        // day-end writer), so storedDayEnd()/dayKey(for:) immediately observe the
        // new boundary. budgetEngine.updateDayEnd also runs a non-destructive
        // resetIfNeeded internally.
        budgetEngine.updateDayEnd(hour: hour, minute: minute)

        reanchorForDayEndChange()

        scheduleDayBoundaryTimer()
        syncUserPreferencesToSupabase()
        (notificationService as? NotificationManager)?
            .scheduleDayResetWarning(dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }

    /// Move the daily anchor to the new day-start WITHOUT resetting progress.
    ///
    /// Changing the day-end shifts where "today" begins, which can make
    /// `dayKey(for: .now)` differ from the stored anchor's day key while the user
    /// is still within the same calendar session. Letting `checkDayBoundary` see
    /// that as a rollover would wipe spent/earned state and usage budgets. Instead
    /// we re-stamp the anchors and `lastDayKey` to the new boundary, keep all
    /// economy state intact, and extend any live usage-budget expiries so a
    /// running unlock isn't cut short (or orphaned past) the new day-end.
    private func reanchorForDayEndChange() {
        let g = UserDefaults.stepsTrader()
        let now = Date.now
        let newDayStart = currentDayStart(for: now)

        g.set(newDayStart, forKey: SharedKeys.dailyEnergyAnchor)
        g.set(newDayStart, forKey: SharedKeys.stepsBalanceAnchor)
        lastDayKey = Self.dayKey(for: now)

        let newExpiry = DayBoundary.nextBoundary(
            after: now,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute
        )
        for group in ticketGroups where g.integer(forKey: SharedKeys.usageBudgetKey(group.id)) > 0 {
            g.set(newExpiry, forKey: SharedKeys.usageBudgetExpiryKey(group.id))
        }

        // Recompute balance + widgets from the preserved state. spentStepsToday,
        // selections, base energy and the canvas are all left untouched.
        recalculateDailyEnergy()
    }
}
