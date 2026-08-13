import Foundation
import SwiftUI
import WidgetKit

// MARK: - Daily Energy Management
// All persistence keys live in SharedKeys (non-isolated enum, safe to read from
// any actor context). The previous file-scope `_xxxKey` constants were folded
// into SharedKeys in CODE_AUDIT.md §9.4.
extension AppModel {
    var happeningPointsToday: Int {
        HappeningEconomy.points(forAdditionCount: todayAdditions.count)
    }

    /// Adds one occurrence when the happening has not already been added on
    /// the requested custom day.
    func canAddHappening(id: String, on date: Date = .now) -> Bool {
        let dayKey = Self.dayKey(for: date)
        return !todayAdditions.contains {
            $0.dayKey == dayKey && $0.optionId == id
        }
    }

    @discardableResult
    func addHappening(
        id: String,
        colorHex: String,
        at date: Date = .now,
        recordUse: Bool = true,
        entryId: String = UUID().uuidString
    ) -> OptionEntry? {
        let dayKey = Self.dayKey(for: date)
        guard canAddHappening(id: id, on: date) else { return nil }

        let entry = OptionEntry(
            id: entryId,
            dayKey: dayKey,
            optionId: id,
            colorHex: colorHex,
            timestamp: date,
            assetVariant: nil
        )
        todayAdditions.append(entry)
        if recordUse { happeningStore.recordUse(id: id, at: date) }
        recalculateDailyEnergy()
        persistTodayAdditions()
        Task { await SupabaseSyncService.shared.syncOptionEntry(entry) }
        Task { await SupabaseSyncService.shared.syncCustomHappenings(happeningStore.all) }
        return entry
    }

    func removeAddition(entryId: String) {
        guard let index = todayAdditions.firstIndex(where: { $0.id == entryId }) else { return }
        todayAdditions.remove(at: index)
        recalculateDailyEnergy()
        persistTodayAdditions()
        Task { await SupabaseSyncService.shared.deleteOptionEntry(id: entryId) }
    }

    func createHappening(title: String, at date: Date = .now) -> Happening {
        happeningStore.create(title: title, at: date)
    }

