import Foundation
import SwiftUI
import WidgetKit

// MARK: - Daily Energy Keys (file-scope to avoid @MainActor isolation on static lets)
private let _dailyEnergyAnchorKey = "dailyEnergyAnchor_v1"
private let _dailySleepHoursKey = "dailySleepHours_v1"
private let _baseEnergyTodayKey = "baseEnergyToday_v1"
private let _pastDaySnapshotsKey = "pastDaySnapshots_v1"
private let _dailyCanvasSlotsKey = "dailyChoiceSlots_v1"
private let _customEnergyOptionsKey = "customEnergyOptions_v1"
private let _savedRoutinesKey = "savedEnergyRoutines_v1"
private let _dailyMomentsKey = "dailyMoments_v1"

// MARK: - Daily Energy Management
extension AppModel {
    private func dailySelectionsKey(for category: EnergyCategory) -> String {
        "dailyEnergySelections_v1_\(category.rawValue)"
    }
    
    private func preferredOptionsKey(for category: EnergyCategory) -> String {
        "preferredEnergyOptions_v1_\(category.rawValue)"
    }
    
    // MARK: - Daily energy system
    func loadEnergyPreferences() {
        preferredBodyOptions = loadPreferredOptions(for: .body)
        preferredRestOptions = loadPreferredOptions(for: .mind)
        preferredHeartOptions = loadPreferredOptions(for: .heart)
    }

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let rawAnchor = g.object(forKey: _dailyEnergyAnchorKey)
        AppLogger.energy.debug("📥 loadDailyEnergyState: anchor raw=\(String(describing: rawAnchor)), as Date=\(String(describing: rawAnchor as? Date))")
        guard let anchor = rawAnchor as? Date else {
            AppLogger.energy.debug("📥 loadDailyEnergyState: NO anchor — seeding and loading persisted state")
            g.set(currentDayStart(for: Date.now), forKey: _dailyEnergyAnchorKey)
            dailySleepHours = g.double(forKey: _dailySleepHoursKey)
            dailyBodySelections = loadStringArray(forKey: dailySelectionsKey(for: .body))
            dailyRestSelections = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            dailyHeartSelections = loadStringArray(forKey: dailySelectionsKey(for: .heart))
            let storedBody = loadStringArray(forKey: preferredOptionsKey(for: .body))
            let storedMind = loadStringArray(forKey: preferredOptionsKey(for: .mind))
            let storedHeart = loadStringArray(forKey: preferredOptionsKey(for: .heart))
            if !storedBody.isEmpty { preferredBodyOptions = storedBody }
            if !storedMind.isEmpty { preferredRestOptions = storedMind }
            if !storedHeart.isEmpty { preferredHeartOptions = storedHeart }
            baseEnergyToday = g.integer(forKey: _baseEnergyTodayKey)
            spentStepsToday = g.integer(forKey: SharedKeys.spentStepsToday)
            loadDailyCanvasSlots()
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
        dailySleepHours = g.double(forKey: _dailySleepHoursKey)

        dailyBodySelections = loadStringArray(forKey: dailySelectionsKey(for: .body))
        dailyRestSelections = loadStringArray(forKey: dailySelectionsKey(for: .mind))
        dailyHeartSelections = loadStringArray(forKey: dailySelectionsKey(for: .heart))
        let storedBody = loadStringArray(forKey: preferredOptionsKey(for: .body))
        let storedMind = loadStringArray(forKey: preferredOptionsKey(for: .mind))
        let storedHeart = loadStringArray(forKey: preferredOptionsKey(for: .heart))
        if !storedBody.isEmpty { preferredBodyOptions = storedBody }
        if !storedMind.isEmpty { preferredRestOptions = storedMind }
        if !storedHeart.isEmpty { preferredHeartOptions = storedHeart }

        baseEnergyToday = g.integer(forKey: _baseEnergyTodayKey)
        spentStepsToday = g.integer(forKey: SharedKeys.spentStepsToday)
        dailyMoments = Self.loadSavedMoments(from: g)

        AppLogger.energy.debug("📥 loadDailyEnergyState LOADED: body=\(self.dailyBodySelections), mind=\(self.dailyRestSelections), heart=\(self.dailyHeartSelections), base=\(self.baseEnergyToday), spent=\(self.spentStepsToday)")
        
        loadDailyCanvasSlots()
        
        recoverSelectionsFromCanvasIfNeeded()
    }
    
