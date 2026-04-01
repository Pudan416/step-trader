import Foundation
import SwiftUI
import WidgetKit

// MARK: - Daily Energy Management
extension AppModel {
    // MARK: - Daily energy system keys
    private var dailyEnergyAnchorKey: String { "dailyEnergyAnchor_v1" }
    private var dailySleepHoursKey: String { "dailySleepHours_v1" }
    private var baseEnergyTodayKey: String { "baseEnergyToday_v1" }
    
    private func dailySelectionsKey(for category: EnergyCategory) -> String {
        "dailyEnergySelections_v1_\(category.rawValue)"
    }
    
    private var pastDaySnapshotsKey: String { "pastDaySnapshots_v1" }
    private var dailyCanvasSlotsKey: String { "dailyChoiceSlots_v1" }
    private var customEnergyOptionsKey: String { "customEnergyOptions_v1" }
    
    private func preferredOptionsKey(for category: EnergyCategory) -> String {
        "preferredEnergyOptions_v1_\(category.rawValue)"
    }
    
    // MARK: - Daily energy system
    func loadEnergyPreferences() {
        preferredActivityOptions = loadPreferredOptions(for: .body)
        preferredRestOptions = loadPreferredOptions(for: .mind)
        preferredJoysOptions = loadPreferredOptions(for: .heart)
    }

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let rawAnchor = g.object(forKey: dailyEnergyAnchorKey)
        AppLogger.energy.debug("📥 loadDailyEnergyState: anchor raw=\(String(describing: rawAnchor)), as Date=\(String(describing: rawAnchor as? Date))")
        guard let anchor = rawAnchor as? Date else {
            AppLogger.energy.debug("📥 loadDailyEnergyState: NO anchor — seeding and loading persisted state")
            g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
            dailySleepHours = g.double(forKey: dailySleepHoursKey)
            dailyActivitySelections = loadStringArray(forKey: dailySelectionsKey(for: .body))
            dailyRestSelections = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            dailyJoysSelections = loadStringArray(forKey: dailySelectionsKey(for: .heart))
            preferredActivityOptions = loadStringArray(forKey: preferredOptionsKey(for: .body))
            preferredRestOptions = loadStringArray(forKey: preferredOptionsKey(for: .mind))
            preferredJoysOptions = loadStringArray(forKey: preferredOptionsKey(for: .heart))
            baseEnergyToday = g.integer(forKey: baseEnergyTodayKey)
            loadDailyCanvasSlots()
            recoverSelectionsFromCanvasIfNeeded()
            return
        }
        let sameDay = isSameCustomDay(anchor, Date())
        AppLogger.energy.debug("📥 loadDailyEnergyState: anchor=\(anchor), isSameDay=\(sameDay), dayEndH=\(self.dayEndHour), dayEndM=\(self.dayEndMinute)")
        if !sameDay {
            AppLogger.energy.debug("📥 loadDailyEnergyState: different day — resetting")
            resetDailyEnergyState()
            return
        }
        dailySleepHours = g.double(forKey: dailySleepHoursKey)

        dailyActivitySelections = loadStringArray(forKey: dailySelectionsKey(for: .body))
        dailyRestSelections = loadStringArray(forKey: dailySelectionsKey(for: .mind))
        dailyJoysSelections = loadStringArray(forKey: dailySelectionsKey(for: .heart))
        preferredActivityOptions = loadStringArray(forKey: preferredOptionsKey(for: .body))
        preferredRestOptions = loadStringArray(forKey: preferredOptionsKey(for: .mind))
        preferredJoysOptions = loadStringArray(forKey: preferredOptionsKey(for: .heart))

        baseEnergyToday = g.integer(forKey: baseEnergyTodayKey)
        
        AppLogger.energy.debug("📥 loadDailyEnergyState LOADED: body=\(self.dailyActivitySelections), mind=\(self.dailyRestSelections), heart=\(self.dailyJoysSelections), base=\(self.baseEnergyToday)")
        
        loadDailyCanvasSlots()
        
