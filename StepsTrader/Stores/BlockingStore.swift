import Foundation
import Combine
import FamilyControls
import DeviceActivity
import ManagedSettings
import SwiftUI
import WidgetKit

@MainActor
final class BlockingStore: ObservableObject {
    // Dependencies
    private let familyControlsService: any FamilyControlsServiceProtocol
    
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
            
            self.familyControlsService.updateSelection(self.appSelection)
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
            defaults.set(data, forKey: SharedKeys.appSelection)
            defaults.set(Date(), forKey: SharedKeys.appSelectionSavedDate)
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
        do {
            let data = try JSONEncoder().encode(ticketGroups)
            g.set(data, forKey: ticketGroupsKey)
        } catch {
            AppLogger.shield.error("Failed to encode ticketGroups — user config not persisted: \(error.localizedDescription)")
        }

        // Build Lite Config
        if let lite = buildLiteTicketConfig() {
            do {
                let liteData = try JSONEncoder().encode(lite)
                g.set(liteData, forKey: LiteTicketConfig.storageKey)
            } catch {
                AppLogger.shield.error("Failed to encode LiteTicketConfig: \(error.localizedDescription)")
            }
        }

        let persistTime = CFAbsoluteTimeGetCurrent() - startTime
        if persistTime > 0.05 {
            AppLogger.shield.debug("⏱️ persistTicketGroups took \(String(format: "%.3f", persistTime))s")
        }

        // Debounce widget reload and shield rebuild together to avoid spamming
        // on rapid successive persists (reorder, batch updates, etc.)
        persistAndRebuildTask?.cancel()
        persistAndRebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
            self.rebuildFamilyControlsShield()
        }
    }

    private func buildLiteTicketConfig() -> LiteTicketConfig? {
        #if canImport(FamilyControls)
        let groups: [LiteTicketGroup] = ticketGroups.compactMap { group in
            guard let data = try? JSONEncoder().encode(group.selection) else { return nil }
            let base64 = data.base64EncodedString()
            let active = group.settings.familyControlsModeEnabled
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
        SharedKeys.timeAccessSelectionKey(bundleId)
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

            familyControlsService.refreshAuthorizationStatus()

            guard familyControlsService.isAuthorized else {
                AppLogger.shield.debug("⚠️ Cannot rebuild block: Family Controls not authorized (even after refresh)")
                logShieldDiagnostic(source: "app", apps: 0, categories: 0,
                                    detail: "ABORTED: Family Controls not authorized")
                ShieldRebuildHelper.rebuild()
                return
            }
            
            let startTime = CFAbsoluteTimeGetCurrent()
            var combined = FamilyActivitySelection()
            let defaults = UserDefaults.stepsTrader()
            var diagLines: [String] = []
            
            for group in ticketGroups {
                let budgetKey = SharedKeys.usageBudgetKey(group.id)
                if defaults.integer(forKey: budgetKey) > 0 {
                    diagLines.append("SKIP \(group.name): usageBudget active")
                    AppLogger.shield.debug("⏭️ Skipping group \(group.name) - usage budget active")
                    continue
                }
                
                let isActive = group.settings.familyControlsModeEnabled == true
                if isActive {
                    #if canImport(FamilyControls)
                    combined.applicationTokens.formUnion(group.selection.applicationTokens)
                    combined.categoryTokens.formUnion(group.selection.categoryTokens)
                    diagLines.append("ADD \(group.name): \(group.selection.applicationTokens.count) apps, \(group.selection.categoryTokens.count) cats (fc=\(group.settings.familyControlsModeEnabled))")
                    #endif
                } else {
                    diagLines.append("INACTIVE \(group.name): fc=\(group.settings.familyControlsModeEnabled)")
                }
            }
            
            // Legacy appUnlockSettings support
            for (cardId, settings) in appUnlockSettings {
                if settings.familyControlsModeEnabled == true {
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
            sharedDefaults.set(0, forKey: SharedKeys.shieldState)

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
            let appCount = g.selection.applicationTokens.count
            let catCount = g.selection.categoryTokens.count
            let budgetKey = SharedKeys.usageBudgetKey(g.id)
            let budget = defaults.integer(forKey: budgetKey)
            let status = budget > 0 ? "USAGE_BUDGET \(budget)m" : "LOCKED"
            lines.append("  \(g.name) | id=\(g.id.prefix(8))… | fc=\(fc) | \(appCount) apps \(catCount) cats | \(status)")
        }

        // 2. Family Controls auth
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

        // 5b. Usage Budget State
        lines.append("")
        lines.append("-- Usage Budgets --")
        var budgetCount = 0
        for g in ticketGroups {
            let remaining = defaults.integer(forKey: SharedKeys.usageBudgetKey(g.id))
            let initial = defaults.integer(forKey: SharedKeys.usageBudgetInitialKey(g.id))
            let started = defaults.object(forKey: SharedKeys.usageBudgetStartedKey(g.id)) as? Date
            if remaining > 0 || initial > 0 || started != nil {
                let startedStr = started.map { iso.string(from: $0) } ?? "nil"
                var extra = ""
                if let s = started, initial > 0 {
                    let wallElapsed = Int(now.timeIntervalSince(s) / 60)
                    let wallRemaining = max(0, initial - wallElapsed)
                    let effective = min(remaining, wallRemaining)
                    extra = " | wallClock=\(wallElapsed)m elapsed, effective=\(effective)m"
                }
                lines.append("  \(g.name): \(remaining)/\(initial)m remaining | started: \(startedStr)\(extra)")
                budgetCount += 1
            }
        }
        if budgetCount == 0 { lines.append("  (no active budgets)") }

        // 5c. Last startMonitoring log
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

}
