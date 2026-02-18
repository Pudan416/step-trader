import Foundation

/// Single source of truth for all UserDefaults and App Group keys.
/// Shared across the main app and extensions (ShieldAction, ShieldConfiguration, DeviceActivityMonitor).
enum SharedKeys {
    static let appGroupId = "group.personal-project.StepsTrader"
    static func appGroupDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
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

    // MARK: - Budget (legacy and current)
    static let dailyTariffSelectionsAnchor = "dailyTariffSelectionsAnchor"
    static let dailyTariffSelections = "dailyTariffSelections_v1"
    static let spentMinutes = "spentMinutes_v1"
    static let spentStepsLegacy = "spentSteps_v1"
    static let spentTariff = "spentTariff_v1"
    static let minuteTariffBundleId = "minuteTariffBundleId_v1"
    static let minuteTariffLastTick = "minuteTariffLastTick_v1"
    static let minuteTariffRate = "minuteTariffRate_v1"
    static let budgetMinutes = "budgetMinutes"
    static let monitoringStartTime = "monitoringStartTime"
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
    static let lastBlockedAppBundleId = "lastBlockedAppBundleId"
    static let lastBlockedGroupId = "lastBlockedGroupId"

    // MARK: - PayGate
    static let shouldShowPayGate = "shouldShowPayGate"
    static let payGateTargetGroupId = "payGateTargetGroupId"
    static let payGateTargetBundleId = "payGateTargetBundleId_v1"
    static let payGateDismissedUntil = "payGateDismissedUntil_v1"
    static let blockedPaygateBundleId = "blockedPaygateBundleId"
    static let blockedPaygateTimestamp = "blockedPaygateTimestamp"

    // MARK: - Spend tracking
    static let appStepsSpentToday = "appStepsSpentToday_v1"
    static let appStepsSpentLifetime = "appStepsSpentLifetime_v1"
    static let appStepsSpentByDay = "appStepsSpentByDay_v1"
    static let minuteChargeLogs = "minuteChargeLogs_v1"
    static let minuteChargeLogsFilename = "minuteChargeLogs.json"
    static let minuteTimeByDay = "minuteTimeByDay_v1"

    /// Shared file for minute charge logs (app + DeviceActivityMonitor extension). Single source of truth.
    static func minuteChargeLogsFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        return container.appendingPathComponent(minuteChargeLogsFilename)
    }
    static let appDayPassGrants = "appDayPassGrants_v1"

    // MARK: - Appearance
    static let gradientStyle = "gradientStyle_v1"

    // MARK: - Selections / gallery
    static let appSelection = "appSelection_v1"
    static let appSelectionSavedDate = "appSelectionSavedDate"
    static let customEnergyOptions = "customEnergyOptions_v1"
    static let pastDaySnapshots = "pastDaySnapshots_v1"
    static let dailyGallerySlots = "dailyChoiceSlots_v1"
    static let userStepsTarget = "userStepsTarget"
    static let userSleepTarget = "userSleepTarget"

    // MARK: - Monitor (DeviceActivityMonitor extension)
    static let monitorLogs = "monitorLogs_v1"
    static let monitorErrorLogs = "monitorErrorLogs_v1"
    static let monitorErrorCount = "monitorErrorCount_v1"
    static let monitorLastErrorAt = "monitorLastErrorAt_v1"

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

    // MARK: - Helpers (parameterized)
    static func groupUnlockKey(_ groupId: String) -> String { "groupUnlock_\(groupId)" }
    static func blockUntilKey(_ bundleId: String) -> String { "blockUntil_\(bundleId)" }
    static func timeAccessSelectionKey(_ bundleId: String) -> String { "timeAccessSelection_v1_\(bundleId)" }
    static func dailySelectionsKey(_ category: String) -> String { "dailyEnergySelections_v1_\(category)" }
    static func preferredOptionsKey(_ category: String) -> String { "preferredEnergyOptions_v1_\(category)" }
    static func minuteCountKey(dayKey: String, bundleId: String) -> String { "minuteCount_\(dayKey)_\(bundleId)" }
    static func lastAppOpenedFromStepsTrader(_ bundleId: String) -> String { "lastAppOpenedFromStepsTrader_\(bundleId)" }
    static func lastGroupPayGateOpen(_ groupId: String) -> String { "lastGroupPayGateOpen_\(groupId)" }
    static func pushSentFor(_ bundleId: String) -> String { "pushSentFor_\(bundleId)" }
    static func pushSentAt(_ bundleId: String) -> String { "pushSentAt_\(bundleId)" }
    static func appNameTokenKey(_ bundleId: String) -> String { "appName_\(bundleId)" }
}