    func loadCustomEnergyOptions() {
        if let envJSON = ProcessInfo.processInfo.environment["UITEST_CUSTOM_ENERGY_OPTIONS"],
           let data = envJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CustomEnergyOption].self, from: data) {
            customEnergyOptions = decoded
            return
        }

        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: _customEnergyOptionsKey),
              let decoded = try? JSONDecoder().decode([CustomEnergyOption].self, from: data) else {
            customEnergyOptions = []
            return
        }
        customEnergyOptions = decoded
    }
    
    private func saveCustomEnergyOptions() {
        let g = UserDefaults.stepsTrader()
        do {
            let data = try JSONEncoder().encode(customEnergyOptions)
            g.set(data, forKey: _customEnergyOptionsKey)
        } catch {
            AppLogger.energy.error("Failed to encode customEnergyOptions: \(error.localizedDescription)")
            return
        }
        
        // Sync to Supabase
        Task { await SupabaseSyncService.shared.syncCustomActivities(customEnergyOptions) }
    }
    
    func addCustomOption(category: EnergyCategory, titleEn: String, icon: String = "pencil") -> String {
        guard SubscriptionGate.canCreateCustomActivity(isPro: isPro) else {
            AppLogger.app.debug("⛔ addCustomOption blocked — user is not Pro")
            return ""
        }

        let titleEnTrimmed = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleEnTrimmed.isEmpty else { return "" }
        let id = "custom_\(category.rawValue)_\(UUID().uuidString.prefix(8))"
        let custom = CustomEnergyOption(
            id: id,
            titleEn: titleEnTrimmed,
            category: category,
            icon: icon
        )
        customEnergyOptions.append(custom)
        saveCustomEnergyOptions()
        appendOptionToOrder(id: id, category: category)
        objectWillChange.send()
        return id
    }
    
    func customOptions(for category: EnergyCategory) -> [EnergyOption] {
        customEnergyOptions
            .filter { $0.category == category }
            .map { $0.asEnergyOption() }
    }
    
    func customOptionTitle(for optionId: String, lang: String) -> String? {
        customEnergyOptions.first(where: { $0.id == optionId })?.title(for: lang)
    }

    /// Resolve the user-facing title for any option ID (built-in or custom).
    func resolveOptionTitle(for optionId: String) -> String {
        // Ephemeral moments: label stored in dailyMoments, not in the library.
        // Moments are filtered at every sync boundary (see EphemeralMoment), so
        // a `moment_*` ID arriving from server is treated as stale — fall back
        // to the raw ID just in case, but expect this branch to be local-only.
        if EphemeralMoment.isMomentId(optionId) {
            return momentLabel(for: optionId) ?? optionId
        }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        return EnergyDefaults.options.first(where: { $0.id == optionId })?.title(for: lang)
            ?? customOptionTitle(for: optionId, lang: lang)
            ?? optionId
    }

    func updateCustomOption(optionId: String, titleEn: String, icon: String) {
        let titleEnTrimmed = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleEnTrimmed.isEmpty else { return }
        guard let index = customEnergyOptions.firstIndex(where: { $0.id == optionId }) else { return }
        customEnergyOptions[index].titleEn = titleEnTrimmed
        customEnergyOptions[index].icon = icon
        saveCustomEnergyOptions()
        objectWillChange.send()
    }
    
    func deleteCustomOption(optionId: String) {
        guard let index = customEnergyOptions.firstIndex(where: { $0.id == optionId }) else { return }
        let category = customEnergyOptions[index].category
        customEnergyOptions.remove(at: index)
        saveCustomEnergyOptions()
        removeOptionFromOrder(id: optionId, category: category)
        
        var currentPreferred = preferredOptionsIds(for: category)
        currentPreferred.removeAll { $0 == optionId }
        updatePreferredOptions(currentPreferred, category: category)
        
        var currentDaily = dailySelections(for: category)
        currentDaily.removeAll { $0 == optionId }
        setDailySelections(currentDaily, category: category)
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
        objectWillChange.send()
    }
    
    func deleteOption(optionId: String) {
        if optionId.hasPrefix("custom_") {
            deleteCustomOption(optionId: optionId)
            return
        }
        
        guard EnergyDefaults.options.contains(where: { $0.id == optionId }) else { return }
        guard let option = EnergyDefaults.options.first(where: { $0.id == optionId }) else { return }
        let category = option.category
        
        var hidden = hiddenOptions(for: category)
        hidden.insert(optionId)
        saveStringArray(Array(hidden), forKey: hiddenOptionsKey(for: category))
        removeOptionFromOrder(id: optionId, category: category)
        
        var currentPreferred = preferredOptionsIds(for: category)
        currentPreferred.removeAll { $0 == optionId }
        updatePreferredOptions(currentPreferred, category: category)
        
        var currentDaily = dailySelections(for: category)
        currentDaily.removeAll { $0 == optionId }
        setDailySelections(currentDaily, category: category)
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
        objectWillChange.send()
    }
    
    private func loadDailyCanvasSlots() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: _dailyCanvasSlotsKey),
              let decoded = try? JSONDecoder().decode([DayCanvasSlot].self, from: data),
              decoded.count == 4 else {
            syncFromSelectionsToSlots()
            persistDailyCanvasSlots()
            return
        }
        dailyCanvasSlots = decoded
        // IMPORTANT: daily selections are the source of truth.
        // Do not rebuild selections from 4 UI slots on launch, otherwise we can
        // truncate persisted selections and wipe matching canvas elements after restart.
        // Slots are kept as a UI projection and can legitimately be a subset.
    }
    
    /// If UserDefaults lost selection data (e.g. force-quit before flush), reconstruct
    /// from today's canvas JSON file which uses atomic file I/O and survives force-quits.
    private func recoverSelectionsFromCanvasIfNeeded() {
        let allEmpty = dailyBodySelections.isEmpty
            && dailyRestSelections.isEmpty
            && dailyHeartSelections.isEmpty
        guard allEmpty else { return }
        
        let todayKey = Self.dayKey(for: Date.now)
        guard let canvas = CanvasStorageService.shared.loadCanvas(for: todayKey),
              !canvas.elements.isEmpty else { return }
        
        AppLogger.energy.debug("🔧 recoverSelectionsFromCanvas: UserDefaults selections empty but canvas has \(canvas.elements.count) elements — recovering")
        
        var body: [String] = []
        var mind: [String] = []
        var heart: [String] = []
        for el in canvas.elements {
            switch el.category {
            case .body:  if !body.contains(el.optionId) { body.append(el.optionId) }
            case .mind:  if !mind.contains(el.optionId) { mind.append(el.optionId) }
            case .heart: if !heart.contains(el.optionId) { heart.append(el.optionId) }
            }
        }
        
        dailyBodySelections = body
        dailyRestSelections = mind
        dailyHeartSelections = heart
        
        if baseEnergyToday == 0, canvas.inkEarned > 0 {
            baseEnergyToday = canvas.inkEarned
        }
        
        syncFromSelectionsToSlots()
        persistDailyEnergyState()
        
        AppLogger.energy.debug("🔧 Recovered: body=\(body), mind=\(mind), heart=\(heart), base=\(self.baseEnergyToday)")
    }
    
    private func syncFromSelectionsToSlots() {
        var slots: [DayCanvasSlot] = []
        for cat in [EnergyCategory.body, .mind, .heart] {
            let ids = dailySelections(for: cat)
            for id in ids.prefix(4) {
                slots.append(DayCanvasSlot(category: cat, optionId: id))
            }
        }
        while slots.count < 4 {
            slots.append(DayCanvasSlot(category: nil, optionId: nil))
        }
        dailyCanvasSlots = Array(slots.prefix(4))
    }
    
    private func syncFromSlotsToSelections() {
        dailyBodySelections = dailyCanvasSlots.compactMap { $0.category == .body ? $0.optionId : nil }
        dailyRestSelections = dailyCanvasSlots.compactMap { $0.category == .mind ? $0.optionId : nil }
        dailyHeartSelections = dailyCanvasSlots.compactMap { $0.category == .heart ? $0.optionId : nil }
    }
    
    func setDailyCanvasSlot(at index: Int, category: EnergyCategory?, optionId: String?) {
        guard (0..<4).contains(index) else { return }
        let previous = dailyCanvasSlots[index]
        dailyCanvasSlots[index] = DayCanvasSlot(category: category, optionId: optionId)
        syncFromSlotsToSelections()
        recalculateDailyEnergy()
        persistDailyEnergyState()
        
        if let cat = category, let id = optionId {
            if previous.optionId != id {
                Task {
                    await SupabaseSyncService.shared.trackAnalyticsEvent(
                        name: "piece_selected",
                        properties: [
                            "option_id": id,
                            "category": cat.rawValue,
                            "source": "canvas_slot"
                        ]
                    )
                }
            }
        }
    }
    
    private func persistDailyCanvasSlots() {
        let g = UserDefaults.stepsTrader()
        do {
            let data = try JSONEncoder().encode(dailyCanvasSlots)
            g.set(data, forKey: _dailyCanvasSlotsKey)
        } catch {
            AppLogger.energy.error("Failed to encode dailyCanvasSlots: \(error.localizedDescription)")
        }
    }
    
    private static let pastDaySnapshotsRetentionDays = 90

    func loadPastDaySnapshots() -> [String: PastDaySnapshot] {
        let url = PersistenceManager.pastDaySnapshotsFileURL
        var decoded: [String: PastDaySnapshot] = [:]

        if (try? url.checkResourceIsReachable()) == true, let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) {
            decoded = loaded
        } else {
            let g = UserDefaults.stepsTrader()
            if let data = g.data(forKey: _pastDaySnapshotsKey),
               let loaded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) {
                decoded = loaded
                if let fileData = try? JSONEncoder().encode(decoded) {
                    try? fileData.write(to: url, options: .atomic)
                }
                g.removeObject(forKey: _pastDaySnapshotsKey)
            } else {
                return [:]
            }
        }

        let pruned = Self.prunePastDaySnapshotsToRetention(decoded)
        if pruned.count != decoded.count {
            if let data = try? JSONEncoder().encode(pruned) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return pruned
    }

    private static func prunePastDaySnapshotsToRetention(_ snapshots: [String: PastDaySnapshot]) -> [String: PastDaySnapshot] {
        let keys = snapshots.keys.sorted()
        guard keys.count > pastDaySnapshotsRetentionDays else { return snapshots }
        let keep = Set(keys.suffix(pastDaySnapshotsRetentionDays))
        return snapshots.filter { keep.contains($0.key) }
    }

    private func savePastDaySnapshot(dayKey: String, _ snapshot: PastDaySnapshot) {
        var all = loadPastDaySnapshots()
        all[dayKey] = snapshot
        let pruned = Self.prunePastDaySnapshotsToRetention(all)
        let url = PersistenceManager.pastDaySnapshotsFileURL
        if let data = try? JSONEncoder().encode(pruned) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func mergePastDaySnapshots(_ snapshots: [String: PastDaySnapshot]) {
        guard !snapshots.isEmpty else { return }
        var all = loadPastDaySnapshots()
        for (key, snap) in snapshots {
            if all[key] == nil { all[key] = snap }
        }
        let pruned = Self.prunePastDaySnapshotsToRetention(all)
        let url = PersistenceManager.pastDaySnapshotsFileURL
        if let data = try? JSONEncoder().encode(pruned) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func resetDailyEnergyState() {
        let g = UserDefaults.stepsTrader()

        // Capture ALL old-day values FIRST, before any state mutation.
        // This prevents reading stale/new-day values if checkDayBoundary already cleared some keys.
        let oldAnchor = g.object(forKey: _dailyEnergyAnchorKey) as? Date ?? .distantPast
        let dayKeyToSave = Self.dayKey(for: oldAnchor)
        let savedSpent = g.integer(forKey: SharedKeys.spentStepsToday)
        let savedBody = loadStringArray(forKey: dailySelectionsKey(for: .body))
        let savedMind = loadStringArray(forKey: dailySelectionsKey(for: .mind))
        let savedHeart = loadStringArray(forKey: dailySelectionsKey(for: .heart))
        let savedSleep = g.double(forKey: _dailySleepHoursKey)
        let cachedSteps = g.double(forKey: SharedKeys.cachedStepsToday)
        let savedSteps: Int = cachedSteps > 0 ? Int(cachedSteps) : Int(stepsToday)
        let savedStepsTarget = userStepsTarget
        let savedSleepTarget = userSleepTarget
        let savedBaseEnergy = g.integer(forKey: _baseEnergyTodayKey)
        let savedMoments = Self.loadSavedMoments(from: g)

        let daySnapshot = buildPastDaySnapshot(
            savedSpent: savedSpent,
            savedBody: savedBody,
            savedMind: savedMind,
            savedHeart: savedHeart,
            savedSleep: savedSleep,
            cachedSteps: cachedSteps,
            savedSteps: savedSteps,
            savedStepsTarget: savedStepsTarget,
            savedSleepTarget: savedSleepTarget,
            savedBaseEnergy: savedBaseEnergy,
            savedMoments: savedMoments
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
        dailyBodySelections = []
        dailyRestSelections = []
        dailyHeartSelections = []
        dailyMoments = []
        g.removeObject(forKey: _dailyMomentsKey)
        dailyCanvasSlots = (0..<4).map { _ in DayCanvasSlot(category: nil, optionId: nil) }
        baseEnergyToday = 0
        spentStepsToday = 0
        stepsBalance = 0
        clearDismissedWorkouts()
        persistDailyEnergyState()
        g.set(currentDayStart(for: Date.now), forKey: _dailyEnergyAnchorKey)
    }

    /// Pure function: builds a PastDaySnapshot from explicit parameters,
    /// avoiding any dependency on mutable in-memory or UserDefaults state.
    private func buildPastDaySnapshot(
        savedSpent: Int,
        savedBody: [String],
        savedMind: [String],
        savedHeart: [String],
        savedSleep: Double,
        cachedSteps: Double,
        savedSteps: Int,
        savedStepsTarget: Double,
        savedSleepTarget: Double,
        savedBaseEnergy: Int,
        savedMoments: [EphemeralMoment] = []
    ) -> PastDaySnapshot {
        let stepsForInk = cachedSteps > 0 ? cachedSteps : Double(savedSteps)
        let sleepPts = savedSleep > 0
            ? pointsFromSleep(hours: savedSleep)
            : EnergyDefaults.assumedSleepPoints
        let computedInkEarned = min(
            EnergyDefaults.maxBaseEnergy,
            pointsFromSteps(stepsForInk) +
            sleepPts +
            pointsFromSelections(savedBody.count) +
            pointsFromSelections(savedMind.count) +
            pointsFromSelections(savedHeart.count)
        )
        let inkEarned = computedInkEarned > 0 ? computedInkEarned : savedBaseEnergy

        return PastDaySnapshot(
            inkEarned: inkEarned,
            inkSpent: savedSpent,
            bodyIds: savedBody,
            mindIds: savedMind,
            heartIds: savedHeart,
            steps: savedSteps,
            sleepHours: savedSleep,
            stepsTarget: savedStepsTarget,
            sleepTargetHours: savedSleepTarget,
            moments: savedMoments
        )
    }

    @discardableResult
    func resetDailyEnergyIfNeeded() -> Bool {
        let g = UserDefaults.stepsTrader()
        guard let anchor = g.object(forKey: _dailyEnergyAnchorKey) as? Date else {
            AppLogger.energy.debug("⚠️ resetDailyEnergyIfNeeded: anchor missing — seeding, NOT resetting (body=\(self.dailyBodySelections.count), mind=\(self.dailyRestSelections.count), heart=\(self.dailyHeartSelections.count))")
            g.set(currentDayStart(for: Date.now), forKey: _dailyEnergyAnchorKey)
            return false
        }
        if !isSameCustomDay(anchor, Date.now) {
            AppLogger.energy.debug("⚠️ resetDailyEnergyIfNeeded: day changed — resetting (anchor=\(anchor))")
            resetDailyEnergyState()
            return true
        }
        return false
    }

    private func loadPreferredOptions(for category: EnergyCategory) -> [String] {
        let stored = loadStringArray(forKey: preferredOptionsKey(for: category))
        if !stored.isEmpty {
            return stored
        }
        let defaults = EnergyDefaults.coreOptions
            .filter { $0.category == category }
            .map(\.id)
        let fallback = Array(defaults.prefix(EnergyDefaults.maxSelectionsPerCategory))
        saveStringArray(fallback, forKey: preferredOptionsKey(for: category))
        return fallback
    }

    private func optionsOrderKey(for category: EnergyCategory) -> String {
        "energyOptionsOrder_\(category.rawValue)"
    }
    
    private func hiddenOptionsKey(for category: EnergyCategory) -> String {
        "energyOptionsHidden_\(category.rawValue)"
    }

    private func loadStringArray(forKey key: String) -> [String] {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveStringArray(_ value: [String], forKey key: String) {
        let g = UserDefaults.stepsTrader()
        do {
            let data = try JSONEncoder().encode(value)
            g.set(data, forKey: key)
        } catch {
            AppLogger.energy.error("Failed to encode string array for key '\(key)': \(error.localizedDescription)")
        }
    }

    private func preferredOptionsIds(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return preferredBodyOptions
        case .mind: return preferredRestOptions
        case .heart: return preferredHeartOptions
        }
    }
    
    private func allOptions(for category: EnergyCategory) -> [EnergyOption] {
        let defaults = EnergyDefaults.coreOptions.filter { $0.category == category }
        let custom = customOptions(for: category)
        let hidden = hiddenOptions(for: category)
        return (defaults + custom).filter { !hidden.contains($0.id) }
    }
    
    func hiddenOptionIds(for category: EnergyCategory) -> Set<String> {
        Set(loadStringArray(forKey: hiddenOptionsKey(for: category)))
    }

    private func hiddenOptions(for category: EnergyCategory) -> Set<String> {
        hiddenOptionIds(for: category)
    }
    
    func orderedOptions(for category: EnergyCategory) -> [EnergyOption] {
        let all = allOptions(for: category)
        let optionsById = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let storedOrder = loadStringArray(forKey: optionsOrderKey(for: category))
        var ordered: [EnergyOption] = []
        
        for id in storedOrder {
            if let option = optionsById[id] {
                ordered.append(option)
            }
        }
        
        let missing = all.filter { option in
            !ordered.contains(where: { $0.id == option.id })
        }
        ordered.append(contentsOf: missing)
        return ordered
    }
    
    func updateOptionsOrder(_ ids: [String], category: EnergyCategory) {
        let allIds = Set(allOptions(for: category).map(\.id))
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let filtered = unique.filter { allIds.contains($0) }
        let missing = allIds.subtracting(filtered)
        let updated = filtered + Array(missing)
        saveStringArray(updated, forKey: optionsOrderKey(for: category))
        objectWillChange.send()
    }
    
    private func appendOptionToOrder(id: String, category: EnergyCategory) {
        var current = loadStringArray(forKey: optionsOrderKey(for: category))
        if !current.contains(id) {
            current.append(id)
            saveStringArray(current, forKey: optionsOrderKey(for: category))
        }
    }
    
    private func removeOptionFromOrder(id: String, category: EnergyCategory) {
        var current = loadStringArray(forKey: optionsOrderKey(for: category))
        current.removeAll { $0 == id }
        saveStringArray(current, forKey: optionsOrderKey(for: category))
    }

    func preferredOptions(for category: EnergyCategory) -> [EnergyOption] {
        let ids: [String]
        switch category {
        case .body: ids = preferredBodyOptions
        case .mind: ids = preferredRestOptions
        case .heart: ids = preferredHeartOptions
        }
        let all = allOptions(for: category)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }


    func updatePreferredOptions(_ ids: [String], category: EnergyCategory) {
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let trimmed = Array(unique.prefix(EnergyDefaults.maxSelectionsPerCategory))
        switch category {
        case .body: preferredBodyOptions = trimmed
        case .mind: preferredRestOptions = trimmed
        case .heart: preferredHeartOptions = trimmed
        }
        let filteredDaily = dailySelections(for: category).filter { trimmed.contains($0) }
        setDailySelections(filteredDaily, category: category)
        saveStringArray(trimmed, forKey: preferredOptionsKey(for: category))
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    func togglePreferredOption(optionId: String, category: EnergyCategory) {
        var selections: [String]
        switch category {
        case .body: selections = preferredBodyOptions
        case .mind: selections = preferredRestOptions
        case .heart: selections = preferredHeartOptions
        }
        let wasSelected = selections.contains(optionId)
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        updatePreferredOptions(selections, category: category)
        
        if !wasSelected && selections.contains(optionId) {
            Task {
                await SupabaseSyncService.shared.trackAnalyticsEvent(
                    name: "piece_selected",
                    properties: [
                        "option_id": optionId,
                        "category": category.rawValue,
                        "source": "preferred_selection"
                    ]
                )
            }
        }
    }

    func isPreferredOptionSelected(_ optionId: String, category: EnergyCategory) -> Bool {
        switch category {
        case .body: return preferredBodyOptions.contains(optionId)
        case .mind: return preferredRestOptions.contains(optionId)
        case .heart: return preferredHeartOptions.contains(optionId)
        }
    }

    func toggleDailySelection(optionId: String, category: EnergyCategory) {
        var selections = dailySelections(for: category)
        let wasSelected = selections.contains(optionId)
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        setDailySelections(selections, category: category)
        syncFromSelectionsToSlots()
        // Recalculate BEFORE persisting so baseEnergyToday is up-to-date when saved.
        // Previously, persistDailyEnergyState saved the stale value, and if the app
        // crashed before recalculate finished, baseEnergyToday would be wrong on reload.
        recalculateDailyEnergy()
        persistDailyEnergyState()
        
        if !wasSelected && selections.contains(optionId) {
            Task {
                await SupabaseSyncService.shared.trackAnalyticsEvent(
                    name: "piece_selected",
                    properties: [
                        "option_id": optionId,
                        "category": category.rawValue,
                        "source": "daily_canvas"
                    ]
                )
            }
        }
    }

    func isDailySelected(_ optionId: String, category: EnergyCategory) -> Bool {
        dailySelections(for: category).contains(optionId)
    }

    // MARK: - Ephemeral Moments

    /// Decode persisted `dailyMoments` from UserDefaults, returning `[]` on
    /// missing data or decode failure. Centralized so loaders and the
    /// pre-reset snapshot path stay in sync.
    static func loadSavedMoments(from defaults: UserDefaults) -> [EphemeralMoment] {
        guard let data = defaults.data(forKey: _dailyMomentsKey),
              let decoded = try? JSONDecoder().decode([EphemeralMoment].self, from: data)
        else { return [] }
        return decoded
    }

    /// Add a one-time moment for today.
    /// The moment's ID is added to the appropriate category selection so the
    /// energy economy is unaffected — moment counts like a regular activity.
    @discardableResult
    func addMoment(label: String, icon: String, category: EnergyCategory) -> EphemeralMoment? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppLogger.energy.debug("⚡️ addMoment: empty label, skipping")
            return nil
        }
        guard dailySelections(for: category).count < EnergyDefaults.maxSelectionsPerCategory else {
            AppLogger.energy.debug("⚡️ addMoment: category \(category.rawValue) is full, skipping")
            return nil
        }
        let dayKey = AppModel.dayKey(for: Date.now)
        let moment = EphemeralMoment(label: trimmed, icon: icon, category: category, dayKey: dayKey)
        dailyMoments.append(moment)
        // Register the ID in the category selection so it contributes energy
        var selections = dailySelections(for: category)
        selections.append(moment.id)
        setDailySelections(selections, category: category)
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
        AppLogger.energy.debug("✦ addMoment: '\(trimmed)' → \(category.rawValue) [\(moment.id)]")
        return moment
    }

    /// Remove a moment logged today (undo support).
    func removeMoment(id: String) {
        guard let moment = dailyMoments.first(where: { $0.id == id }) else { return }
        dailyMoments.removeAll { $0.id == id }
        var selections = dailySelections(for: moment.category)
        selections.removeAll { $0 == id }
        setDailySelections(selections, category: moment.category)
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    /// Resolve a moment label for a given optionId (used by resolveOptionTitle).
    func momentLabel(for optionId: String) -> String? {
        dailyMoments.first(where: { $0.id == optionId })?.label
    }

    func dailySelectionsCount(for category: EnergyCategory) -> Int {
        dailySelections(for: category).count
    }

    /// Whether the per-category daily limit of 4 cards has been reached.
    func isDailyLimitReached(for category: EnergyCategory) -> Bool {
        dailySelectionsCount(for: category) >= EnergyDefaults.maxSelectionsPerCategory
    }

    func dailySelections(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return dailyBodySelections
        case .mind: return dailyRestSelections
        case .heart: return dailyHeartSelections
        }
    }

    private func setDailySelections(_ selections: [String], category: EnergyCategory) {
        switch category {
        case .body: dailyBodySelections = selections
        case .mind: dailyRestSelections = selections
        case .heart: dailyHeartSelections = selections
        }
    }

    func persistDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        g.set(dailySleepHours, forKey: _dailySleepHoursKey)
        saveStringArray(dailyBodySelections, forKey: dailySelectionsKey(for: .body))
        saveStringArray(dailyRestSelections, forKey: dailySelectionsKey(for: .mind))
        saveStringArray(dailyHeartSelections, forKey: dailySelectionsKey(for: .heart))
        if let data = try? JSONEncoder().encode(dailyMoments) {
            g.set(data, forKey: _dailyMomentsKey)
        }
        g.set(baseEnergyToday, forKey: _baseEnergyTodayKey)
        g.set(spentStepsToday, forKey: SharedKeys.spentStepsToday)
        g.set(currentDayStart(for: Date.now), forKey: SharedKeys.stepsBalanceAnchor)
        persistDailyCanvasSlots()
        if g.object(forKey: _dailyEnergyAnchorKey) == nil {
            g.set(currentDayStart(for: Date.now), forKey: _dailyEnergyAnchorKey)
        }
        // Sync daily selections to Supabase (skip during bootstrap to avoid overwriting server data)
        guard !isBootstrapping else {
            AppLogger.energy.debug("🔄 persistDailyEnergyState: skipping sync during bootstrap")
            return
        }
        
        let today = Self.dayKey(for: Date.now)
        AppLogger.energy.debug("🔄 persistDailyEnergyState calling syncDailySelections for \(today)")
        AppLogger.energy.debug("🔄   body: \(self.dailyBodySelections)")
        AppLogger.energy.debug("🔄   mind: \(self.dailyRestSelections)")
        AppLogger.energy.debug("🔄   heart: \(self.dailyHeartSelections)")
        Task {
            await SupabaseSyncService.shared.syncDailySelections(
                dayKey: today,
                activityIds: dailyBodySelections,
                recoveryIds: dailyRestSelections,
                joysIds: dailyHeartSelections
            )
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

    var bodyPointsToday: Int {
        pointsFromSelections(dailyBodySelections.count)
    }

    var mindPointsToday: Int {
        pointsFromSelections(dailyRestSelections.count)
    }

    var heartPointsToday: Int {
        pointsFromSelections(dailyHeartSelections.count)
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

    private func pointsFromSelections(_ count: Int) -> Int {
        min(count, EnergyDefaults.maxSelectionsPerCategory) * EnergyDefaults.selectionPoints
    }

    @MainActor
    func recalculateDailyEnergy() {
        // Total = steps(20) + sleep(20) + body(20) + mind(20) + heart(20) = 100 max
        let stepsForEnergy = stepsToday > 0 ? stepsToday : fallbackCachedSteps()
        let stepsPts = pointsFromSteps(stepsForEnergy)
        let sleepPts = sleepPointsToday
        let total = stepsPts + sleepPts + bodyPointsToday + mindPointsToday + heartPointsToday

        AppLogger.energy.info("👣 recalcEnergy: stepsToday=\(Int(self.stepsToday)), stepsForEnergy=\(Int(stepsForEnergy)), stepsPts=\(stepsPts)")
        AppLogger.energy.debug("⚡️ recalculateDailyEnergy: steps=\(stepsPts) + sleep=\(sleepPts)\(self.isSleepAssumed ? " (assumed)" : "") + body=\(self.bodyPointsToday) + mind=\(self.mindPointsToday) + heart=\(self.heartPointsToday) = \(total)")
        
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
        g.set(baseEnergyToday, forKey: _baseEnergyTodayKey)

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
                preferredBody: preferredBodyOptions,
                preferredMind: preferredRestOptions,
                preferredHeart: preferredHeartOptions,
                canvasSlots: dailyCanvasSlots,
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
            bodyPoints: bodyPointsToday,
            mindPoints: mindPointsToday,
            heartPoints: heartPointsToday,
            timestamp: Date.now
        ))
    }



    /// Check if an option ID still exists (built-in or custom, not hidden).
    private func optionExists(_ id: String, category: EnergyCategory) -> Bool {
        let all = orderedOptions(for: category)
        return all.contains { $0.id == id }
    }

    /// Bulk-set all three category selections, recalculate, and persist.
    func applySelections(body: [String], mind: [String], heart: [String]) {
        dailyBodySelections = Array(body.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyRestSelections = Array(mind.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyHeartSelections = Array(heart.prefix(EnergyDefaults.maxSelectionsPerCategory))
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    // MARK: - Routines (Saved Presets)

    func loadSavedRoutines() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: _savedRoutinesKey),
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
            g.set(data, forKey: _savedRoutinesKey)
        } catch {
            AppLogger.energy.error("Failed to encode savedRoutines: \(error.localizedDescription)")
        }
        Task { await SupabaseSyncService.shared.syncSavedRoutines(savedRoutines) }
    }

    /// Save current selections as a named routine.
    /// Ephemeral moments are stripped — a routine is a reusable template and a
    /// one-time moment ID would never resolve on a future day (and shouldn't
    /// leave this device via the routine sync either).
    func saveCurrentAsRoutine(name: String) {
        let routine = EnergyRoutine(
            name: name,
            bodyIds: EphemeralMoment.filteredOutOfSync(dailyBodySelections),
            mindIds: EphemeralMoment.filteredOutOfSync(dailyRestSelections),
            heartIds: EphemeralMoment.filteredOutOfSync(dailyHeartSelections),
            lastUsed: Date.now
        )
        savedRoutines.append(routine)
        persistSavedRoutines()
    }

    /// Apply a saved routine's selections to today.
    func applyRoutine(_ routine: EnergyRoutine) {
        let validBody = routine.bodyIds.filter { optionExists($0, category: .body) }
        let validMind = routine.mindIds.filter { optionExists($0, category: .mind) }
        let validHeart = routine.heartIds.filter { optionExists($0, category: .heart) }
        applySelections(body: validBody, mind: validMind, heart: validHeart)

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
