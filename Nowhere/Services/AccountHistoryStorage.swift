import Foundation

/// Explicit scope shared by the account transition and local legacy viewer.
/// Lock files, credentials, device wallpaper and diagnostics are excluded.
enum AccountHistoryStorage {
    static var rootDirectory: URL {
        applicationDirectory.appendingPathComponent("account-history", isDirectory: true)
    }

    static var hasLegacyArchive: Bool {
        let name = AccountHistoryVault.legacyOwner.utf8.map { String(format: "%02x", $0) }.joined() + ".plist"
        return FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent(name).path)
    }

    private static var applicationDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent(Bundle.main.bundleIdentifier ?? "StepsTrader", isDirectory: true)
    }

    /// Construction for read-only access never runs working-set recovery.
    /// `activate` performs recovery later inside the coordinator's writer locks.
    static func makeVault() throws -> AccountHistoryVault {
        let keys: Set<String> = [
            SharedKeys.dayEndHour, SharedKeys.dayEndMinute,
            SharedKeys.dailyEnergyAnchor, SharedKeys.dailySleepHours, SharedKeys.baseEnergyToday,
            SharedKeys.restDayOverrideEnabled, SharedKeys.stepsBalance, SharedKeys.spentStepsToday,
            SharedKeys.bonusSteps, SharedKeys.cachedStepsToday, SharedKeys.stepsBalanceAnchor,
            SharedKeys.hasStepsData, "cachedSleepHoursToday",
            SharedKeys.dailyBudgetMinutes, SharedKeys.remainingMinutes, SharedKeys.todayAnchor, SharedKeys.selectedTariff,
            SharedKeys.ticketGroups, SharedKeys.legacyShieldGroups, SharedKeys.liteTicketConfig,
            SharedKeys.appUnlockSettings, SharedKeys.appSelection, SharedKeys.appSelectionSavedDate,
            SharedKeys.appStepsSpentToday, SharedKeys.appStepsSpentLifetime, SharedKeys.appStepsSpentByDay, SharedKeys.appDayPassGrants,
            SharedKeys.happeningCatalog, SharedKeys.happeningPaletteSelection, SharedKeys.legacyHappeningPaletteOrderIds,
            SharedKeys.happeningFrequentPalette, SharedKeys.happeningShapeNonce, SharedKeys.happeningShapeNonceDayKey,
            SharedKeys.todayAdditions, SharedKeys.customEnergyOptions, SharedKeys.pastDaySnapshots,
            SharedKeys.dailyCanvasSlots, SharedKeys.savedRoutines, SharedKeys.dailyMoments,
            SharedKeys.userStepsTarget, SharedKeys.userSleepTarget, SharedKeys.hasCompletedInitialRestore,
            SharedKeys.gradientStyle, SharedKeys.gradientPalette, SharedKeys.userGradientStyle, SharedKeys.userGradientPalette,
            SharedKeys.dailyRandomThemeEnabled, SharedKeys.dailyRandomThemeLastRolledKey, SharedKeys.modernPaletteCategories,
            SharedKeys.canvasVisualStyle, SharedKeys.canvasVisualStyleMigrationVersion, SharedKeys.canvasOverlayStyle,
            SharedKeys.canvasTexture, SharedKeys.bodyCanvasShape, SharedKeys.mindCanvasShape, SharedKeys.heartCanvasShape,
            SharedKeys.allowedCanvasShapes, SharedKeys.allowedCanvasFills,
            SharedKeys.notifyOneMinBefore, SharedKeys.notifyWhenTimerOver, SharedKeys.notifyCanvasReminder,
            SharedKeys.canvasReminderHour, SharedKeys.canvasReminderMinute, SharedKeys.notifyDayResetWarning,
            SharedKeys.dayResetWarningHours, SharedKeys.notifyActivityDetected,
            SharedKeys.eveningReflectionDismissedDay, SharedKeys.eveningReflectionRequestedAt,
            SharedKeys.readNoteIDs, SupabaseSyncService.retryQueueKey, SupabaseSyncService.optionEntryIntentKey,
            SharedKeys.analyticsEventsQueue
        ]
        let prefixes = [
            "dailyEnergySelections_v1_", "preferredEnergyOptions_v1_", "timeAccessSelection_v1_",
            "minuteCount_", "lastAppOpenedFromStepsTrader_", "usageBudget_", "usageBudgetStarted_",
            "usageBudgetInitial_", "usageBudgetExpiry_", "usageBudgetSession_v2_", "lastGroupPayGateOpen_",
            SharedKeys.pendingBudgetMonitoringPrefix, SharedKeys.pendingBudgetMinutesPrefix,
            "pendingSpendAmount_", "pendingSpendTracking_", "pendingSpendWindow_", "pendingSpendMinutes_",
            "widgetUnlockCapability_v1_", "appName_", "fc_appName_", "fc_bundleId_", "fc_groupId_"
        ]
        var locations: [AccountHistoryVault.Location] = [
            .init(name: "canvases", url: applicationDirectory.appendingPathComponent("canvases"), isDirectory: true),
            .init(name: "snapshots", url: URL.documentsDirectory.appendingPathComponent("canvas_snapshots"), isDirectory: true)
        ]
        for name in ["pastDaySnapshots", "paymentTransactions", "appStepsSpentByDay", "appStepsSpentLifetime"] {
            locations.append(.init(name: name, url: applicationDirectory.appendingPathComponent(name + ".json")))
        }
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId) {
            // Wallpaper files in the same directory are device settings and
            // have an independent AppIntent writer; rotate only this preview.
            locations.append(.init(name: "widgetCanvas", url: group.appendingPathComponent("widget_snapshots/canvas_today.jpg")))
        }
        return try AccountHistoryVault(root: rootDirectory, domains: [
            .init(defaults: .nowhere(), keys: keys, keyPrefixes: prefixes),
            .init(defaults: .standard, keys: keys, keyPrefixes: prefixes)
        ], locations: locations, recoverWorkingSet: false)
    }
}
