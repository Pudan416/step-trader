import Foundation
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Ticket Groups Management
extension AppModel {
    // MARK: - Ticket Groups Management Functions
    func loadTicketGroups() {
        blockingStore.loadTicketGroups()
    }

    func persistTicketGroups() {
        blockingStore.persistTicketGroups()
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
        return blockingStore.createTicketGroup(name: name, templateApp: templateApp, defaultSettings: defaultSettings, stickerThemeIndex: themeIndex)
    }

    func updateTicketGroup(_ group: TicketGroup) {
        blockingStore.updateTicketGroup(group)
    }

    func deleteTicketGroup(_ groupId: String) {
        blockingStore.deleteTicketGroup(groupId)
    }

    func addAppsToGroup(_ groupId: String, selection: FamilyActivitySelection) {
        blockingStore.addAppsToGroup(groupId, selection: selection)
    }

    // MARK: - Find Ticket Group
    func findTicketGroup(for bundleId: String?) -> TicketGroup? {
        guard let bundleId else { return nil }

        #if canImport(FamilyControls)
        let defaults = UserDefaults.stepsTrader()

        // Iterate through all groups to find the app
        for group in ticketGroups {
            // Check all ApplicationTokens in the group
            for token in group.selection.applicationTokens {
                if let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                    let tokenKey = "fc_appName_" + tokenData.base64EncodedString()

                    // Check stored app name
                    if let storedName = defaults.string(forKey: tokenKey) {
                        let bundleIdLower = bundleId.lowercased()
                        let storedNameLower = storedName.lowercased()

                        if bundleIdLower == storedNameLower ||
                           bundleIdLower.contains(storedNameLower) ||
                           storedNameLower.contains(bundleIdLower) {
                            return group
                        }
                    }
                }
            }
        }
        #endif

        return nil
    }
}
