import Foundation
import Combine
import FamilyControls
import DeviceActivity
import ManagedSettings
import SwiftUI

@MainActor
final class BlockingStore: ObservableObject {
    // Dependencies
    private let familyControlsService: any FamilyControlsServiceProtocol
    
    // Cache serialized token keys to avoid repeated NSKeyedArchiver calls
    private var tokenKeyCache: [ApplicationToken: String] = [:]

    private func cachedTokenKey(for token: ApplicationToken) -> String? {
        if let cached = tokenKeyCache[token] { return cached }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return nil }
        let key = "fc_unlockUntil_" + data.base64EncodedString()
        tokenKeyCache[token] = key
        return key
    }

    // Published State
    @Published var ticketGroups: [TicketGroup] = []
    @Published var appUnlockSettings: [String: AppUnlockSettings] = [:]
    @Published var appSelection = FamilyActivitySelection() {
        didSet {
            // Logic for appSelection changes (debounce, persist) will be handled here
            handleAppSelectionChange(oldValue: oldValue)
        }
    }
    @Published var isBlocked = false
    @Published var isTrackingTime = false
    
    // Internal state
    private var rebuildBlockTask: Task<Void, Never>?
    private var persistAndRebuildTask: Task<Void, Never>?
    private var saveAppSelectionTask: Task<Void, Never>?
    private var lastSavedAppSelection: FamilyActivitySelection?
    
    // Constants
    private let ticketGroupsKey = "ticketGroups_v1"
    private let legacyShieldGroupsKey = "shieldGroups_v1"
    
    init(familyControlsService: any FamilyControlsServiceProtocol) {
        self.familyControlsService = familyControlsService
    }
    
    // MARK: - Authorization
    var isAuthorized: Bool {
        familyControlsService.isAuthorized
    }
    
    func requestAuthorization() async throws {
        do {
            try await familyControlsService.requestAuthorization()
        } catch {
            ErrorManager.shared.handle(AppError.familyControlsAuthorizationFailed(error))
            throw error
        }
    }
    
    // MARK: - App Selection Logic
    private func handleAppSelectionChange(oldValue: FamilyActivitySelection) {
        let hasChanges = appSelection.applicationTokens != oldValue.applicationTokens
            || appSelection.categoryTokens != oldValue.categoryTokens
        
        guard hasChanges else { return }
        
        if let lastSaved = lastSavedAppSelection,
           lastSaved.applicationTokens == appSelection.applicationTokens,
           lastSaved.categoryTokens == appSelection.categoryTokens {
            return
        }
        
        saveAppSelectionTask?.cancel()
        
        saveAppSelectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard let self = self, !Task.isCancelled else { return }
            
            self.saveAppSelection()
            self.lastSavedAppSelection = self.appSelection
            
            if let service = self.familyControlsService as? FamilyControlsService {
                service.updateSelection(self.appSelection)
            }
        }
    }
    
    func updateAppSelectionFromService(_ selection: FamilyActivitySelection) {
        guard selection.applicationTokens != appSelection.applicationTokens
            || selection.categoryTokens != appSelection.categoryTokens else { return }
        
        lastSavedAppSelection = selection
        appSelection = selection
    }
    
    private func saveAppSelection() {
        let defaults = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(appSelection) {
            defaults.set(data, forKey: "appSelection_v1")
            defaults.set(Date(), forKey: "appSelectionSavedDate")
        }
    }
    
    func clearAppSelection() {
        let emptySelection = FamilyActivitySelection()
        lastSavedAppSelection = emptySelection
        appSelection = emptySelection
        
        familyControlsService.updateSelection(emptySelection)
        rebuildFamilyControlsShield()
    }
    
    // MARK: - Ticket Groups Management
    func loadTicketGroups() {
        let g = UserDefaults.stepsTrader()
        if let data = g.data(forKey: ticketGroupsKey),
           let decoded = try? JSONDecoder().decode([TicketGroup].self, from: data) {
            ticketGroups = decoded
            return
        }
        // Migration from legacy key
        if let data = g.data(forKey: legacyShieldGroupsKey),
           let decoded = try? JSONDecoder().decode([TicketGroup].self, from: data) {
            ticketGroups = decoded
            g.set(data, forKey: ticketGroupsKey)
        } else {
            ticketGroups = []
        }
    }

    func persistTicketGroups() {
        let startTime = CFAbsoluteTimeGetCurrent()
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(ticketGroups) {
            g.set(data, forKey: ticketGroupsKey)
        }

        // Build Lite Config
        if let lite = buildLiteTicketConfig(),
           let liteData = try? JSONEncoder().encode(lite) {
            g.set(liteData, forKey: LiteTicketConfig.storageKey)
        }

        let persistTime = CFAbsoluteTimeGetCurrent() - startTime
        if persistTime > 0.05 {
            AppLogger.shield.debug("⏱️ persistTicketGroups took \(String(format: "%.3f", persistTime))s")
        }

        // Use a separate task so persist-triggered rebuilds don't collide
        // with direct rebuildFamilyControlsShield() calls (audit fix #8)
        persistAndRebuildTask?.cancel()
        persistAndRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            self.rebuildFamilyControlsShield()
        }
    }

    private func buildLiteTicketConfig() -> LiteTicketConfig? {
        #if canImport(FamilyControls)
        let groups: [LiteTicketGroup] = ticketGroups.compactMap { group in
            guard let data = try? JSONEncoder().encode(group.selection) else { return nil }
            let base64 = data.base64EncodedString()
            let active = group.settings.minuteTariffEnabled || group.settings.familyControlsModeEnabled
            return LiteTicketGroup(
                id: group.id,
                name: group.name,
                selectionDataBase64: base64,
                active: active
            )
        }
        return LiteTicketConfig(groups: groups)
        #else
        return LiteTicketConfig(groups: [])
        #endif
    }

    func createTicketGroup(name: String, templateApp: String? = nil, defaultSettings: AppUnlockSettings, stickerThemeIndex: Int = 0) -> TicketGroup {
        let group = TicketGroup(name: name, settings: defaultSettings, templateApp: templateApp, stickerThemeIndex: stickerThemeIndex)
        ticketGroups.append(group)
        persistTicketGroups()
        return group
    }

    func updateTicketGroup(_ group: TicketGroup) {
        if let index = ticketGroups.firstIndex(where: { $0.id == group.id }) {
            ticketGroups[index] = group
            persistTicketGroups()
        }
    }

    func deleteTicketGroup(_ groupId: String) {
        ticketGroups.removeAll { $0.id == groupId }
        persistTicketGroups()
    }

    func addAppsToGroup(_ groupId: String, selection: FamilyActivitySelection) {
        guard let index = ticketGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var group = ticketGroups[index]
        #if canImport(FamilyControls)
        group.selection.applicationTokens.formUnion(selection.applicationTokens)
        group.selection.categoryTokens.formUnion(selection.categoryTokens)
        #endif
        ticketGroups[index] = group
        persistTicketGroups()
    }

    // MARK: - Block Management
    private func timeAccessSelectionKey(for bundleId: String) -> String {
        "timeAccessSelection_v1_\(bundleId)"
    }
    
    func timeAccessSelection(for bundleId: String) -> FamilyActivitySelection {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = g.data(forKey: timeAccessSelectionKey(for: bundleId)),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            return decoded
        }
        #endif
        return FamilyActivitySelection()
    }

    func saveTimeAccessSelection(_ selection: FamilyActivitySelection, for bundleId: String) {
        let g = UserDefaults.stepsTrader()
        #if canImport(FamilyControls)
        if let data = try? JSONEncoder().encode(selection) {
            g.set(data, forKey: timeAccessSelectionKey(for: bundleId))
        }
        #endif
    }
    
    func rebuildFamilyControlsShield() {
        rebuildBlockTask?.cancel()

        rebuildBlockTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }

            guard familyControlsService.isAuthorized else {
                AppLogger.shield.debug("⚠️ Cannot rebuild block: Family Controls not authorized")
                logShieldDiagnostic(source: "app", apps: 0, categories: 0,
                                    detail: "ABORTED: Family Controls not authorized")
                return
            }
            
            let startTime = CFAbsoluteTimeGetCurrent()
            var combined = FamilyActivitySelection()
            let defaults = UserDefaults.stepsTrader()
            let now = Date()
            var diagLines: [String] = []
            
            for group in ticketGroups {
                let unlockKey = "groupUnlock_\(group.id)"
                if let unlockUntil = defaults.object(forKey: unlockKey) as? Date {
                    if now < unlockUntil {
                        let secs = Int(unlockUntil.timeIntervalSince(now))
                        diagLines.append("SKIP \(group.name): unlocked \(secs)s left")
                        AppLogger.shield.debug("⏭️ Skipping group \(group.name) - unlocked until \(unlockUntil)")
                        continue
                    } else {
                        diagLines.append("EXPIRED \(group.name): key removed")
                        AppLogger.shield.debug("🧹 Cleaning expired unlock for group \(group.name)")
                        defaults.removeObject(forKey: unlockKey)
                    }
                }
                
                let isActive = group.settings.familyControlsModeEnabled == true || group.settings.minuteTariffEnabled == true
                if isActive {
                    #if canImport(FamilyControls)
                    var groupTokens = group.selection.applicationTokens
                    let groupCategories = group.selection.categoryTokens
                    
                    groupTokens = groupTokens.filter { token in
                        guard let tokenKey = cachedTokenKey(for: token),
                              let unlockUntil = defaults.object(forKey: tokenKey) as? Date else { return true }
                        return now >= unlockUntil
                    }
                    
                    combined.applicationTokens.formUnion(groupTokens)
                    combined.categoryTokens.formUnion(groupCategories)
                    diagLines.append("ADD \(group.name): \(groupTokens.count) apps, \(groupCategories.count) cats (fc=\(group.settings.familyControlsModeEnabled) mt=\(group.settings.minuteTariffEnabled))")
                    #endif
                } else {
                    diagLines.append("INACTIVE \(group.name): fc=\(group.settings.familyControlsModeEnabled) mt=\(group.settings.minuteTariffEnabled)")
                }
            }
            
            // Legacy appUnlockSettings support
            for (cardId, settings) in appUnlockSettings {
                if settings.familyControlsModeEnabled == true || settings.minuteTariffEnabled == true {
                    let blockKey = "blockUntil_\(cardId)"
                    if let until = defaults.object(forKey: blockKey) as? Date {
                        if now < until { continue }
                        else { defaults.removeObject(forKey: blockKey) }
                    }
                    let selection = timeAccessSelection(for: cardId)
                    combined.applicationTokens.formUnion(selection.applicationTokens)
                    combined.categoryTokens.formUnion(selection.categoryTokens)
                }
            }
            
            familyControlsService.updateSelection(combined)
            familyControlsService.updateMinuteModeMonitoring()
            familyControlsService.updateShieldSchedule()
            
            applyShieldImmediately(selection: combined)
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > 0.1 {
                AppLogger.shield.debug("⚠️ rebuildFamilyControlsShield took \(String(format: "%.3f", elapsed))s")
            }
            
            let sharedDefaults = UserDefaults.stepsTrader()
            sharedDefaults.set(0, forKey: "doomShieldState_v1")

            let detail = diagLines.joined(separator: " | ")
            logShieldDiagnostic(source: "app", apps: combined.applicationTokens.count,
                                categories: combined.categoryTokens.count, detail: detail)
        }
    }
    
    #if canImport(ManagedSettings)
    private func applyShieldImmediately(selection: FamilyActivitySelection) {
        guard familyControlsService.isAuthorized else {
            AppLogger.shield.debug("⚠️ Cannot apply shield: Family Controls not authorized")
            return
        }
        
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        AppLogger.shield.debug("🛡️ Shield applied immediately: \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories")
    }
    #endif
    
    func cleanupExpiredUnlocks() {
        let defaults = UserDefaults.stepsTrader()
        let now = Date()
        var cleanedCount = 0
        
        for group in ticketGroups {
            let unlockKey = "groupUnlock_\(group.id)"
            if let unlockUntil = defaults.object(forKey: unlockKey) as? Date,
               now >= unlockUntil {
                defaults.removeObject(forKey: unlockKey)
                cleanedCount += 1
                AppLogger.shield.debug("🧹 Cleaned expired unlock for group \(group.name)")
            }
        }
        
        if cleanedCount > 0 {
            AppLogger.shield.debug("🧹 Cleaned \(cleanedCount) expired unlock(s), rebuilding shield...")
            rebuildFamilyControlsShield()
        }

        // If no unlocks remain, cancel the background refresh task
        let hasActiveUnlocks = ticketGroups.contains { group in
            let key = "groupUnlock_\(group.id)"
            if let until = defaults.object(forKey: key) as? Date, now < until { return true }
            return false
        }
        if !hasActiveUnlocks {
            UnlockExpiryTaskManager.shared.cancelPendingTasks()
        }
    }

    // MARK: - Shield Diagnostics

    /// Append a diagnostic entry to the shared history ring buffer (last 20 entries).
    /// Called from app-side rebuild; the extension writes its own via the same keys.
    static func logShieldDiagnostic(source: String, apps: Int, categories: Int, detail: String) {
        let defaults = UserDefaults.stepsTrader()
        let iso = ISO8601DateFormatter()
        let ts = iso.string(from: Date())
        let entry = "[\(ts)] [\(source)] apps=\(apps) cats=\(categories) \(detail)"

        var history = defaults.stringArray(forKey: SharedKeys.shieldDiagHistory) ?? []
        history.append(entry)
        if history.count > 20 { history = Array(history.suffix(20)) }
        defaults.set(history, forKey: SharedKeys.shieldDiagHistory)
        defaults.set(entry, forKey: SharedKeys.shieldDiagLastRebuild)
    }

    private func logShieldDiagnostic(source: String, apps: Int, categories: Int, detail: String) {
        Self.logShieldDiagnostic(source: source, apps: apps, categories: categories, detail: detail)
    }

    /// Build a human-readable diagnostics string covering shield state, unlock keys,
    /// ticket groups, extension logs, and rebuild history.
    func dumpShieldDiagnostics() -> String {
        let defaults = UserDefaults.stepsTrader()
        let now = Date()
        let iso = ISO8601DateFormatter()
        var lines: [String] = ["=== Shield Diagnostics (\(iso.string(from: now))) ===", ""]

        // 1. Ticket groups
        lines.append("-- Ticket Groups (\(ticketGroups.count)) --")
        for g in ticketGroups {
            let fc = g.settings.familyControlsModeEnabled
            let mt = g.settings.minuteTariffEnabled
            let appCount = g.selection.applicationTokens.count
            let catCount = g.selection.categoryTokens.count
            let unlockKey = "groupUnlock_\(g.id)"
            var status = "LOCKED"
            if let until = defaults.object(forKey: unlockKey) as? Date {
                if now < until {
                    status = "UNLOCKED \(Int(until.timeIntervalSince(now)))s left"
                } else {
                    status = "EXPIRED (key still present!)"
                }
            }
            lines.append("  \(g.name) | id=\(g.id.prefix(8))… | fc=\(fc) mt=\(mt) | \(appCount) apps \(catCount) cats | \(status)")
        }

        // 2. Active unlock/block keys
        lines.append("")
        lines.append("-- Active Unlock Keys --")
        let allKeys = defaults.dictionaryRepresentation().keys.sorted()
        var unlockCount = 0
        for key in allKeys where key.hasPrefix("groupUnlock_") || key.hasPrefix("blockUntil_") {
            if let until = defaults.object(forKey: key) as? Date {
                let delta = Int(until.timeIntervalSince(now))
                let state = delta > 0 ? "active (\(delta)s)" : "EXPIRED (\(-delta)s ago)"
                lines.append("  \(key) → \(state)")
                unlockCount += 1
            }
        }
        if unlockCount == 0 { lines.append("  (none)") }

        // 3. Family Controls auth
        lines.append("")
        lines.append("-- Family Controls --")
        lines.append("  authorized: \(familyControlsService.isAuthorized)")

        // 4. Current ManagedSettingsStore state
        #if canImport(ManagedSettings)
        let store = ManagedSettingsStore(named: .init("shield"))
        let shieldApps = store.shield.applications?.count ?? 0
        let shieldCats: Int = {
            if case .specific(let cats, _) = store.shield.applicationCategories { return cats.count }
            return 0
        }()
        lines.append("  ManagedSettingsStore 'shield': \(shieldApps) apps, \(shieldCats) categories")
        #endif

        // 5. DeviceActivityCenter registered activities
        #if canImport(DeviceActivity)
        let activityCenter = DeviceActivityCenter()
        let registeredActivities = activityCenter.activities
        lines.append("")
        lines.append("-- DeviceActivityCenter.activities (\(registeredActivities.count)) --")
        if registeredActivities.isEmpty {
            lines.append("  (none — startMonitoring never succeeded or was cleared)")
        } else {
            for activity in registeredActivities {
                lines.append("  \(activity.rawValue)")
            }
        }
        #endif

        // 5b. Last startMonitoring log
        if let lastMonLog = defaults.string(forKey: SharedKeys.lastStartMonitoringLog) {
            lines.append("")
            lines.append("-- Last startMonitoring Result --")
            lines.append("  \(lastMonLog)")
        }

        // 5c. Extension test
        if let testAt = defaults.object(forKey: SharedKeys.extensionTestScheduledAt) as? Date {
            let delta = Int(now.timeIntervalSince(testAt))
            lines.append("")
            lines.append("-- Extension Test --")
            lines.append("  scheduled \(delta)s ago")
        }

        // 6. Shield rebuild history
        lines.append("")
        lines.append("-- Rebuild History (last 20) --")
        let history = defaults.stringArray(forKey: SharedKeys.shieldDiagHistory) ?? []
        if history.isEmpty {
            lines.append("  (none)")
        } else {
            for entry in history { lines.append("  \(entry)") }
        }

        // 7. Extension monitor logs
        lines.append("")
        lines.append("-- Extension Monitor Logs (last 30) --")
        let monitorLogs = defaults.stringArray(forKey: SharedKeys.monitorLogs) ?? []
        if monitorLogs.isEmpty {
            lines.append("  (none)")
        } else {
            for log in monitorLogs { lines.append("  \(log)") }
        }

        // 8. Extension errors
        let errorCount = defaults.integer(forKey: SharedKeys.monitorErrorCount)
        if errorCount > 0 {
            lines.append("")
            lines.append("-- Extension Errors (count: \(errorCount)) --")
            if let lastAt = defaults.object(forKey: SharedKeys.monitorLastErrorAt) as? Date {
                lines.append("  last error: \(iso.string(from: lastAt))")
            }
        }

        lines.append("")
        lines.append("=== END ===")
        return lines.joined(separator: "\n")
    }

    // MARK: - Tracking
    func startTracking() {
        isTrackingTime = true
        isBlocked = true
        rebuildFamilyControlsShield()
    }
    
    func stopTracking() {
        isTrackingTime = false
        isBlocked = false
        // Clear shield using targeted properties instead of clearAllSettings()
        // to avoid wiping unrelated ManagedSettings (audit fix #17)
        let empty = FamilyActivitySelection()
        familyControlsService.updateSelection(empty)
        #if canImport(ManagedSettings)
        let store = ManagedSettingsStore(named: .init("shield"))
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        #endif
    }
}