        recoverSelectionsFromCanvasIfNeeded()
    }
    
    func loadCustomEnergyOptions() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: customEnergyOptionsKey),
              let decoded = try? JSONDecoder().decode([CustomEnergyOption].self, from: data) else {
            customEnergyOptions = []
            return
        }
        customEnergyOptions = decoded
    }
    
    private func saveCustomEnergyOptions() {
        let g = UserDefaults.stepsTrader()
        guard let data = try? JSONEncoder().encode(customEnergyOptions) else { return }
        g.set(data, forKey: customEnergyOptionsKey)
        
        // Sync to Supabase
        Task { await SupabaseSyncService.shared.syncCustomActivities(customEnergyOptions) }
    }
    
    func addCustomOption(category: EnergyCategory, titleEn: String, titleRu: String, icon: String = "pencil") -> String {
        let titleEnTrimmed = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleRuTrimmed = titleRu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleEnTrimmed.isEmpty else { return "" }
        let id = "custom_\(category.rawValue)_\(UUID().uuidString.prefix(8))"
        let custom = CustomEnergyOption(
            id: id,
            titleEn: titleEnTrimmed,
            titleRu: titleRuTrimmed.isEmpty ? titleEnTrimmed : titleRuTrimmed,
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
        EnergyDefaults.options.first(where: { $0.id == optionId })?.title(for: "en")
            ?? customOptionTitle(for: optionId, lang: "en")
            ?? optionId
    }

    func updateCustomOption(optionId: String, titleEn: String, titleRu: String, icon: String) {
        let titleEnTrimmed = titleEn.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleRuTrimmed = titleRu.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titleEnTrimmed.isEmpty else { return }
        guard let index = customEnergyOptions.firstIndex(where: { $0.id == optionId }) else { return }
        customEnergyOptions[index].titleEn = titleEnTrimmed
        customEnergyOptions[index].titleRu = titleRuTrimmed.isEmpty ? titleEnTrimmed : titleRuTrimmed
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
        // Don't allow deleting built-in options
        if EnergyDefaults.options.contains(where: { $0.id == optionId }) {
            return
        }
        
        if optionId.hasPrefix("custom_") {
            deleteCustomOption(optionId: optionId)
            return
        }
        
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
        guard let data = g.data(forKey: dailyCanvasSlotsKey),
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
        let allEmpty = dailyActivitySelections.isEmpty
            && dailyRestSelections.isEmpty
            && dailyJoysSelections.isEmpty
        guard allEmpty else { return }
        
        let todayKey = Self.dayKey(for: Date())
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
        
        dailyActivitySelections = body
        dailyRestSelections = mind
        dailyJoysSelections = heart
        
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
        dailyActivitySelections = dailyCanvasSlots.compactMap { $0.category == .body ? $0.optionId : nil }
        dailyRestSelections = dailyCanvasSlots.compactMap { $0.category == .mind ? $0.optionId : nil }
        dailyJoysSelections = dailyCanvasSlots.compactMap { $0.category == .heart ? $0.optionId : nil }
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
        if let data = try? JSONEncoder().encode(dailyCanvasSlots) {
            g.set(data, forKey: dailyCanvasSlotsKey)
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
            if let data = g.data(forKey: pastDaySnapshotsKey),
               let loaded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) {
                decoded = loaded
                if let fileData = try? JSONEncoder().encode(decoded) {
                    try? fileData.write(to: url, options: .atomic)
                }
                g.removeObject(forKey: pastDaySnapshotsKey)
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

    private func resetDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        let dayKeyToSave = Self.dayKey(for: anchor)

        // Build snapshot from PERSISTED state (UserDefaults), not in-memory — on new-day launch in-memory is still default 0/empty
        let savedSpent = g.integer(forKey: SharedKeys.spentStepsToday)
        let savedActivity = loadStringArray(forKey: dailySelectionsKey(for: .body))
        let savedCreativity = loadStringArray(forKey: dailySelectionsKey(for: .mind))
        let savedJoys = loadStringArray(forKey: dailySelectionsKey(for: .heart))
        let savedSleep = g.double(forKey: dailySleepHoursKey)
        let cachedSteps = g.double(forKey: SharedKeys.cachedStepsToday)
        let savedSteps: Int = cachedSteps > 0 ? Int(cachedSteps) : Int(stepsToday)
        let savedStepsTarget = userStepsTarget
        let savedSleepTarget = userSleepTarget

        // Recompute inkEarned from raw persisted values instead of trusting baseEnergyTodayKey.
        // baseEnergyTodayKey can be stale (=0) when HealthKit delivers steps/sleep data after
        // a day-boundary reset, because the Combine-debounced recalculateDailyEnergy() fires
        // 200ms after the reset — too late. Computing inline guarantees correctness.
        let stepsForInk = cachedSteps > 0 ? cachedSteps : stepsToday
        let computedInkEarned = min(
            EnergyDefaults.maxBaseEnergy,
            pointsFromSteps(stepsForInk) +
            pointsFromSleep(hours: savedSleep) +
            pointsFromSelections(savedActivity.count) +
            pointsFromSelections(savedCreativity.count) +
            pointsFromSelections(savedJoys.count)
        )
        // Fall back to the persisted key only if computation yields 0 (no raw data available).
        let savedBaseEnergy = g.integer(forKey: baseEnergyTodayKey)
        let inkEarned = computedInkEarned > 0 ? computedInkEarned : savedBaseEnergy

        let daySnapshot = PastDaySnapshot(
            inkEarned: inkEarned,
            inkSpent: savedSpent,
            bodyIds: savedActivity,
            mindIds: savedCreativity,
            heartIds: savedJoys,
            steps: savedSteps,
            sleepHours: savedSleep,
            stepsTarget: savedStepsTarget,
            sleepTargetHours: savedSleepTarget
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
        g.removeObject(forKey: SharedKeys.cachedStepsToday)
        g.set(false, forKey: SharedKeys.hasStepsData)
        dailyActivitySelections = []
        dailyRestSelections = []
        dailyJoysSelections = []
        dailyCanvasSlots = (0..<4).map { _ in DayCanvasSlot(category: nil, optionId: nil) }
        baseEnergyToday = 0
        clearDismissedWorkouts()
        persistDailyEnergyState()
        g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
    }

    @discardableResult
    func resetDailyEnergyIfNeeded() -> Bool {
        let g = UserDefaults.stepsTrader()
        guard let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date else {
            AppLogger.energy.debug("⚠️ resetDailyEnergyIfNeeded: anchor missing — seeding, NOT resetting (body=\(self.dailyActivitySelections.count), mind=\(self.dailyRestSelections.count), heart=\(self.dailyJoysSelections.count))")
            g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
            return false
        }
        if !isSameCustomDay(anchor, Date()) {
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
        let defaults = EnergyDefaults.options
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
        if let data = try? JSONEncoder().encode(value) {
            g.set(data, forKey: key)
        }
    }

    private func preferredOptionsIds(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return preferredActivityOptions
        case .mind: return preferredRestOptions
        case .heart: return preferredJoysOptions
        }
    }
    
    private func allOptions(for category: EnergyCategory) -> [EnergyOption] {
        let defaults = EnergyDefaults.options.filter { $0.category == category }
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
        case .body: ids = preferredActivityOptions
        case .mind: ids = preferredRestOptions
        case .heart: ids = preferredJoysOptions
        }
        let all = allOptions(for: category)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }


    func updatePreferredOptions(_ ids: [String], category: EnergyCategory) {
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let trimmed = Array(unique.prefix(EnergyDefaults.maxSelectionsPerCategory))
        switch category {
        case .body: preferredActivityOptions = trimmed
        case .mind: preferredRestOptions = trimmed
        case .heart: preferredJoysOptions = trimmed
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
        case .body: selections = preferredActivityOptions
        case .mind: selections = preferredRestOptions
        case .heart: selections = preferredJoysOptions
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
        case .body: return preferredActivityOptions.contains(optionId)
        case .mind: return preferredRestOptions.contains(optionId)
        case .heart: return preferredJoysOptions.contains(optionId)
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

    func dailySelectionsCount(for category: EnergyCategory) -> Int {
        dailySelections(for: category).count
    }

    /// Whether the per-category daily limit of 4 activities has been reached.
    func isDailyLimitReached(for category: EnergyCategory) -> Bool {
        dailySelectionsCount(for: category) >= EnergyDefaults.maxSelectionsPerCategory
    }

    func dailySelections(for category: EnergyCategory) -> [String] {
        switch category {
        case .body: return dailyActivitySelections
        case .mind: return dailyRestSelections
        case .heart: return dailyJoysSelections
        }
    }

    private func setDailySelections(_ selections: [String], category: EnergyCategory) {
        switch category {
        case .body: dailyActivitySelections = selections
        case .mind: dailyRestSelections = selections
        case .heart: dailyJoysSelections = selections
        }
    }

    func persistDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        g.set(dailySleepHours, forKey: dailySleepHoursKey)
        saveStringArray(dailyActivitySelections, forKey: dailySelectionsKey(for: .body))
        saveStringArray(dailyRestSelections, forKey: dailySelectionsKey(for: .mind))
        saveStringArray(dailyJoysSelections, forKey: dailySelectionsKey(for: .heart))
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)
        persistDailyCanvasSlots()
        if g.object(forKey: dailyEnergyAnchorKey) == nil {
            g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
        }
        // Sync daily selections to Supabase (skip during bootstrap to avoid overwriting server data)
        guard !isBootstrapping else {
            AppLogger.energy.debug("🔄 persistDailyEnergyState: skipping sync during bootstrap")
            return
        }
        
        let today = Self.dayKey(for: Date())
        AppLogger.energy.debug("🔄 persistDailyEnergyState calling syncDailySelections for \(today)")
        AppLogger.energy.debug("🔄   activities: \(self.dailyActivitySelections)")
        AppLogger.energy.debug("🔄   creativity: \(self.dailyRestSelections)")
        AppLogger.energy.debug("🔄   joys: \(self.dailyJoysSelections)")
        Task {
            await SupabaseSyncService.shared.syncDailySelections(
                dayKey: today,
                activityIds: dailyActivitySelections,
                recoveryIds: dailyRestSelections,
                joysIds: dailyJoysSelections
            )
        }
    }

    var sleepPointsToday: Int {
        pointsFromSleep(hours: dailySleepHours)
    }

    var stepsPointsToday: Int {
        pointsFromSteps(stepsToday)
    }

    /// Body: 4 chosen cards × 5 colors = 20 max.
    var activityPointsToday: Int {
        pointsFromSelections(dailyActivitySelections.count)
    }

    /// Mind: 4 chosen cards × 5 colors = 20 max.
    var creativityPointsToday: Int {
        pointsFromSelections(dailyRestSelections.count)
    }

    /// Heart: 4 chosen cards × 5 colors = 20 max.
    var joysCategoryPointsToday: Int {
        pointsFromSelections(dailyJoysSelections.count)
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
        let capped = min(max(0, hours), target)
        let ratio = capped / target
        return Int(ratio * Double(EnergyDefaults.sleepMaxPoints))
    }

    private func pointsFromSteps(_ steps: Double) -> Int {
        let target = userStepsTarget
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
        let sleepPts = pointsFromSleep(hours: dailySleepHours)
        let total = stepsPts + sleepPts + activityPointsToday + creativityPointsToday + joysCategoryPointsToday

        AppLogger.energy.debug("⚡️ recalculateDailyEnergy: steps=\(stepsPts) + sleep=\(sleepPts) + body=\(self.activityPointsToday) + mind=\(self.creativityPointsToday) + heart=\(self.joysCategoryPointsToday) = \(total)")
        // Assertion removed — was tautological (BUG-R08)
        
        // Rest day override grants a minimum base of 30 colors.
        let adjustedTotal = isRestDayOverrideEnabled ? max(total, 30) : total
        
        // Base energy capped at maximum 100
        baseEnergyToday = min(EnergyDefaults.maxBaseEnergy, adjustedTotal)
        
        // NOTE: Do NOT cap spentStepsToday to baseEnergyToday here.
        // If a user resets the canvas (clearing category selections → lower baseEnergyToday),
        // capping spent would permanently erase the spent amount, creating free EXP
        // when activities are re-added. max(0, ...) on balance handles the display correctly:
        // balance stays at 0 until re-earned energy exceeds the original spent amount.
        
        let oldBalance = stepsBalance
        stepsBalance = max(0, baseEnergyToday - spentStepsToday)
        AppLogger.energy.debug("⚡️ stepsBalance: \(oldBalance) → \(self.stepsBalance) (base=\(self.baseEnergyToday), spent=\(self.spentStepsToday))")
        
        let g = UserDefaults.stepsTrader()
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)

        writeWidgetSnapshot()

        if stepsBalance != oldBalance {
            WidgetCenter.shared.reloadAllTimelines()
        }
        
        AppLogger.energy.debug("⚡️ totalStepsBalance = \(self.totalStepsBalance)")
        
        // Force UI update
        objectWillChange.send()
        
        // Sync daily stats to Supabase (skip during bootstrap)
        guard !isBootstrapping else { return }
        
        let today = Self.dayKey(for: Date())
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
        Task {
            await SupabaseSyncService.shared.syncUserPreferences(
                stepsTarget: g.object(forKey: SharedKeys.userStepsTarget) as? Double ?? EnergyDefaults.stepsTarget,
                sleepTarget: g.object(forKey: SharedKeys.userSleepTarget) as? Double ?? EnergyDefaults.sleepTargetHours,
                dayEndHour: dayEndHour,
                dayEndMinute: dayEndMinute,
                restDayOverride: isRestDayOverrideEnabled,
                preferredBody: preferredActivityOptions,
                preferredMind: preferredRestOptions,
                preferredHeart: preferredJoysOptions,
                canvasSlots: dailyCanvasSlots,
                hasWallpaperShortcut: hasWallpaperShortcut,
                wallpaperShortcutUses: wallpaperShortcutUses,
                notifyOneMinBefore: g.object(forKey: SharedKeys.notifyOneMinBefore) as? Bool ?? true,
                notifyWhenTimerOver: g.object(forKey: SharedKeys.notifyWhenTimerOver) as? Bool ?? true,
                notifyCanvasReminder: g.object(forKey: SharedKeys.notifyCanvasReminder) as? Bool ?? true,
                canvasReminderHour: g.object(forKey: SharedKeys.canvasReminderHour) as? Int ?? 21,
                canvasReminderMinute: g.object(forKey: SharedKeys.canvasReminderMinute) as? Int ?? 0,
                notifyDayResetWarning: g.object(forKey: SharedKeys.notifyDayResetWarning) as? Bool ?? true,
                dayResetWarningHours: g.object(forKey: SharedKeys.dayResetWarningHours) as? Int ?? 1,
                hasMediumWidget: g.bool(forKey: SharedKeys.hasMediumWidget),
                hasLargeWidget: g.bool(forKey: SharedKeys.hasLargeWidget),
                lastOpenedAt: Date()
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
            bodyPoints: activityPointsToday,
            mindPoints: creativityPointsToday,
            heartPoints: joysCategoryPointsToday,
            timestamp: Date()
        ))
    }

    // MARK: - Repeat Yesterday

    /// Returns yesterday's snapshot if available.
    func yesterdaySnapshot() -> PastDaySnapshot? {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        let key = Self.dayKey(for: yesterday)
        let all = loadPastDaySnapshots()
        return all[key]
    }

    /// Whether today has no Body/Mind/Heart selections yet and yesterday had some.
    var canRepeatYesterday: Bool {
        let todayEmpty = dailyActivitySelections.isEmpty
            && dailyRestSelections.isEmpty
            && dailyJoysSelections.isEmpty
        guard todayEmpty else { return false }
        guard let snap = yesterdaySnapshot() else { return false }
        return !snap.bodyIds.isEmpty || !snap.mindIds.isEmpty || !snap.heartIds.isEmpty
    }

    /// Apply yesterday's Body/Mind/Heart selections to today.
    func repeatYesterday() {
        guard let snap = yesterdaySnapshot() else { return }
        let validBody = snap.bodyIds.filter { optionExists($0, category: .body) }
        let validMind = snap.mindIds.filter { optionExists($0, category: .mind) }
        let validHeart = snap.heartIds.filter { optionExists($0, category: .heart) }
        applySelections(body: validBody, mind: validMind, heart: validHeart)
    }

    /// Check if an option ID still exists (built-in or custom, not hidden).
    private func optionExists(_ id: String, category: EnergyCategory) -> Bool {
        let all = orderedOptions(for: category)
        return all.contains { $0.id == id }
    }

    /// Bulk-set all three category selections, recalculate, and persist.
    func applySelections(body: [String], mind: [String], heart: [String]) {
        dailyActivitySelections = Array(body.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyRestSelections = Array(mind.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyJoysSelections = Array(heart.prefix(EnergyDefaults.maxSelectionsPerCategory))
        syncFromSelectionsToSlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    // MARK: - Routines (Saved Presets)

    private var savedRoutinesKey: String { "savedEnergyRoutines_v1" }

    func loadSavedRoutines() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: savedRoutinesKey),
              let decoded = try? JSONDecoder().decode([EnergyRoutine].self, from: data) else {
            savedRoutines = []
            return
        }
        savedRoutines = decoded
    }

    private func persistSavedRoutines() {
        let g = UserDefaults.stepsTrader()
        guard let data = try? JSONEncoder().encode(savedRoutines) else { return }
        g.set(data, forKey: savedRoutinesKey)
    }

    /// Save current selections as a named routine.
    func saveCurrentAsRoutine(name: String) {
        let routine = EnergyRoutine(
            name: name,
            bodyIds: dailyActivitySelections,
            mindIds: dailyRestSelections,
            heartIds: dailyJoysSelections,
            lastUsed: Date()
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
            savedRoutines[idx].lastUsed = Date()
            persistSavedRoutines()
        }
    }

    /// Delete a saved routine.
    func deleteRoutine(_ routine: EnergyRoutine) {
        savedRoutines.removeAll { $0.id == routine.id }
        persistSavedRoutines()
    }

}
