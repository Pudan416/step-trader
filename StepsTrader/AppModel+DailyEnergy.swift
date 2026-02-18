import Foundation
import SwiftUI

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
    
    private var legacyMoneyInJoysId: String { "joys_money" }
    private var moneyInMindId: String { "creativity_doing_cash" }
    
    @discardableResult
    private func migrateMoneyPieceToMind(creativityIds: inout [String], joysIds: inout [String]) -> Bool {
        let hadLegacyInJoys = joysIds.contains(legacyMoneyInJoysId)
        let hadLegacyInMind = creativityIds.contains(legacyMoneyInJoysId)
        guard hadLegacyInJoys || hadLegacyInMind else { return false }
        
        joysIds.removeAll { $0 == legacyMoneyInJoysId }
        creativityIds.removeAll { $0 == legacyMoneyInJoysId }
        
        if !creativityIds.contains(moneyInMindId) {
            creativityIds.insert(moneyInMindId, at: 0)
        }
        
        return true
    }

    // MARK: - Daily energy system
    func loadEnergyPreferences() {
        preferredActivityOptions = loadPreferredOptions(for: .body)
        preferredRestOptions = loadPreferredOptions(for: .mind)
        preferredJoysOptions = loadPreferredOptions(for: .heart)
    }

    private static let energyMigrationVersionKey = "energyMigrationVersion_v1"
    private static let currentEnergyMigrationVersion = 2

    func loadDailyEnergyState() {
        let g = UserDefaults.stepsTrader()
        let anchor = g.object(forKey: dailyEnergyAnchorKey) as? Date ?? .distantPast
        if !isSameCustomDay(anchor, Date()) {
            resetDailyEnergyState()
            return
        }
        dailySleepHours = g.double(forKey: dailySleepHoursKey)

        let needsMigration = g.integer(forKey: Self.energyMigrationVersionKey) < Self.currentEnergyMigrationVersion

        if needsMigration {
            // Migration: try new keys first, then old move/reboot/joy
            let newActivity = loadStringArray(forKey: dailySelectionsKey(for: .body))
            let oldMove = loadStringArray(forKey: "dailyEnergySelections_v1_move")
            dailyActivitySelections = newActivity.isEmpty ? migrateOptionIds(oldMove, from: "move_", to: "activity_") : newActivity

            let newCreativity = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            let oldRestKey = loadStringArray(forKey: "dailyEnergySelections_v1_rest")
            let oldReboot = loadStringArray(forKey: "dailyEnergySelections_v1_reboot")
            let legacyRest = loadStringArray(forKey: "dailyEnergySelections_v1_recovery")
            let resolvedCreativity = !newCreativity.isEmpty ? newCreativity : (!oldRestKey.isEmpty ? oldRestKey : legacyRest)
            let fallbackFromReboot = migrateOptionIds(oldReboot, from: "reboot_", to: "recovery_")
            dailyRestSelections = !resolvedCreativity.isEmpty ? resolvedCreativity : fallbackFromReboot
            dailyRestSelections = migrateOptionIds(dailyRestSelections, from: "recovery_", to: "creativity_")

            let newJoys = loadStringArray(forKey: dailySelectionsKey(for: .heart))
            let oldJoy = loadStringArray(forKey: "dailyEnergySelections_v1_joy")
            dailyJoysSelections = newJoys.isEmpty ? migrateOptionIds(oldJoy, from: "joy_", to: "joys_") : newJoys
            dailyJoysSelections = migrateOptionIds(dailyJoysSelections, from: "joysl_", to: "joys_")

            let newPreferredActivity = loadStringArray(forKey: preferredOptionsKey(for: .body))
            let oldPreferredMove = loadStringArray(forKey: "preferredEnergyOptions_v1_move")
            preferredActivityOptions = newPreferredActivity.isEmpty ? migrateOptionIds(oldPreferredMove, from: "move_", to: "activity_") : newPreferredActivity

            let newPreferredCreativity = loadStringArray(forKey: preferredOptionsKey(for: .mind))
            let oldPreferredRestKey = loadStringArray(forKey: "preferredEnergyOptions_v1_rest")
            let oldPreferredReboot = loadStringArray(forKey: "preferredEnergyOptions_v1_reboot")
            let legacyPreferredRest = loadStringArray(forKey: "preferredEnergyOptions_v1_recovery")
            let resolvedPreferredCreativity = !newPreferredCreativity.isEmpty ? newPreferredCreativity : (!oldPreferredRestKey.isEmpty ? oldPreferredRestKey : legacyPreferredRest)
            let fallbackPreferredFromReboot = migrateOptionIds(oldPreferredReboot, from: "reboot_", to: "recovery_")
            preferredRestOptions = !resolvedPreferredCreativity.isEmpty ? resolvedPreferredCreativity : fallbackPreferredFromReboot
            preferredRestOptions = migrateOptionIds(preferredRestOptions, from: "recovery_", to: "creativity_")

            let newPreferredJoys = loadStringArray(forKey: preferredOptionsKey(for: .heart))
            let oldPreferredJoy = loadStringArray(forKey: "preferredEnergyOptions_v1_joy")
            preferredJoysOptions = newPreferredJoys.isEmpty ? migrateOptionIds(oldPreferredJoy, from: "joy_", to: "joys_") : newPreferredJoys
            preferredJoysOptions = migrateOptionIds(preferredJoysOptions, from: "joysl_", to: "joys_")

            _ = migrateMoneyPieceToMind(
                creativityIds: &dailyRestSelections,
                joysIds: &dailyJoysSelections
            )
            _ = migrateMoneyPieceToMind(
                creativityIds: &preferredRestOptions,
                joysIds: &preferredJoysOptions
            )

            // Persist migrated data under new keys
            saveStringArray(dailyActivitySelections, forKey: dailySelectionsKey(for: .body))
            saveStringArray(dailyRestSelections, forKey: dailySelectionsKey(for: .mind))
            saveStringArray(dailyJoysSelections, forKey: dailySelectionsKey(for: .heart))
            saveStringArray(preferredActivityOptions, forKey: preferredOptionsKey(for: .body))
            saveStringArray(preferredRestOptions, forKey: preferredOptionsKey(for: .mind))
            saveStringArray(preferredJoysOptions, forKey: preferredOptionsKey(for: .heart))

            g.set(Self.currentEnergyMigrationVersion, forKey: Self.energyMigrationVersionKey)
            AppLogger.energy.debug("Energy migration completed (v\(Self.currentEnergyMigrationVersion))")
        } else {
            // Fast path: no migration needed, read directly from canonical keys
            dailyActivitySelections = loadStringArray(forKey: dailySelectionsKey(for: .body))
            dailyRestSelections = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            dailyJoysSelections = loadStringArray(forKey: dailySelectionsKey(for: .heart))
            preferredActivityOptions = loadStringArray(forKey: preferredOptionsKey(for: .body))
            preferredRestOptions = loadStringArray(forKey: preferredOptionsKey(for: .mind))
            preferredJoysOptions = loadStringArray(forKey: preferredOptionsKey(for: .heart))
        }

        baseEnergyToday = g.integer(forKey: baseEnergyTodayKey)
        
        loadDailyGallerySlots()
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
        recalculateDailyEnergy()
        persistDailyEnergyState()
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
        persistDailyGallerySlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
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
        for cat in [EnergyCategory.body, .mind, .heart] {
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
        dailyActivitySelections = dailyGallerySlots.compactMap { $0.category == .body ? $0.optionId : nil }
        dailyRestSelections = dailyGallerySlots.compactMap { $0.category == .mind ? $0.optionId : nil }
        dailyJoysSelections = dailyGallerySlots.compactMap { $0.category == .heart ? $0.optionId : nil }
    }
    
    func setDailyGallerySlot(at index: Int, category: EnergyCategory?, optionId: String?) {
        guard (0..<4).contains(index) else { return }
        let previous = dailyGallerySlots[index]
        dailyGallerySlots[index] = DayGallerySlot(category: category, optionId: optionId)
        syncFromSlotsToSelections()
        persistDailyGallerySlots()
        recalculateDailyEnergy()
        persistDailyEnergyState()
        
        // Track activity selection in global stats
        if let cat = category, let id = optionId {
            trackActivityForGlobalStats(activityId: id, category: cat)
            if previous.optionId != id {
                Task {
                    await SupabaseSyncService.shared.trackAnalyticsEvent(
                        name: "piece_selected",
                        properties: [
                            "option_id": id,
                            "category": cat.rawValue,
                            "source": "gallery_slot"
                        ]
                    )
                }
            }
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

        var migrated = decoded
        var didMigrate = false
        for (key, snapshot) in decoded {
            var creativity = snapshot.mindIds
            var joys = snapshot.heartIds
            if migrateMoneyPieceToMind(creativityIds: &creativity, joysIds: &joys) {
                var updated = snapshot
                updated.mindIds = creativity
                updated.heartIds = joys
                migrated[key] = updated
                didMigrate = true
            }
        }

        let pruned = Self.prunePastDaySnapshotsToRetention(migrated)
        if didMigrate || pruned.count != migrated.count {
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
        let savedSpent = g.integer(forKey: SharedKeys.spentStepsToday)
        let savedActivity = loadStringArray(forKey: dailySelectionsKey(for: .body))
        let needsLegacyMigration = g.integer(forKey: Self.energyMigrationVersionKey) < Self.currentEnergyMigrationVersion
        var savedCreativity: [String]
        var migratedSavedJoys: [String]
        if needsLegacyMigration {
            let newCreativity = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            let oldRestKey = loadStringArray(forKey: "dailyEnergySelections_v1_rest")
            let legacyRest = loadStringArray(forKey: "dailyEnergySelections_v1_recovery")
            savedCreativity = !newCreativity.isEmpty ? newCreativity : (!oldRestKey.isEmpty ? oldRestKey : legacyRest)
            if savedCreativity.isEmpty {
                savedCreativity = migrateOptionIds(
                    loadStringArray(forKey: "dailyEnergySelections_v1_reboot"),
                    from: "reboot_",
                    to: "recovery_"
                )
            }
            savedCreativity = migrateOptionIds(savedCreativity, from: "recovery_", to: "creativity_")
            let savedJoys = loadStringArray(forKey: dailySelectionsKey(for: .heart))
            migratedSavedJoys = migrateOptionIds(savedJoys, from: "joysl_", to: "joys_")
            _ = migrateMoneyPieceToMind(creativityIds: &savedCreativity, joysIds: &migratedSavedJoys)
        } else {
            savedCreativity = loadStringArray(forKey: dailySelectionsKey(for: .mind))
            migratedSavedJoys = loadStringArray(forKey: dailySelectionsKey(for: .heart))
        }
        let savedSleep = g.double(forKey: dailySleepHoursKey)
        let cachedSteps = g.double(forKey: "cachedStepsToday")
        let savedSteps: Int = cachedSteps > 0 ? Int(cachedSteps) : Int(stepsToday)
        let savedStepsTarget = userStepsTarget
        let savedSleepTarget = userSleepTarget
        let daySnapshot = PastDaySnapshot(
            inkEarned: savedBaseEnergy,
            inkSpent: savedSpent,
            bodyIds: savedActivity,
            mindIds: savedCreativity,
            heartIds: migratedSavedJoys,
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

        // Save a rendered canvas snapshot for the history gallery
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
    
    private func hiddenOptions(for category: EnergyCategory) -> Set<String> {
        let hidden = Set(loadStringArray(forKey: hiddenOptionsKey(for: category)))
        return hidden
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

    func availableOptions(for category: EnergyCategory) -> [EnergyOption] {
        orderedOptions(for: category)
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
        persistDailyGallerySlots()
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
                        "source": "daily_gallery"
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

    func setDailySleepHours(_ hours: Double) {
        dailySleepHours = min(max(0, hours), 24)
        recalculateDailyEnergy()
        persistDailyEnergyState()
    }

    private func dailySelections(for category: EnergyCategory) -> [String] {
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
        persistDailyGallerySlots()
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

    var activityExtrasPoints: Int {
        pointsFromSelections(dailyActivitySelections.count)
    }

    var creativityExtrasPoints: Int {
        pointsFromSelections(dailyRestSelections.count)
    }

    var joysChoicePointsToday: Int {
        pointsFromSelections(dailyJoysSelections.count)
    }

    /// Body: 4 chosen cards × 5 ink = 20 max.
    var activityPointsToday: Int {
        activityExtrasPoints
    }

    /// Mind: 4 chosen cards × 5 ink = 20 max.
    var creativityPointsToday: Int {
        creativityExtrasPoints
    }

    /// Heart: 4 chosen cards × 5 ink = 20 max.
    var joysCategoryPointsToday: Int {
        joysChoicePointsToday
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
        
        // Rest day override grants a minimum base of 30 ink.
        let adjustedTotal = isRestDayOverrideEnabled ? max(total, 30) : total
        
        // Base energy capped at maximum 100
        baseEnergyToday = min(EnergyDefaults.maxBaseEnergy, adjustedTotal)
        
        // Check total limit: baseEnergyToday + bonusSteps must not exceed 100
        // If baseEnergyToday increased and total exceeds limit, reduce bonusSteps
        let maxTotalEnergy = EnergyDefaults.maxBaseEnergy // 100
        let currentTotal = baseEnergyToday + bonusSteps
        if currentTotal > maxTotalEnergy {
            // Reduce bonusSteps so total stays <= 100
            let oldBonus = bonusSteps
            bonusSteps = max(0, maxTotalEnergy - baseEnergyToday)
            AppLogger.energy.debug("⚡️ Capped bonusSteps: \(oldBonus) → \(self.bonusSteps)")
            syncAndPersistBonusBreakdown() // Persist the update
        }
        
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
        g.set(stepsBalance, forKey: "stepsBalance")
        
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
                bonusEnergy: bonusSteps,
                remainingBalance: totalStepsBalance
            )
        }
        
        // Sync user preferences (targets, day boundary, preferred options, gallery slots)
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
                gallerySlots: dailyGallerySlots
            )
        }
    }
}
