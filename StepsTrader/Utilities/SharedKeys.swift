import Foundation
import os.log
import WidgetKit

// MARK: - Widget Data File (bypasses UserDefaults caching)

struct WidgetSnapshot: Codable {
    let balance: Int
    let earned: Int
    let stepsPoints: Int
    let sleepPoints: Int
    let bodyPoints: Int
    let mindPoints: Int
    let heartPoints: Int
    let timestamp: Date
}

enum WidgetDataFile {
    private static var fileURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        )?.appendingPathComponent("widget_data.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}

/// Single source of truth for all UserDefaults and App Group keys.
/// Shared across the main app and extensions (ShieldAction, ShieldConfiguration, DeviceActivityMonitor).
enum SharedKeys {
    static let appGroupId = "group.personal-project.StepsTrader"
    static func appGroupDefaults() -> UserDefaults {
        if let defaults = UserDefaults(suiteName: appGroupId) {
            return defaults
        }
        #if DEBUG
        assertionFailure("App Group container '\(appGroupId)' unavailable — check entitlements")
        #endif
        Logger(subsystem: "com.personalproject.StepsTrader", category: "SharedKeys").error("appGroupDefaults(): App Group container '\(appGroupId)' unavailable, falling back to .standard")
        return .standard
    }

    // MARK: - Day boundary
    static let dayEndHour = "dayEndHour_v1"
    static let dayEndMinute = "dayEndMinute_v1"

    // MARK: - Energy / steps
    static let dailyEnergyAnchor = "dailyEnergyAnchor_v1"
    static let dailySleepHours = "dailySleepHours_v1"
    static let baseEnergyToday = "baseEnergyToday_v1"
    static let restDayOverrideEnabled = "restDayOverrideEnabled_v1"
    static let stepsBalance = "stepsBalance"
    static let spentStepsToday = "spentStepsToday"
    static let bonusSteps = "debugStepsBonus_v1"
    static let cachedStepsToday = "cachedStepsToday"
    static let stepsBalanceAnchor = "stepsBalanceAnchor"

    // MARK: - Budget
    static let dailyBudgetMinutes = "dailyBudgetMinutes"
    static let remainingMinutes = "remainingMinutes"
    static let todayAnchor = "todayAnchor"
    static let selectedTariff = "selectedTariff"

    // MARK: - Ticket groups
    static let ticketGroups = "ticketGroups_v1"
    static let legacyShieldGroups = "shieldGroups_v1"
    static let liteTicketConfig = "liteTicketConfig_v1"
    static let appUnlockSettings = "appUnlockSettings_v1"

    // MARK: - Shield state
    static let shieldState = "doomShieldState_v1"
    static let shieldActionLogs = "shieldActionLogs_v1"
    static let lastBlockedAppBundleId = "lastBlockedAppBundleId"
    static let lastBlockedGroupId = "lastBlockedGroupId"

    // MARK: - PayGate
    static let shouldShowPayGate = "shouldShowPayGate"
    static let payGateTargetGroupId = "payGateTargetGroupId"
    static let payGateTargetBundleId = "payGateTargetBundleId_v1"
    static let payGateRequestedAt = "payGateRequestedAt_v1"
    static let payGateDismissedUntil = "payGateDismissedUntil_v1"
    static let lastPayGateAction = "lastPayGateAction"
    static let blockedPaygateBundleId = "blockedPaygateBundleId"
    static let blockedPaygateTimestamp = "blockedPaygateTimestamp"

    // MARK: - Spend tracking
    static let appStepsSpentToday = "appStepsSpentToday_v1"
    static let appStepsSpentLifetime = "appStepsSpentLifetime_v1"
    static let appStepsSpentByDay = "appStepsSpentByDay_v1"
    static let appDayPassGrants = "appDayPassGrants_v1"

    // MARK: - Notification preferences
    static let notifyOneMinBefore = "notifyOneMinBefore_v1"
    static let notifyWhenTimerOver = "notifyWhenTimerOver_v1"
    static let notifyCanvasReminder = "notifyCanvasReminder_v1"
    static let canvasReminderHour = "canvasReminderHour_v1"
    static let canvasReminderMinute = "canvasReminderMinute_v1"
    static let notifyActivityDetected = "notifyActivityDetected_v1"
    static let notifyDayResetWarning = "notifyDayResetWarning_v1"
    static let dayResetWarningHours = "dayResetWarningHours_v1"

    // MARK: - Appearance
    static let gradientStyle = "gradientStyle_v1"
    static let gradientPalette = "gradientPalette_v1"

    // MARK: - Widget
    static let widgetBackgroundMode = "widgetBackgroundMode_v1"
    static let hasMediumWidget = "hasMediumWidget_v1"
    static let hasLargeWidget = "hasLargeWidget_v1"

    // MARK: - Selections / canvas
    static let appSelection = "appSelection_v1"
    static let appSelectionSavedDate = "appSelectionSavedDate"
    static let customEnergyOptions = "customEnergyOptions_v1"
    static let pastDaySnapshots = "pastDaySnapshots_v1"
    static let dailyCanvasSlots = "dailyChoiceSlots_v1"
    static let userStepsTarget = "userStepsTarget"
    static let userSleepTarget = "userSleepTarget"

    // MARK: - Monitor (DeviceActivityMonitor extension)
    static let monitorLogs = "monitorLogs_v1"
    static let monitorErrorLogs = "monitorErrorLogs_v1"
    static let monitorErrorCount = "monitorErrorCount_v1"
    static let monitorLastErrorAt = "monitorLastErrorAt_v1"

    // MARK: - Shield diagnostics (written by app, extension, and BGTask)
    static let shieldDiagLastRebuild = "shieldDiag_lastRebuild_v1"
    static let shieldDiagHistory = "shieldDiag_history_v1"
    static let lastStartMonitoringLog = "shieldDiag_lastStartMonitoring_v1"
    static let extensionTestScheduledAt = "shieldDiag_extTestScheduledAt_v1"

    // MARK: - Automation / handoff
    static let handoffToken = "handoffToken"
    static let automationConfiguredBundles = "automationConfiguredBundles"
    static let automationBundleId = "automationBundleId"
    static let automationPendingBundles = "automationPendingBundles"
    static let automationLastOpened = "automationLastOpened_v1"
    static let automationPendingTimestamps = "automationPendingTimestamps_v1"
    static let selectedAppScheme = "selectedAppScheme"

    // MARK: - Supabase / CloudKit
    static let supabaseTodayCacheTTLSeconds = "supabaseTodayCacheTTLSeconds_v1"
    static let supabaseHistoryPageSize = "supabaseHistoryPageSize_v1"
    static let supabaseHistoryRefreshTTLSeconds = "supabaseHistoryRefreshTTLSeconds_v1"
    static let analyticsEventsQueue = "analyticsEventsQueue_v1"
    static let cloudkitLastSync = "cloudkit_lastSync"

    // MARK: - Steps data
    static let hasStepsData = "hasStepsData_v1"

    // MARK: - Notes (app-only)
    static let readNoteIDs = "readNoteIDs_v1"

    // MARK: - Legacy shield config
    static let liteShieldConfig = "liteShieldConfig_v1"

    // MARK: - Helpers (parameterized)
    static func timeAccessSelectionKey(_ bundleId: String) -> String { "timeAccessSelection_v1_\(bundleId)" }
    static func dailySelectionsKey(_ category: String) -> String { "dailyEnergySelections_v1_\(category)" }
    static func preferredOptionsKey(_ category: String) -> String { "preferredEnergyOptions_v1_\(category)" }
    static func minuteCountKey(dayKey: String, bundleId: String) -> String { "minuteCount_\(dayKey)_\(bundleId)" }
    static func lastAppOpenedFromStepsTrader(_ bundleId: String) -> String { "lastAppOpenedFromStepsTrader_\(bundleId)" }
    static func usageBudgetKey(_ groupId: String) -> String { "usageBudget_\(groupId)" }
    static func usageBudgetStartedKey(_ groupId: String) -> String { "usageBudgetStarted_\(groupId)" }
    static func usageBudgetInitialKey(_ groupId: String) -> String { "usageBudgetInitial_\(groupId)" }
    static func usageBudgetExpiryKey(_ groupId: String) -> String { "usageBudgetExpiry_\(groupId)" }
    static func lastGroupPayGateOpen(_ groupId: String) -> String { "lastGroupPayGateOpen_\(groupId)" }
    static func pushSentFor(_ bundleId: String) -> String { "pushSentFor_\(bundleId)" }
    static func pushSentAt(_ bundleId: String) -> String { "pushSentAt_\(bundleId)" }
    static func appNameTokenKey(_ bundleId: String) -> String { "appName_\(bundleId)" }
    static func fcAppNameKey(_ base64Token: String) -> String { "fc_appName_" + base64Token }
    static func fcBundleIdKey(_ base64Token: String) -> String { "fc_bundleId_" + base64Token }
    static func fcGroupIdKey(_ base64Token: String) -> String { "fc_groupId_" + base64Token }

    // MARK: - Pending budget (widget → main app handoff)
    static let pendingBudgetMonitoringPrefix = "pendingBudgetMonitoring_"
    static let pendingBudgetMinutesPrefix = "pendingBudgetMinutes_"
    static func pendingSpendAmountKey(_ groupId: String) -> String { "pendingSpendAmount_\(groupId)" }
    static func pendingSpendTrackingKey(_ groupId: String) -> String { "pendingSpendTracking_\(groupId)" }
}
