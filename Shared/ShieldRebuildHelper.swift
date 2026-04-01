import Foundation
#if canImport(ManagedSettings)
import ManagedSettings
#endif
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Shared Codable Types
// Canonical definitions used by DeviceActivityMonitor, ShieldAction, and
// ShieldRebuildHelper to decode ticket-group / unlock-settings payloads
// from App Group UserDefaults.  Keep these at file scope so every target
// that includes Shared/ can reference them without qualification.

/// Minimal decoded view of per-app unlock settings stored under `appUnlockSettings_v1`.
struct StoredUnlockSettings: Codable {
    let entryCostSteps: Int?
    let familyControlsModeEnabled: Bool?
}

/// Lite ticket config written by the main app (`liteTicketConfig_v1` / `liteShieldConfig_v1`).
struct LiteConfig: Decodable {
    let groups: [LiteGroup]
}

/// A single group inside `LiteConfig`.
struct LiteGroup: Decodable {
    let id: String
    let name: String
    let selectionDataBase64: String
    let active: Bool
}

/// Full ticket-group payload decoded from `ticketGroups_v1` / `shieldGroups_v1`.
struct ShieldGroupData: Decodable {
    let id: String
    let name: String
    let selectionData: Data?
    let settings: SettingsBlock?

    var hasActiveSettings: Bool {
        settings?.familyControlsModeEnabled == true
    }

    struct SettingsBlock: Decodable {
        let familyControlsModeEnabled: Bool?
    }
}

/// Resolved group tuple returned by `ShieldRebuildHelper.loadGroups`.
struct GroupTuple {
    let id: String
    let name: String
    let selectionData: Data?
    let active: Bool
}

// MARK: - Shield Rebuild

/// Shared shield rebuild logic used by the main app, widget extension, and
/// DeviceActivityMonitor extension.  Reads ticket groups from the App Group
/// UserDefaults, skips unlocked groups, unions the remaining selections, and
/// applies the result to `ManagedSettingsStore(named: "shield")`.
enum ShieldRebuildHelper {

    // MARK: - Public

    /// Rebuild the shield from any process that links ManagedSettings.
    static func rebuild() {
        #if canImport(ManagedSettings) && canImport(FamilyControls)
        let defaults = UserDefaults(suiteName: SharedKeys.appGroupId) ?? .standard

        var allApps = Set<ApplicationToken>()
        var allCategories = Set<ActivityCategoryToken>()

        let groups = loadGroups(defaults: defaults)

        for group in groups where group.active {
            if defaults.integer(forKey: SharedKeys.usageBudgetKey(group.id)) > 0 {
                if let expiry = defaults.object(forKey: SharedKeys.usageBudgetExpiryKey(group.id)) as? Date,
                   Date() < expiry {
                    continue
                }
                defaults.removeObject(forKey: SharedKeys.usageBudgetKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
            }

            guard let selectionData = group.selectionData else { continue }
            guard let sel = try? JSONDecoder().decode(
                FamilyActivitySelection.self, from: selectionData
            ) else { continue }

            allApps.formUnion(sel.applicationTokens)
            allCategories.formUnion(sel.categoryTokens)
        }

        // Legacy per-app selections
        if let data = defaults.data(forKey: SharedKeys.appUnlockSettings),
           let decoded = try? JSONDecoder().decode([String: StoredUnlockSettings].self, from: data) {
            for (bundleId, settings) in decoded where settings.familyControlsModeEnabled == true {
                let key = SharedKeys.timeAccessSelectionKey(bundleId)
                if let selData = defaults.data(forKey: key),
                   let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selData) {
                    allApps.formUnion(sel.applicationTokens)
                    allCategories.formUnion(sel.categoryTokens)
                }
            }
        }

        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = allApps.isEmpty ? nil : allApps
        store.shield.applicationCategories = allCategories.isEmpty
            ? nil
            : .specific(allCategories)

        defaults.set(0, forKey: SharedKeys.shieldState)
        #endif
    }

    // MARK: - Group Loading

    /// Load ticket groups from UserDefaults, preferring lite config over full payload.
    /// Shared across DeviceActivityMonitor, ShieldAction, and the rebuild logic.
    static func loadGroups(defaults: UserDefaults) -> [GroupTuple] {
        if let liteData = defaults.data(forKey: SharedKeys.liteTicketConfig),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: liteData) {
            return lite.groups.map {
                GroupTuple(id: $0.id, name: $0.name,
                           selectionData: Data(base64Encoded: $0.selectionDataBase64),
                           active: $0.active)
            }
        }
        if let liteData = defaults.data(forKey: SharedKeys.liteShieldConfig),
           let lite = try? JSONDecoder().decode(LiteConfig.self, from: liteData) {
            return lite.groups.map {
                GroupTuple(id: $0.id, name: $0.name,
                           selectionData: Data(base64Encoded: $0.selectionDataBase64),
                           active: $0.active)
            }
        }
        let groupsData = defaults.data(forKey: SharedKeys.ticketGroups)
            ?? defaults.data(forKey: SharedKeys.legacyShieldGroups)
        guard let data = groupsData,
              let groups = try? JSONDecoder().decode([ShieldGroupData].self, from: data)
        else { return [] }
        return groups.map {
            GroupTuple(id: $0.id, name: $0.name,
                       selectionData: $0.selectionData,
                       active: $0.hasActiveSettings)
        }
    }
}