    /// Creates a catalog item and installs it into the configured ten without
    /// logging it to the current day. The user still has to tap its field zone.
    func createPaletteHappening(
        title: String,
        at date: Date = .now,
        syncCustomHappenings: @escaping ([Happening]) -> Void = { happenings in
            Task { await SupabaseSyncService.shared.syncCustomHappenings(happenings) }
        }
    ) -> Happening? {
        let happening = createHappening(title: title, at: date)
        do {
            try happeningPaletteSelectionStore.insertReplacingLeastUsed(
                happening.id,
                catalog: happeningStore.all
            )
            objectWillChange.send()
            syncCustomHappenings(happeningStore.all)
            return happening
        } catch {
            AppLogger.energy.error(
                "Failed to install created palette happening: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func paletteHappeningCatalog() -> [Happening] {
        happeningStore.all
    }

    func selectedPaletteHappeningIDs() -> [String] {
        happeningPaletteSelectionStore.ids
    }

    func savePaletteHappeningSelection(_ ids: [String]) throws {
        try happeningPaletteSelectionStore.save(ids, catalog: happeningStore.all)
        objectWillChange.send()
    }

    func configuredPaletteHappenings() -> [Happening] {
        happeningPaletteSelectionStore.ids.compactMap { happeningStore.happening(id: $0) }
    }

    /// The figure each configured happening takes today — the shape type,
    /// colour, silhouette and rotation a tile previews and `spawn` then uses.
    /// Derived from the day's nonce rather than stored; see `HappeningShapeRoll`.
    func paletteFigures(on date: Date = .now) -> [String: HappeningShapeAssignment] {
        let dayKey = Self.dayKey(for: date)
        AppLogger.energy.debug(
            "🎲 paletteFigures read: nonce \(self.happeningShapeNonceStore.nonce(for: dayKey))"
        )
        return HappeningShapeRoll.assignments(
            for: configuredPaletteHappenings().map(\.id),
            dayKey: dayKey,
            nonce: happeningShapeNonceStore.nonce(for: dayKey)
        )
    }

    /// Shake. Only the field changes: additions already carry the colour they
    /// were logged with, and their canvas elements already froze their shape.
    func rerollPaletteFigures(on date: Date = .now) {
        let dayKey = Self.dayKey(for: date)
        let minted = happeningShapeNonceStore.reroll(for: dayKey)
        AppLogger.energy.debug("🎲 reroll: minted nonce \(minted) for \(dayKey)")
        objectWillChange.send()
    }

    func availablePaletteHappenings(on date: Date = .now) -> [Happening] {
        let used = Set(todayAdditions.lazy
            .filter { $0.dayKey == Self.dayKey(for: date) }
            .map(\.optionId))
        return configuredPaletteHappenings().filter { !used.contains($0.id) }
    }

    func rekeyTodayAdditions(from oldDayKey: String, to newDayKey: String) {
        guard oldDayKey != newDayKey else { return }
        var didChange = false
        todayAdditions = todayAdditions.map { entry in
            guard entry.dayKey == oldDayKey else { return entry }
            var moved = entry
            moved.dayKey = newDayKey
            didChange = true
            return moved
        }
        guard didChange else { return }
        persistTodayAdditions()
        let movedEntries = todayAdditions.filter { $0.dayKey == newDayKey }
        Task { await SupabaseSyncService.shared.syncOptionEntries(movedEntries) }
    }

    private func persistTodayAdditions() {
        do {
            UserDefaults.stepsTrader().set(
                try JSONEncoder().encode(todayAdditions),
                forKey: SharedKeys.todayAdditions
            )
        } catch {
            AppLogger.energy.error("Failed to encode today additions: \(error.localizedDescription)")
        }
    }

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        happeningStore.load()
        happeningPaletteSelectionStore.load(catalog: happeningStore.all)
        loadTodayAdditions(from: g)
        reconstituteHappeningsFromHistory()
        let rawAnchor = g.object(forKey: SharedKeys.dailyEnergyAnchor)
        AppLogger.energy.debug("📥 loadDailyEnergyState: anchor raw=\(String(describing: rawAnchor)), as Date=\(String(describing: rawAnchor as? Date))")
        guard let anchor = rawAnchor as? Date else {
            AppLogger.energy.debug("📥 loadDailyEnergyState: NO anchor — seeding and loading persisted state")
            g.set(currentDayStart(for: Date.now), forKey: SharedKeys.dailyEnergyAnchor)
            dailySleepHours = g.double(forKey: SharedKeys.dailySleepHours)
            baseEnergyToday = g.integer(forKey: SharedKeys.baseEnergyToday)
            spentStepsToday = g.integer(forKey: SharedKeys.spentStepsToday)
            recoverSelectionsFromCanvasIfNeeded()
            return
        }
        let sameDay = isSameCustomDay(anchor, Date.now)
        AppLogger.energy.debug("📥 loadDailyEnergyState: anchor=\(anchor), isSameDay=\(sameDay), dayEndH=\(self.dayEndHour), dayEndM=\(self.dayEndMinute)")
        if !sameDay {
            AppLogger.energy.debug("📥 loadDailyEnergyState: different day — resetting")
            resetDailyEnergyState()
            return
        }
        dailySleepHours = g.double(forKey: SharedKeys.dailySleepHours)

        baseEnergyToday = g.integer(forKey: SharedKeys.baseEnergyToday)
        spentStepsToday = g.integer(forKey: SharedKeys.spentStepsToday)

        AppLogger.energy.debug("📥 loadDailyEnergyState LOADED: additions=\(self.todayAdditions.count), base=\(self.baseEnergyToday), spent=\(self.spentStepsToday)")
        
        recoverSelectionsFromCanvasIfNeeded()
    }

    private func reconstituteHappeningsFromHistory() {
        var ids = Set(todayAdditions.map(\.optionId))
        for snapshot in loadPastDaySnapshots().values {
            ids.formUnion(snapshot.happeningIds)
        }
        happeningStore.reconstituteOrphans(fromHistoryIds: ids) { id in
            EnergyDefaults.legacyTitle(for: id) ?? id
        }
    }

    private func loadTodayAdditions(from defaults: UserDefaults) {
        guard let data = defaults.data(forKey: SharedKeys.todayAdditions) else {
            migrateLegacySelections(from: defaults)
            return
        }
        do {
            let decoded = try JSONDecoder().decode([OptionEntry].self, from: data)
            let todayKey = Self.dayKey(for: .now)
            todayAdditions = decoded.filter { $0.dayKey == todayKey }
            if todayAdditions.count != decoded.count {
                persistTodayAdditions()
            }
        } catch {
            AppLogger.energy.error("Failed to decode today additions: \(error.localizedDescription)")
            todayAdditions = []
        }
    }

    /// Reads a legacy per-category selection array.
    ///
    /// The old build persisted these as **JSON-encoded `Data`** (its private
    /// `saveStringArray` did `JSONEncoder().encode` then `set(data:)`), so
    /// `stringArray(forKey:)` returns nil for every real user's stored value.
    /// Both shapes are accepted here: `Data` is what is actually on disk, and
    /// the native array form costs one line to tolerate.
    private func legacySelectionIds(_ defaults: UserDefaults, category: String) -> [String] {
        let key = "dailyEnergySelections_v1_\(category)"
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return defaults.stringArray(forKey: key) ?? []
    }

    private func migrateLegacySelections(from defaults: UserDefaults) {
        let legacyIds = ["body", "mind", "heart"].flatMap {
            legacySelectionIds(defaults, category: $0)
        }
        let todayKey = Self.dayKey(for: .now)
        todayAdditions = legacyIds.map { optionId in
            OptionEntry(
                id: UUID().uuidString,
                dayKey: todayKey,
                optionId: optionId,
                colorHex: CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex,
                timestamp: .now,
                assetVariant: nil
            )
        }
        guard !todayAdditions.isEmpty else { return }
        persistTodayAdditions()
        AppLogger.energy.info("Migrated \(self.todayAdditions.count) legacy selections to happenings")
    }

    private func recoverSelectionsFromCanvasIfNeeded() {
        guard todayAdditions.isEmpty else { return }
        let todayKey = Self.dayKey(for: .now)
        guard let canvas = CanvasStorageService.shared.loadCanvas(for: todayKey),
              !canvas.elements.isEmpty else { return }
        todayAdditions = canvas.elements.map { element in
            OptionEntry(
                id: element.id.uuidString,
                dayKey: todayKey,
                optionId: element.optionId,
                colorHex: element.hexColor,
                timestamp: element.createdAt,
                assetVariant: element.assetVariant
            )
        }
        persistTodayAdditions()
    }
    
    func resolveOptionTitle(for optionId: String) -> String {
        if let happening = happeningStore.happening(id: optionId) {
            return happening.localizedTitle()
        }
        return EnergyDefaults.legacyTitle(for: optionId) ?? optionId
    }

    func loadPastDaySnapshots() -> [String: PastDaySnapshot] {
        let url = PersistenceManager.pastDaySnapshotsFileURL
        var decoded: [String: PastDaySnapshot] = [:]

        if (try? url.checkResourceIsReachable()) == true, let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) {
            decoded = loaded
        } else {
            let g = UserDefaults.stepsTrader()
            if let data = g.data(forKey: SharedKeys.pastDaySnapshots),
               let loaded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) {
                decoded = loaded
                if let fileData = try? JSONEncoder().encode(decoded) {
                    try? fileData.write(to: url, options: .atomic)
                }
                g.removeObject(forKey: SharedKeys.pastDaySnapshots)
            } else {
                return [:]
            }
        }

