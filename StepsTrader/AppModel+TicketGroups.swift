import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Ticket Groups Management
extension AppModel {
    private func scheduleTicketGroupsSupabaseSync() {
        let snapshot = ticketGroups
        Task {
            await SupabaseSyncService.shared.syncTicketGroups(snapshot)
        }
    }

    // MARK: - Ticket Groups Management Functions
    func loadTicketGroups() {
        blockingStore.loadTicketGroups()
        scheduleTicketGroupsSupabaseSync()
    }

    func persistTicketGroups() {
        blockingStore.persistTicketGroups()
        scheduleTicketGroupsSupabaseSync()
    }

    func createTicketGroup(name: String, templateApp: String? = nil, stickerThemeIndex: Int? = nil) -> TicketGroup {
        let defaultSettings = AppUnlockSettings(
            entryCostSteps: entryCostSteps,
            dayPassCostSteps: defaultDayPassCost(forEntryCost: entryCostSteps),
            allowedWindows: [.minutes10, .minutes30, .hour1],
            minuteTariffEnabled: false,
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
        scheduleTicketGroupsSupabaseSync()
    }

    func deleteTicketGroup(_ groupId: String) {
        blockingStore.deleteTicketGroup(groupId)
        scheduleTicketGroupsSupabaseSync()
    }

    func addAppsToGroup(_ groupId: String, selection: FamilyActivitySelection) {
        blockingStore.addAppsToGroup(groupId, selection: selection)
        scheduleTicketGroupsSupabaseSync()
    }

    // MARK: - Find Ticket Group
    func findTicketGroup(for bundleId: String?) -> TicketGroup? {
        guard let bundleId else { return nil }

        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()

        // Iterate through all groups to find the app
        let bundleIdLower = bundleId.lowercased()
        for group in ticketGroups {
            for token in group.selection.applicationTokens {
                guard let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { continue }
                let base64 = tokenData.base64EncodedString()
                // Prefer exact bundleId match (avoids "Mail" matching "Gmail")
                if let storedBundleId = defaults.string(forKey: "fc_bundleId_" + base64) {
                    if bundleIdLower == storedBundleId.lowercased() { return group }
                    continue
                }
                // Legacy: only exact match on stored name (no substring)
                if let storedName = defaults.string(forKey: "fc_appName_" + base64),
                   bundleIdLower == storedName.lowercased() {
                    return group
                }
            }
        }
        #endif

        return nil
    }
}
