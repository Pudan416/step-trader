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

    /// Adds one concrete occurrence. There is intentionally no deduplication
    /// by happening id and no cap on what reaches the canvas.
    @discardableResult
    func addHappening(
        id: String,
        colorHex: String,
        at date: Date = .now
    ) -> OptionEntry {
        let entry = OptionEntry(
            id: UUID().uuidString,
            dayKey: Self.dayKey(for: date),
            optionId: id,
            colorHex: colorHex,
            timestamp: date,
            assetVariant: nil
        )
        todayAdditions.append(entry)
        happeningStore.recordUse(id: id, at: date)
        recalculateDailyEnergy()
        persistTodayAdditions()
        Task { await SupabaseSyncService.shared.syncOptionEntry(entry) }
        return entry
    }

    func removeAddition(entryId: String) {
        guard let index = todayAdditions.firstIndex(where: { $0.id == entryId }) else { return }
        todayAdditions.remove(at: index)
        recalculateDailyEnergy()
        persistTodayAdditions()
    }

    func paletteOrder() -> [Happening] {
        paletteOrderCache.order(
            for: Self.dayKey(for: .now),
            happenings: happeningStore.all
        ).compactMap { happeningStore.happening(id: $0) }
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
        loadTodayAdditions(from: g)
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

    private func migrateLegacySelections(from defaults: UserDefaults) {
        let legacyIds = ["body", "mind", "heart"].flatMap { raw in
            defaults.stringArray(forKey: "dailyEnergySelections_v1_\(raw)") ?? []
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
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return EnergyDefaults.options.first(where: { $0.id == optionId })?.title(for: lang)
            ?? optionId
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
        // not deleted). See `HistoryView.unlockedKeys`.
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
            bodyIds: savedHappeningIds,
            mindIds: [],
            heartIds: [],
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
                preferredBody: [],
                preferredMind: [],
                preferredHeart: [],
                canvasSlots: [],
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
                bodyCanvasShape: std.string(forKey: SharedKeys.bodyCanvasShape) ?? CanvasShapeType.circle.rawValue,
                mindCanvasShape: std.string(forKey: SharedKeys.mindCanvasShape) ?? CanvasShapeType.snowflake.rawValue,
                heartCanvasShape: std.string(forKey: SharedKeys.heartCanvasShape) ?? CanvasShapeType.rays.rawValue
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
            bodyIds: todayAdditions.map(\.optionId),
            mindIds: [],
            heartIds: [],
            lastUsed: Date.now
        )
        savedRoutines.append(routine)
        persistSavedRoutines()
    }

    /// Apply a saved routine's selections to today.
    func applyRoutine(_ routine: EnergyRoutine) {
        let known = Set(happeningStore.all.map(\.id))
        for id in (routine.bodyIds + routine.mindIds + routine.heartIds) where known.contains(id) {
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
