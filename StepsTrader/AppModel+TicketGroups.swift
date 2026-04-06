import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Ticket Groups Management
extension AppModel {
    /// Cached bundle-ID → TicketGroup lookup. Invalidated whenever groups change.
    private static var _bundleIdGroupCache: [String: TicketGroup]?

    private func invalidateBundleIdCache() {
        Self._bundleIdGroupCache = nil
    }

    private func scheduleTicketGroupsSupabaseSync() {
        let snapshot = ticketGroups
        Task {
            await SupabaseSyncService.shared.syncTicketGroups(snapshot)
        }
    }

    // MARK: - Ticket Groups Management Functions
    func loadTicketGroups() {
        blockingStore.loadTicketGroups()
        invalidateBundleIdCache()
        scheduleTicketGroupsSupabaseSync()
    }

    func persistTicketGroups() {
        blockingStore.persistTicketGroups()
        invalidateBundleIdCache()
        scheduleTicketGroupsSupabaseSync()
    }

    func createTicketGroup(name: String, templateApp: String? = nil, stickerThemeIndex: Int? = nil) -> TicketGroup {
        let defaultSettings = AppUnlockSettings(
            entryCostSteps: entryCostSteps,
            dayPassCostSteps: defaultDayPassCost(forEntryCost: entryCostSteps),
            allowedWindows: [.minutes10, .minutes30, .hour1],
            familyControlsModeEnabled: true
        )
        let themeIndex = stickerThemeIndex ?? 0
        let group = blockingStore.createTicketGroup(name: name, templateApp: templateApp, defaultSettings: defaultSettings, stickerThemeIndex: themeIndex)
        scheduleTicketGroupsSupabaseSync()
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "ticket_created",
                properties: [
                    "group_id": group.id,
                    "template_app": templateApp ?? ""
                ]
            )
        }
        return group
    }

    func updateTicketGroup(_ group: TicketGroup) {
        blockingStore.updateTicketGroup(group)
        invalidateBundleIdCache()
        scheduleTicketGroupsSupabaseSync()
    }

    func deleteTicketGroup(_ groupId: String) {
        blockingStore.deleteTicketGroup(groupId)
        invalidateBundleIdCache()
        scheduleTicketGroupsSupabaseSync()
    }

    func addAppsToGroup(_ groupId: String, selection: FamilyActivitySelection) {
        blockingStore.addAppsToGroup(groupId, selection: selection)
        invalidateBundleIdCache()
        scheduleTicketGroupsSupabaseSync()
    }

    // MARK: - Find Ticket Group
    func findTicketGroup(for bundleId: String?) -> TicketGroup? {
        guard let bundleId else { return nil }

        #if canImport(FamilyControls)
        if let cache = Self._bundleIdGroupCache {
            return cache[bundleId.lowercased()]
        }

        let defaults = UserDefaults.stepsTrader()
        var lookup: [String: TicketGroup] = [:]

        for group in ticketGroups {
            for token in group.selection.applicationTokens {
                let tokenData: Data
                do {
                    tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                } catch {
                    AppLogger.familyControls.error("Failed to archive application token in group \(group.id): \(error.localizedDescription)")
                    continue
                }
                let base64 = tokenData.base64EncodedString()
                if let storedBundleId = defaults.string(forKey: SharedKeys.fcBundleIdKey(base64)) {
                    lookup[storedBundleId.lowercased()] = group
                } else if let storedName = defaults.string(forKey: SharedKeys.fcAppNameKey(base64)) {
                    lookup[storedName.lowercased()] = group
                }
            }
        }

        Self._bundleIdGroupCache = lookup
        return lookup[bundleId.lowercased()]
        #else
        return nil
        #endif
    }
}