        // History is retained indefinitely for everyone — no retention prune.
        // Pro users see all days; Free users see only the last
        // `SubscriptionGate.freeHistoryDayCount` days (older days are locked,
        // not deleted). See `MeWeekStats.unlockedKeys`.
        return decoded
    }

    private func savePastDaySnapshot(dayKey: String, _ snapshot: PastDaySnapshot) {
        var all = loadPastDaySnapshots()
        all[dayKey] = snapshot
        let url = PersistenceManager.pastDaySnapshotsFileURL
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func mergePastDaySnapshots(_ snapshots: [String: PastDaySnapshot]) {
        guard !snapshots.isEmpty else { return }
        var all = loadPastDaySnapshots()
        for (key, snap) in snapshots {
            if all[key] == nil { all[key] = snap }
        }
        let url = PersistenceManager.pastDaySnapshotsFileURL
        if let data = try? JSONEncoder().encode(all) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func resetDailyEnergyState() {
        let g = UserDefaults.stepsTrader()

        // Capture ALL old-day values FIRST, before any state mutation.
        // This prevents reading stale/new-day values if checkDayBoundary already cleared some keys.
        let oldAnchor = g.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date ?? .distantPast
        let dayKeyToSave = Self.dayKey(for: oldAnchor)
        let savedSpent = g.integer(forKey: SharedKeys.spentStepsToday)
        let savedHappeningIds = todayAdditions.map(\.optionId)
        let savedSleep = g.double(forKey: SharedKeys.dailySleepHours)
        let cachedSteps = g.double(forKey: SharedKeys.cachedStepsToday)
        let savedSteps: Int = cachedSteps > 0 ? Int(cachedSteps) : Int(stepsToday)
        let savedStepsTarget = userStepsTarget
        let savedSleepTarget = userSleepTarget
        let savedBaseEnergy = g.integer(forKey: SharedKeys.baseEnergyToday)

        let daySnapshot = buildPastDaySnapshot(
            savedSpent: savedSpent,
            savedHappeningIds: savedHappeningIds,
            savedSleep: savedSleep,
            cachedSteps: cachedSteps,
            savedSteps: savedSteps,
            savedStepsTarget: savedStepsTarget,
            savedSleepTarget: savedSleepTarget,
            savedBaseEnergy: savedBaseEnergy
        )
        savePastDaySnapshot(dayKey: dayKeyToSave, daySnapshot)
        
        // Sync day snapshot to Supabase (backup historical data)
        Task {
            await SupabaseSyncService.shared.syncDaySnapshot(
                dayKey: dayKeyToSave,
                snapshot: daySnapshot
            )
        }

        // Save a rendered canvas snapshot for history
        if let oldCanvas = CanvasStorageService.shared.loadCanvas(for: dayKeyToSave),
           !oldCanvas.elements.isEmpty {
            CanvasStorageService.shared.saveSnapshot(
                for: dayKeyToSave,
                elements: oldCanvas.elements,
                sleepPoints: oldCanvas.sleepPoints,
                stepsPoints: oldCanvas.stepsPoints,
                sleepColor: Color(hex: oldCanvas.sleepColorHex),
                stepsColor: Color(hex: oldCanvas.stepsColorHex),
                decayNorm: oldCanvas.decayNorm
            )
        }

        dailySleepHours = 0
        stepsToday = 0
        healthStore.hasStepsData = false
        healthStore.clearCachedStepCount()
        g.removeObject(forKey: SharedKeys.cachedStepsToday)
        g.set(false, forKey: SharedKeys.hasStepsData)
        g.removeObject(forKey: "cachedSleepHoursToday")
        todayAdditions = []
        g.removeObject(forKey: SharedKeys.todayAdditions)
        baseEnergyToday = 0
        spentStepsToday = 0
        stepsBalance = 0
        clearDismissedWorkouts()
        persistDailyEnergyState()
        g.set(currentDayStart(for: Date.now), forKey: SharedKeys.dailyEnergyAnchor)
    }

    /// Pure function: builds a PastDaySnapshot from explicit parameters,
    /// avoiding any dependency on mutable in-memory or UserDefaults state.
    private func buildPastDaySnapshot(
        savedSpent: Int,
        savedHappeningIds: [String],
        savedSleep: Double,
        cachedSteps: Double,
        savedSteps: Int,
        savedStepsTarget: Double,
        savedSleepTarget: Double,
        savedBaseEnergy: Int
    ) -> PastDaySnapshot {
        let stepsForInk = cachedSteps > 0 ? cachedSteps : Double(savedSteps)
        let sleepPts = savedSleep > 0
            ? pointsFromSleep(hours: savedSleep)
            : EnergyDefaults.assumedSleepPoints
        let computedInkEarned = min(
            EnergyDefaults.maxBaseEnergy,
            pointsFromSteps(stepsForInk) +
            sleepPts +
            HappeningEconomy.points(forAdditionCount: savedHappeningIds.count)
        )
        let inkEarned = computedInkEarned > 0 ? computedInkEarned : savedBaseEnergy

        return PastDaySnapshot(
            inkEarned: inkEarned,
            inkSpent: savedSpent,
            happeningIds: savedHappeningIds,
            steps: savedSteps,
            sleepHours: savedSleep,
            stepsTarget: savedStepsTarget,
            sleepTargetHours: savedSleepTarget
        )
    }

    @discardableResult
    func resetDailyEnergyIfNeeded() -> Bool {
        let g = UserDefaults.stepsTrader()
        guard let anchor = g.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date else {
            AppLogger.energy.debug("⚠️ resetDailyEnergyIfNeeded: anchor missing — seeding, NOT resetting (additions=\(self.todayAdditions.count))")
            g.set(currentDayStart(for: Date.now), forKey: SharedKeys.dailyEnergyAnchor)
            return false
        }
        if !isSameCustomDay(anchor, Date.now) {
            AppLogger.energy.debug("⚠️ resetDailyEnergyIfNeeded: day changed — resetting (anchor=\(anchor))")
            resetDailyEnergyState()
            return true
        }
        return false
    }

    func persistDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        persistTodayAdditions()
        g.set(dailySleepHours, forKey: SharedKeys.dailySleepHours)
        g.set(baseEnergyToday, forKey: SharedKeys.baseEnergyToday)
        g.set(spentStepsToday, forKey: SharedKeys.spentStepsToday)
        g.set(currentDayStart(for: Date.now), forKey: SharedKeys.stepsBalanceAnchor)
        if g.object(forKey: SharedKeys.dailyEnergyAnchor) == nil {
            g.set(currentDayStart(for: Date.now), forKey: SharedKeys.dailyEnergyAnchor)
        }
    }

    var sleepPointsToday: Int {
        let realPoints = pointsFromSleep(hours: dailySleepHours)
        if dailySleepHours > 0 { return realPoints }
        // HealthKit confirmed no sleep data AND enough time has passed
        // since day boundary to assume the user has slept → gift assumed colors
        if hasSleepData && hasEnoughTimePassedForSleepAssumption {
            return EnergyDefaults.assumedSleepPoints
        }
        return realPoints
    }

    /// True when sleep colors are gifted because HealthKit returned no data.
    var isSleepAssumed: Bool {
        dailySleepHours == 0 && hasSleepData && hasEnoughTimePassedForSleepAssumption
    }

    /// At least 6 hours since the custom day boundary — safe to assume the user slept.
    private var hasEnoughTimePassedForSleepAssumption: Bool {
        let dayStart = currentDayStart(for: Date.now)
        let hoursSinceDayStart = Date.now.timeIntervalSince(dayStart) / 3600
        return hoursSinceDayStart >= 6
    }

    var stepsPointsToday: Int {
        pointsFromSteps(stepsToday)
    }

    private var userSleepTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userSleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
    }
    
    private var userStepsTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userStepsTarget") as? Double ?? EnergyDefaults.stepsTarget
    }
    
    var isRestDayOverrideEnabled: Bool {
        UserDefaults.stepsTrader().bool(forKey: SharedKeys.restDayOverrideEnabled)
    }
    
    // MARK: - Wallpaper Shortcut Tracking
    
    var hasWallpaperShortcut: Bool {
        UserDefaults.stepsTrader().bool(forKey: "hasWallpaperShortcut")
    }
    
    var wallpaperShortcutUses: Int {
        UserDefaults.stepsTrader().integer(forKey: "wallpaperShortcutUses")
    }
    
    func markWallpaperShortcutUsed() {
        let g = UserDefaults.stepsTrader()
        g.set(true, forKey: "hasWallpaperShortcut")
        let current = g.integer(forKey: "wallpaperShortcutUses")
        g.set(current + 1, forKey: "wallpaperShortcutUses")
        syncUserPreferencesToSupabase()
    }
    
    func setRestDayOverrideEnabled(_ enabled: Bool) {
        let g = UserDefaults.stepsTrader()
        g.set(enabled, forKey: SharedKeys.restDayOverrideEnabled)
        // Mirror in standard defaults for widgets/tests that may not use app-group accessor.
        UserDefaults.standard.set(enabled, forKey: SharedKeys.restDayOverrideEnabled)
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }
    
    private func pointsFromSleep(hours: Double) -> Int {
        let target = userSleepTarget
        guard target > 0 else { return 0 }
        let capped = min(max(0, hours), target)
        let ratio = capped / target
        return Int(ratio * Double(EnergyDefaults.sleepMaxPoints))
    }

    private func pointsFromSteps(_ steps: Double) -> Int {
        let target = userStepsTarget
        guard target > 0 else { return 0 }
        let capped = min(max(0, steps), target)
        let ratio = capped / target
        return Int(ratio * Double(EnergyDefaults.stepsMaxPoints))
    }

    @MainActor
    func recalculateDailyEnergy() {
        // Total = steps(20) + sleep(20) + happenings(60) = 100 max
        let stepsForEnergy = stepsToday > 0 ? stepsToday : fallbackCachedSteps()
        let stepsPts = pointsFromSteps(stepsForEnergy)
        let sleepPts = sleepPointsToday
        let total = stepsPts + sleepPts + happeningPointsToday

        AppLogger.energy.info("👣 recalcEnergy: stepsToday=\(Int(self.stepsToday)), stepsForEnergy=\(Int(stepsForEnergy)), stepsPts=\(stepsPts)")
        AppLogger.energy.debug("⚡️ recalculateDailyEnergy: steps=\(stepsPts) + sleep=\(sleepPts)\(self.isSleepAssumed ? " (assumed)" : "") + happenings=\(self.happeningPointsToday) (\(self.todayAdditions.count) additions) = \(total)")
        
        let adjustedTotal = isRestDayOverrideEnabled ? max(total, 30) : total
        
        baseEnergyToday = min(EnergyDefaults.maxBaseEnergy, adjustedTotal)
        
        // Safety net: if in-memory spentStepsToday is 0 but UD has a non-zero value
        // for the same day, restore from UD. This catches any code path that
        // accidentally zeroes the in-memory value without going through resetDailyEnergyState.
        if spentStepsToday == 0 {
            let udG = UserDefaults.stepsTrader()
            let udSpent = udG.integer(forKey: SharedKeys.spentStepsToday)
            if udSpent > 0 {
                let anchor = udG.object(forKey: SharedKeys.dailyEnergyAnchor) as? Date ?? .distantPast
                if isSameCustomDay(anchor, Date.now) {
                    AppLogger.energy.error("⚠️ recalculateDailyEnergy: spentStepsToday=0 but UD has \(udSpent) (same day) — restoring from UD")
                    spentStepsToday = udSpent
                }
            }
        }
        
        let oldBalance = stepsBalance
        stepsBalance = max(0, baseEnergyToday - spentStepsToday)
        AppLogger.energy.debug("⚡️ stepsBalance: \(oldBalance) → \(self.stepsBalance) (base=\(self.baseEnergyToday), spent=\(self.spentStepsToday))")
        
        let g = UserDefaults.stepsTrader()
        g.set(baseEnergyToday, forKey: SharedKeys.baseEnergyToday)

        writeWidgetSnapshot()

        if stepsBalance != oldBalance {
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        AppLogger.energy.debug("⚡️ totalStepsBalance = \(self.totalStepsBalance)")
        
        // Force UI update
        objectWillChange.send()
        
        // Sync daily stats to Supabase (skip during bootstrap)
        guard !isBootstrapping else { return }
        
        let today = Self.dayKey(for: Date.now)
        Task {
            await SupabaseSyncService.shared.syncDailyStats(
                dayKey: today,
                steps: Int(stepsToday),
                sleepHours: dailySleepHours,
                baseEnergy: baseEnergyToday,
                bonusEnergy: 0,
                remainingBalance: totalStepsBalance
            )
        }
        
        // Sync user preferences (targets, day boundary, preferred options, canvas slots)
        syncUserPreferencesToSupabase()
    }
    
    /// Sync user preferences to Supabase (debounced in the service)
    func syncUserPreferencesToSupabase() {
        guard !isBootstrapping else { return }
        let g = UserDefaults.stepsTrader()
        let std = UserDefaults.standard
        Task {
            await SupabaseSyncService.shared.syncUserPreferences(
                stepsTarget: g.object(forKey: SharedKeys.userStepsTarget) as? Double ?? EnergyDefaults.stepsTarget,
                sleepTarget: g.object(forKey: SharedKeys.userSleepTarget) as? Double ?? EnergyDefaults.sleepTargetHours,
                dayEndHour: dayEndHour,
                dayEndMinute: dayEndMinute,
                restDayOverride: isRestDayOverrideEnabled,
                hasWallpaperShortcut: hasWallpaperShortcut,
                wallpaperShortcutUses: wallpaperShortcutUses,
                notifyOneMinBefore: g.object(forKey: SharedKeys.notifyOneMinBefore) as? Bool ?? true,
                notifyWhenTimerOver: g.object(forKey: SharedKeys.notifyWhenTimerOver) as? Bool ?? true,
                notifyCanvasReminder: g.object(forKey: SharedKeys.notifyCanvasReminder) as? Bool ?? false,
                canvasReminderHour: g.object(forKey: SharedKeys.canvasReminderHour) as? Int ?? 21,
                canvasReminderMinute: g.object(forKey: SharedKeys.canvasReminderMinute) as? Int ?? 0,
                notifyDayResetWarning: g.object(forKey: SharedKeys.notifyDayResetWarning) as? Bool ?? true,
                dayResetWarningHours: g.object(forKey: SharedKeys.dayResetWarningHours) as? Int ?? 1,
                hasMediumWidget: g.bool(forKey: SharedKeys.hasMediumWidget),
                hasLargeWidget: g.bool(forKey: SharedKeys.hasLargeWidget),
                lastOpenedAt: Date.now,
                gradientStyle: std.string(forKey: SharedKeys.gradientStyle) ?? GradientStyle.radial.rawValue,
                gradientPalette: std.string(forKey: SharedKeys.gradientPalette) ?? GradientPalette.warmSunset.rawValue,
                userGradientStyle: std.string(forKey: SharedKeys.userGradientStyle) ?? GradientStyle.radial.rawValue,
                userGradientPalette: std.string(forKey: SharedKeys.userGradientPalette) ?? GradientPalette.warmSunset.rawValue,
                dailyRandomThemeEnabled: std.bool(forKey: SharedKeys.dailyRandomThemeEnabled),
                canvasOverlayStyle: g.string(forKey: SharedKeys.canvasOverlayStyle) ?? CanvasOverlayStyle.smudge.rawValue,
                allowedCanvasShapes: CanvasShapeType.allowedByUser.map(\.rawValue)
            )
        }
    }

    // MARK: - Widget Data

    func writeWidgetSnapshot() {
        let g = UserDefaults.stepsTrader()
        WidgetDataFile.write(WidgetSnapshot(
            balance: stepsBalance + g.integer(forKey: SharedKeys.bonusSteps),
            earned: baseEnergyToday,
            stepsPoints: stepsPointsToday,
            sleepPoints: sleepPointsToday,
            bodyPoints: happeningPointsToday,
            mindPoints: 0,
            heartPoints: 0,
            timestamp: Date.now
        ))
    }



    /// Decode-only bridge for old server rows during rollout.
    func applySelections(body: [String], mind: [String], heart: [String]) {
        let todayKey = Self.dayKey(for: .now)
        todayAdditions = (body + mind + heart).map { optionId in
            OptionEntry(
                id: UUID().uuidString,
                dayKey: todayKey,
                optionId: optionId,
                colorHex: CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex,
                timestamp: .now,
                assetVariant: nil
            )
        }
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    // MARK: - Routines (Saved Presets)

    func loadSavedRoutines() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: SharedKeys.savedRoutines),
              let decoded = try? JSONDecoder().decode([EnergyRoutine].self, from: data) else {
            savedRoutines = []
            return
        }
        savedRoutines = decoded
    }

    private func persistSavedRoutines() {
        let g = UserDefaults.stepsTrader()
        do {
            let data = try JSONEncoder().encode(savedRoutines)
            g.set(data, forKey: SharedKeys.savedRoutines)
        } catch {
            AppLogger.energy.error("Failed to encode savedRoutines: \(error.localizedDescription)")
        }
        Task { await SupabaseSyncService.shared.syncSavedRoutines(savedRoutines) }
    }

    /// Save current selections as a named routine.
    func saveCurrentAsRoutine(name: String) {
        let routine = EnergyRoutine(
            name: name,
            happeningIds: todayAdditions.map(\.optionId),
            lastUsed: Date.now
        )
        savedRoutines.append(routine)
        persistSavedRoutines()
    }

    /// Apply a saved routine's selections to today.
    func applyRoutine(_ routine: EnergyRoutine) {
        let known = Set(happeningStore.all.map(\.id))
        for id in routine.happeningIds where known.contains(id) {
            _ = addHappening(
                id: id,
                colorHex: CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
            )
        }

        if let idx = savedRoutines.firstIndex(where: { $0.id == routine.id }) {
            savedRoutines[idx].lastUsed = Date.now
            persistSavedRoutines()
        }
    }

    /// Delete a saved routine.
    func deleteRoutine(_ routine: EnergyRoutine) {
        savedRoutines.removeAll { $0.id == routine.id }
        persistSavedRoutines()
    }

}
