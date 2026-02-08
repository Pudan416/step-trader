import Foundation

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
    private var dailyGallerySlotsKey: String { "dailyChoiceSlots_v1" }
    private var customEnergyOptionsKey: String { "customEnergyOptions_v1" }
    
    private func preferredOptionsKey(for category: EnergyCategory) -> String {
        "preferredEnergyOptions_v1_\(category.rawValue)"
    }
    // MARK: - Daily energy system
    func loadEnergyPreferences() {
        preferredActivityOptions = loadPreferredOptions(for: .activity)
        preferredRestOptions = loadPreferredOptions(for: .creativity)
        preferredJoysOptions = loadPreferredOptions(for: .joys)
    }

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            resetDailyEnergyState()
            return
        }
        dailySleepHours = g.double(forKey: dailySleepHoursKey)
        // Migration: try new keys first, then old move/reboot/joy
        let newActivity = loadStringArray(forKey: dailySelectionsKey(for: .activity))
        let oldMove = loadStringArray(forKey: "dailyEnergySelections_v1_move")
        dailyActivitySelections = newActivity.isEmpty ? migrateOptionIds(oldMove, from: "move_", to: "activity_") : newActivity

        let newCreativity = loadStringArray(forKey: dailySelectionsKey(for: .creativity))
        let oldRestKey = loadStringArray(forKey: "dailyEnergySelections_v1_rest")
        let oldReboot = loadStringArray(forKey: "dailyEnergySelections_v1_reboot")
        let legacyRest = loadStringArray(forKey: "dailyEnergySelections_v1_recovery")
        let resolvedCreativity = !newCreativity.isEmpty ? newCreativity : (!oldRestKey.isEmpty ? oldRestKey : legacyRest)
        let fallbackFromReboot = migrateOptionIds(oldReboot, from: "reboot_", to: "recovery_")
        dailyRestSelections = !resolvedCreativity.isEmpty ? resolvedCreativity : fallbackFromReboot
        // Best-effort rename of legacy "recovery_" IDs into "creativity_" (assets/options have changed).
        dailyRestSelections = migrateOptionIds(dailyRestSelections, from: "recovery_", to: "creativity_")

        let newJoys = loadStringArray(forKey: dailySelectionsKey(for: .joys))
        let oldJoy = loadStringArray(forKey: "dailyEnergySelections_v1_joy")
        dailyJoysSelections = newJoys.isEmpty ? migrateOptionIds(oldJoy, from: "joy_", to: "joys_") : newJoys

        let newPreferredActivity = loadStringArray(forKey: preferredOptionsKey(for: .activity))
        let oldPreferredMove = loadStringArray(forKey: "preferredEnergyOptions_v1_move")
        preferredActivityOptions = newPreferredActivity.isEmpty ? migrateOptionIds(oldPreferredMove, from: "move_", to: "activity_") : newPreferredActivity

        let newPreferredCreativity = loadStringArray(forKey: preferredOptionsKey(for: .creativity))
        let oldPreferredRestKey = loadStringArray(forKey: "preferredEnergyOptions_v1_rest")
        let oldPreferredReboot = loadStringArray(forKey: "preferredEnergyOptions_v1_reboot")
        let legacyPreferredRest = loadStringArray(forKey: "preferredEnergyOptions_v1_recovery")
        let resolvedPreferredCreativity = !newPreferredCreativity.isEmpty ? newPreferredCreativity : (!oldPreferredRestKey.isEmpty ? oldPreferredRestKey : legacyPreferredRest)
        let fallbackPreferredFromReboot = migrateOptionIds(oldPreferredReboot, from: "reboot_", to: "recovery_")
        preferredRestOptions = !resolvedPreferredCreativity.isEmpty ? resolvedPreferredCreativity : fallbackPreferredFromReboot
        preferredRestOptions = migrateOptionIds(preferredRestOptions, from: "recovery_", to: "creativity_")

        let newPreferredJoys = loadStringArray(forKey: preferredOptionsKey(for: .joys))
        let oldPreferredJoy = loadStringArray(forKey: "preferredEnergyOptions_v1_joy")
        preferredJoysOptions = newPreferredJoys.isEmpty ? migrateOptionIds(oldPreferredJoy, from: "joy_", to: "joys_") : newPreferredJoys

        if newPreferredActivity.isEmpty && !oldPreferredMove.isEmpty {
            saveStringArray(preferredActivityOptions, forKey: preferredOptionsKey(for: .activity))
        }
        if newPreferredCreativity.isEmpty && (!oldPreferredReboot.isEmpty || !oldPreferredRestKey.isEmpty) {
            saveStringArray(preferredRestOptions, forKey: preferredOptionsKey(for: .creativity))
        }
        if newPreferredJoys.isEmpty && !oldPreferredJoy.isEmpty {
            saveStringArray(preferredJoysOptions, forKey: preferredOptionsKey(for: .joys))
        }

        dailyActivitySelections = Array(dailyActivitySelections.filter { preferredActivityOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyRestSelections = Array(dailyRestSelections.filter { preferredRestOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))
        dailyJoysSelections = Array(dailyJoysSelections.filter { preferredJoysOptions.contains($0) }.prefix(EnergyDefaults.maxSelectionsPerCategory))

        if newActivity.isEmpty && !oldMove.isEmpty {
            saveStringArray(dailyActivitySelections, forKey: dailySelectionsKey(for: .activity))
        }
        if newCreativity.isEmpty && (!oldReboot.isEmpty || !oldRestKey.isEmpty || !legacyRest.isEmpty) {
            saveStringArray(dailyRestSelections, forKey: dailySelectionsKey(for: .creativity))
        }
        if newJoys.isEmpty && !oldJoy.isEmpty {
            saveStringArray(dailyJoysSelections, forKey: dailySelectionsKey(for: .joys))
        }

        baseEnergyToday = g.integer(forKey: baseEnergyTodayKey)
        
        loadDailyGallerySlots()
        loadCustomEnergyOptions()
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
    
    func customOption(for optionId: String) -> CustomEnergyOption? {
        customEnergyOptions.first(where: { $0.id == optionId })
    }
    
    func customOptionTitle(for optionId: String, lang: String) -> String? {
        customEnergyOptions.first(where: { $0.id == optionId })?.title(for: lang)
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
    
    func replaceOptionWithCustom(optionId: String, category: EnergyCategory, titleEn: String, titleRu: String, icon: String) {
        if optionId.hasPrefix("custom_") {
            updateCustomOption(optionId: optionId, titleEn: titleEn, titleRu: titleRu, icon: icon)
            return
        }
        
        let newId = addCustomOption(category: category, titleEn: titleEn, titleRu: titleRu, icon: icon)
        guard !newId.isEmpty else { return }
        
        var order = loadStringArray(forKey: optionsOrderKey(for: category))
        if let idx = order.firstIndex(of: optionId) {
            order[idx] = newId
        }
        order.removeAll { $0 == optionId }
        saveStringArray(order, forKey: optionsOrderKey(for: category))
        
        var preferred = preferredOptionsIds(for: category)
        if let idx = preferred.firstIndex(of: optionId) {
            preferred[idx] = newId
        }
        updatePreferredOptions(preferred, category: category)
        
        var daily = dailySelections(for: category)
        if let idx = daily.firstIndex(of: optionId) {
            daily[idx] = newId
        }
        setDailySelections(daily, category: category)
        persistDailyEnergyState()
        recalculateDailyEnergy()
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
        persistDailyGallerySlots()
        persistDailyEnergyState()
        recalculateDailyEnergy()
        objectWillChange.send()
    }
    
    func deleteOption(optionId: String) {
        guard !EnergyDefaults.otherOptionIds.contains(optionId) else { return }
        
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
        persistDailyGallerySlots()
        persistDailyEnergyState()
        recalculateDailyEnergy()
        objectWillChange.send()
    }
    
    private func loadDailyGallerySlots() {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: dailyGallerySlotsKey),
              let decoded = try? JSONDecoder().decode([DayGallerySlot].self, from: data),
              decoded.count == 4 else {
            syncFromSelectionsToSlots()
            persistDailyGallerySlots()
            return
        }
        dailyGallerySlots = decoded
        syncFromSlotsToSelections()
        persistDailyEnergyState()
    }
    
    private func syncFromSelectionsToSlots() {
        var slots: [DayGallerySlot] = []
        for cat in [EnergyCategory.activity, .creativity, .joys] {
            let ids = dailySelections(for: cat)
            for id in ids.prefix(4) {
                slots.append(DayGallerySlot(category: cat, optionId: id))
            }
        }
        while slots.count < 4 {
            slots.append(DayGallerySlot(category: nil, optionId: nil))
        }
        dailyGallerySlots = Array(slots.prefix(4))
    }
    
    private func syncFromSlotsToSelections() {
        dailyActivitySelections = dailyGallerySlots.compactMap { $0.category == .activity ? $0.optionId : nil }
        dailyRestSelections = dailyGallerySlots.compactMap { $0.category == .creativity ? $0.optionId : nil }
        dailyJoysSelections = dailyGallerySlots.compactMap { $0.category == .joys ? $0.optionId : nil }
    }
    
    func setDailyGallerySlot(at index: Int, category: EnergyCategory?, optionId: String?) {
        guard (0..<4).contains(index) else { return }
        dailyGallerySlots[index] = DayGallerySlot(category: category, optionId: optionId)
        syncFromSlotsToSelections()
        persistDailyGallerySlots()
        persistDailyEnergyState()
        recalculateDailyEnergy()
        
        // Track activity selection in global stats
        if let cat = category, let id = optionId {
            trackActivityForGlobalStats(activityId: id, category: cat)
        }
    }
    
    /// Track activity selection in global stats table
    private func trackActivityForGlobalStats(activityId: String, category: EnergyCategory) {
        // Find the option details
        let isCustom = activityId.hasPrefix("custom_")
        let titleEn: String
        let titleRu: String
        let icon: String
        
        if isCustom {
            if let custom = customEnergyOptions.first(where: { $0.id == activityId }) {
                titleEn = custom.titleEn
                titleRu = custom.titleRu
                icon = custom.icon
            } else {
                return // Custom option not found
            }
        } else {
            if let option = EnergyDefaults.options.first(where: { $0.id == activityId }) {
                titleEn = option.titleEn
                titleRu = option.titleRu
                icon = option.icon
            } else {
                return // Option not found
            }
        }
        
        Task {
            await SupabaseSyncService.shared.trackActivitySelection(
                activityId: activityId,
                category: category,
                titleEn: titleEn,
                titleRu: titleRu,
                icon: icon,
                isCustom: isCustom
            )
        }
    }
    
    private func persistDailyGallerySlots() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dailyGallerySlots) {
            g.set(data, forKey: dailyGallerySlotsKey)
        }
    }
    
    func loadPastDaySnapshots() -> [String: PastDaySnapshot] {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: pastDaySnapshotsKey),
              let decoded = try? JSONDecoder().decode([String: PastDaySnapshot].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private func savePastDaySnapshot(dayKey: String, _ snapshot: PastDaySnapshot) {
        var all = loadPastDaySnapshots()
        all[dayKey] = snapshot
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(all) {
            g.set(data, forKey: pastDaySnapshotsKey)
        }
    }

    private func migrateOptionIds(_ ids: [String], from prefix: String, to newPrefix: String) -> [String] {
        ids.map { id in
            id.hasPrefix(prefix) ? newPrefix + id.dropFirst(prefix.count) : id
        }
    }

    private func resetDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        let dayKeyToSave = Self.dayKey(for: anchor)

        // Build snapshot from PERSISTED state (UserDefaults), not in-memory — on new-day launch in-memory is still default 0/empty
        let savedBaseEnergy = g.integer(forKey: baseEnergyTodayKey)
        let savedSpent = g.integer(forKey: "spentStepsToday")
        let savedActivity = loadStringArray(forKey: dailySelectionsKey(for: .activity))
        let newCreativity = loadStringArray(forKey: dailySelectionsKey(for: .creativity))
        let oldRestKey = loadStringArray(forKey: "dailyEnergySelections_v1_rest")
        let legacyRest = loadStringArray(forKey: "dailyEnergySelections_v1_recovery")
        var savedCreativity = !newCreativity.isEmpty ? newCreativity : (!oldRestKey.isEmpty ? oldRestKey : legacyRest)
        if savedCreativity.isEmpty {
            savedCreativity = migrateOptionIds(
                loadStringArray(forKey: "dailyEnergySelections_v1_reboot"),
                from: "reboot_",
                to: "recovery_"
            )
        }
        savedCreativity = migrateOptionIds(savedCreativity, from: "recovery_", to: "creativity_")
        let savedJoys = loadStringArray(forKey: dailySelectionsKey(for: .joys))
        let savedSleep = g.double(forKey: dailySleepHoursKey)
        let cachedSteps = g.double(forKey: "cachedStepsToday")
        let savedSteps: Int = cachedSteps > 0 ? Int(cachedSteps) : Int(stepsToday)
        savePastDaySnapshot(dayKey: dayKeyToSave, PastDaySnapshot(
            controlGained: savedBaseEnergy,
            controlSpent: savedSpent,
            activityIds: savedActivity,
            creativityIds: savedCreativity,
            joysIds: savedJoys,
            steps: savedSteps,
            sleepHours: savedSleep
        ))

        dailySleepHours = 0
        dailyActivitySelections = []
        dailyRestSelections = []
        dailyJoysSelections = []
        dailyGallerySlots = (0..<4).map { _ in DayGallerySlot(category: nil, optionId: nil) }
        baseEnergyToday = 0
        persistDailyEnergyState()
        persistDailyGallerySlots()
        g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
    }

    @discardableResult
    func resetDailyEnergyIfNeeded() -> Bool {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
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
        case .activity: return preferredActivityOptions
        case .creativity: return preferredRestOptions
        case .joys: return preferredJoysOptions
        }
    }
    
    private func allOptions(for category: EnergyCategory) -> [EnergyOption] {
        let defaults = EnergyDefaults.options.filter { $0.category == category }
        let custom = customOptions(for: category)
        let hidden = hiddenOptions(for: category)
        return (defaults + custom).filter { !hidden.contains($0.id) }
    }
    
    private func hiddenOptions(for category: EnergyCategory) -> Set<String> {
        let hidden = Set(loadStringArray(forKey: hiddenOptionsKey(for: category)))
        return hidden.subtracting(EnergyDefaults.otherOptionIds)
    }
    
    private func moveOtherToEnd(_ options: [EnergyOption]) -> [EnergyOption] {
        var normal: [EnergyOption] = []
        var others: [EnergyOption] = []
        for option in options {
            if EnergyDefaults.otherOptionIds.contains(option.id) {
                others.append(option)
            } else {
                normal.append(option)
            }
        }
        return normal + others
    }
    
    private func moveOtherIdsToEnd(_ ids: [String]) -> [String] {
        let other = ids.filter { EnergyDefaults.otherOptionIds.contains($0) }
        let normal = ids.filter { !EnergyDefaults.otherOptionIds.contains($0) }
        return normal + other
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
        return moveOtherToEnd(ordered)
    }
    
    func updateOptionsOrder(_ ids: [String], category: EnergyCategory) {
        let allIds = Set(allOptions(for: category).map(\.id))
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let filtered = unique.filter { allIds.contains($0) }
        let missing = allIds.subtracting(filtered)
        let updated = filtered + Array(missing)
        let finalOrder = moveOtherIdsToEnd(updated)
        saveStringArray(finalOrder, forKey: optionsOrderKey(for: category))
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
        case .activity: ids = preferredActivityOptions
        case .creativity: ids = preferredRestOptions
        case .joys: ids = preferredJoysOptions
        }
        let all = allOptions(for: category)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return ids.compactMap { byId[$0] }
    }

    func availableOptions(for category: EnergyCategory) -> [EnergyOption] {
        orderedOptions(for: category)
    }

    func updatePreferredOptions(_ ids: [String], category: EnergyCategory) {
        let unique = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let trimmed = Array(unique.prefix(EnergyDefaults.maxSelectionsPerCategory))
        switch category {
        case .activity: preferredActivityOptions = trimmed
        case .creativity: preferredRestOptions = trimmed
        case .joys: preferredJoysOptions = trimmed
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
        case .activity: selections = preferredActivityOptions
        case .creativity: selections = preferredRestOptions
        case .joys: selections = preferredJoysOptions
        }
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        updatePreferredOptions(selections, category: category)
    }

    func isPreferredOptionSelected(_ optionId: String, category: EnergyCategory) -> Bool {
        switch category {
        case .activity: return preferredActivityOptions.contains(optionId)
        case .creativity: return preferredRestOptions.contains(optionId)
        case .joys: return preferredJoysOptions.contains(optionId)
        }
    }

    func toggleDailySelection(optionId: String, category: EnergyCategory) {
        var selections = dailySelections(for: category)
        if let idx = selections.firstIndex(of: optionId) {
            selections.remove(at: idx)
        } else if selections.count < EnergyDefaults.maxSelectionsPerCategory {
            selections.append(optionId)
        }
        setDailySelections(selections, category: category)
        syncFromSelectionsToSlots()
        persistDailyGallerySlots()
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    func isDailySelected(_ optionId: String, category: EnergyCategory) -> Bool {
        dailySelections(for: category).contains(optionId)
    }

    func dailySelectionsCount(for category: EnergyCategory) -> Int {
        dailySelections(for: category).count
    }

    func setDailySleepHours(_ hours: Double) {
        dailySleepHours = min(max(0, hours), 24)
        persistDailyEnergyState()
        recalculateDailyEnergy()
    }

    private func dailySelections(for category: EnergyCategory) -> [String] {
        switch category {
        case .activity: return dailyActivitySelections
        case .creativity: return dailyRestSelections
        case .joys: return dailyJoysSelections
        }
    }

    private func setDailySelections(_ selections: [String], category: EnergyCategory) {
        switch category {
        case .activity: dailyActivitySelections = selections
        case .creativity: dailyRestSelections = selections
        case .joys: dailyJoysSelections = selections
        }
    }

    func persistDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        g.set(dailySleepHours, forKey: dailySleepHoursKey)
        saveStringArray(dailyActivitySelections, forKey: dailySelectionsKey(for: .activity))
        saveStringArray(dailyRestSelections, forKey: dailySelectionsKey(for: .creativity))
        saveStringArray(dailyJoysSelections, forKey: dailySelectionsKey(for: .joys))
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)
        persistDailyGallerySlots()
        if g.object(forKey: dailyEnergyAnchorKey) == nil {
            g.set(currentDayStart(for: Date()), forKey: dailyEnergyAnchorKey)
        }
        
        // Sync daily selections to Supabase (skip during bootstrap to avoid overwriting server data)
        guard !isBootstrapping else {
            print("🔄 persistDailyEnergyState: skipping sync during bootstrap")
            return
        }
        
        let today = Self.dayKey(for: Date())
        print("🔄 persistDailyEnergyState calling syncDailySelections for \(today)")
        print("🔄   activities: \(dailyActivitySelections)")
        print("🔄   creativity: \(dailyRestSelections)")
        print("🔄   joys: \(dailyJoysSelections)")
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

    var activityExtrasPoints: Int {
        pointsFromSelections(dailyActivitySelections.count)
    }

    var creativityExtrasPoints: Int {
        pointsFromSelections(dailyRestSelections.count)
    }

    var joysChoicePointsToday: Int {
        pointsFromSelections(dailyJoysSelections.count)
    }

    var activityPointsToday: Int {
        stepsPointsToday + activityExtrasPoints
    }

    /// Creativity category is only choices (max 20).
    var creativityPointsToday: Int {
        creativityExtrasPoints
    }

    /// Joys category includes sleep (max 20) + joys choices (max 20) = 40.
    var joysCategoryPointsToday: Int {
        sleepPointsToday + joysChoicePointsToday
    }

    private var userSleepTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userSleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
    }
    
    private var userStepsTarget: Double {
        let g = UserDefaults.stepsTrader()
        return g.object(forKey: "userStepsTarget") as? Double ?? EnergyDefaults.stepsTarget
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
        // Use cached steps when HealthKit hasn't returned yet (e.g. after app restart) so we don't reset base to 20/20/100
        let stepsForEnergy = stepsToday > 0 ? stepsToday : fallbackCachedSteps()
        let activityPts = pointsFromSteps(stepsForEnergy) + activityExtrasPoints
        let total = activityPts + creativityPointsToday + joysCategoryPointsToday

        // Total must equal activity + creativity + joys (same as breakdown chips)
        print("⚡️ recalculateDailyEnergy: activity=\(activityPts) + creativity=\(creativityPointsToday) + joys=\(joysCategoryPointsToday) = \(total) (stepsUsed=\(stepsForEnergy))")
        assert(activityPts + creativityPointsToday + joysCategoryPointsToday == total, "EXP total must equal sum of categories")
        
        // Базовая энергия ограничена максимумом 100
        baseEnergyToday = min(EnergyDefaults.maxBaseEnergy, total)
        
        // Проверяем суммарный лимит: baseEnergyToday + bonusSteps не должно превышать 100
        // Если baseEnergyToday увеличился и сумма превышает лимит, уменьшаем bonusSteps
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy // 100
        let currentTotal = baseEnergyToday + bonusSteps
        if currentTotal > maxTotalEnergy {
            // Уменьшаем bonusSteps, чтобы сумма была <= 100
            let oldBonus = bonusSteps
            bonusSteps = max(0, maxTotalEnergy - baseEnergyToday)
            print("⚡️ Capped bonusSteps: \(oldBonus) → \(bonusSteps)")
            syncAndPersistBonusBreakdown() // Обновим сохранение
        }
        
        if spentStepsToday > baseEnergyToday {
            print("⚡️ Capping spentStepsToday from \(spentStepsToday) to \(baseEnergyToday)")
            spentStepsToday = baseEnergyToday
            let g = UserDefaults.stepsTrader()
            g.set(spentStepsToday, forKey: "spentStepsToday")
        }
        
        let oldBalance = stepsBalance
        stepsBalance = max(0, baseEnergyToday - spentStepsToday)
        print("⚡️ stepsBalance: \(oldBalance) → \(stepsBalance) (base=\(baseEnergyToday), spent=\(spentStepsToday))")
        
        let g = UserDefaults.stepsTrader()
        g.set(baseEnergyToday, forKey: baseEnergyTodayKey)
        g.set(stepsBalance, forKey: "stepsBalance")
        
        // Explicitly update totalStepsBalance after all changes
        updateTotalStepsBalance()
        print("⚡️ totalStepsBalance = \(totalStepsBalance)")
        
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
                bonusEnergy: bonusSteps,
                remainingBalance: totalStepsBalance
            )
        }
    }
}
