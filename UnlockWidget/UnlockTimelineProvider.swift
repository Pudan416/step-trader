import WidgetKit
import SwiftUI

// MARK: - Shared Widget Kind

enum WidgetKind {
    static let main = "NowHereWidget_v2"
    static let status = "NowHereStatus_v1"
}

// MARK: - Timeline Entry

struct UnlockEntry: TimelineEntry {
    let date: Date
    let groups: [GroupSnapshot]
    let colorsBalance: Int
    let selectedGroupIds: [String]
    let mediumMode: MediumWidgetMode
    let wallpaperBackground: UIImage?
    let energyData: EnergyData

    struct GroupSnapshot: Identifiable {
        let id: String
        let name: String
        let enabledIntervals: Set<AccessWindow>
        let isUnlocked: Bool
        let templateApp: String?
        let appsCount: Int
        let spentToday: Int
        let budgetMinutes: Int
        let budgetInitial: Int
        let budgetExpiryDate: Date?
    }

    struct EnergyData {
        let remaining: Int
        let earned: Int
        let bonus: Int
        let maxEnergy: Int
        let stepsPoints: Int
        let sleepPoints: Int
        let bodyPoints: Int
        let mindPoints: Int
        let heartPoints: Int
        let resetDate: Date?
    }
}

// MARK: - Widget Preferences (stored in App Group UserDefaults from app)

enum WidgetPrefsKeys {
    static let mediumMode = "widget_mediumMode_v1"
}

// MARK: - Adaptive Refresh Policy

enum WidgetRefreshPolicy {
    static let idleInterval: TimeInterval = 30 * 60
    static let activeInterval: TimeInterval = 10 * 60
    static let nightInterval: TimeInterval = 60 * 60

    static func nextRefreshDate(from now: Date, hasActiveUnlock: Bool) -> Date {
        let hour = Calendar.current.component(.hour, from: now)
        let isNight = hour >= 23 || hour < 7

        let interval: TimeInterval
        if isNight && !hasActiveUnlock {
            interval = nightInterval
        } else if hasActiveUnlock {
            interval = activeInterval
        } else {
            interval = idleInterval
        }
        return now.addingTimeInterval(interval)
    }

    static func hasAnyActiveUnlock(defaults g: UserDefaults) -> Bool {
        guard let data = g.data(forKey: SharedKeys.ticketGroups)
                ?? g.data(forKey: SharedKeys.legacyShieldGroups),
              let decoded = try? JSONDecoder().decode([_MinGroupStub].self, from: data) else {
            return false
        }
        return decoded.contains { g.integer(forKey: SharedKeys.usageBudgetKey($0.id)) > 0 }
    }

    private struct _MinGroupStub: Decodable { let id: String }
}

// MARK: - Timeline Provider

struct UnlockTimelineProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> UnlockEntry {
        UnlockEntry(
            date: .now,
            groups: [
                .init(id: "placeholder", name: "Apps",
                      enabledIntervals: [.minutes10, .minutes30, .hour1],
                      isUnlocked: false,
                      templateApp: nil, appsCount: 1, spentToday: 0,
                      budgetMinutes: 0, budgetInitial: 0,
                      budgetExpiryDate: nil)
            ],
            colorsBalance: 12,
            selectedGroupIds: [],
            mediumMode: .stats,
            wallpaperBackground: nil,
            energyData: .init(remaining: 11, earned: 15, bonus: 0, maxEnergy: 100,
                              stepsPoints: 0, sleepPoints: 15,
                              bodyPoints: 0, mindPoints: 0, heartPoints: 0,
                              resetDate: nil)
        )
    }

    func snapshot(for configuration: SelectGroupIntent, in context: Context) async -> UnlockEntry {
        buildEntry(at: Date(), selectedGroupIds: configuration.selectedIds)
    }

    func timeline(for configuration: SelectGroupIntent, in context: Context) async -> Timeline<UnlockEntry> {
        UserDefaults(suiteName: SharedKeys.appGroupId)?.set(true, forKey: SharedKeys.hasLargeWidget)

        let now = Date()
        let ids = configuration.selectedIds
        let currentEntry = buildEntry(at: now, selectedGroupIds: ids)

        var entries: [UnlockEntry] = [currentEntry]

        let g = UserDefaults(suiteName: SharedKeys.appGroupId)
        let dayEndHour = g?.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndMinute = g?.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let resetDate = nextResetDate(hour: dayEndHour, minute: dayEndMinute)

        let hasUnlock = g.map { WidgetRefreshPolicy.hasAnyActiveUnlock(defaults: $0) } ?? false
        var refreshPolicy = WidgetRefreshPolicy.nextRefreshDate(from: now, hasActiveUnlock: hasUnlock)

        if let resetDate, resetDate < refreshPolicy {
            let resetEntry = buildEntry(at: resetDate, selectedGroupIds: ids)
            entries.append(resetEntry)
            refreshPolicy = resetDate.addingTimeInterval(60)
        }

        return Timeline(entries: entries, policy: .after(refreshPolicy))
    }

    // MARK: - Build Entry

    private func buildEntry(at date: Date, selectedGroupIds: [String]) -> UnlockEntry {
        guard let g = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            return fallbackEntry(at: date)
        }

        let result = buildEnergyData(defaults: g, at: date)
        let balance = result.balance
        let energy = result.energy

        let modeRaw = g.string(forKey: WidgetPrefsKeys.mediumMode) ?? "stats"
        let mediumMode = MediumWidgetMode(rawValue: modeRaw) ?? .stats

        let selectedIds = selectedGroupIds

        var snapshots: [UnlockEntry.GroupSnapshot] = []
        let activeGroupIds = loadActiveGroupIds(defaults: g)

        if let data = g.data(forKey: SharedKeys.ticketGroups)
                ?? g.data(forKey: SharedKeys.legacyShieldGroups),
           let decoded = try? JSONDecoder().decode([WidgetGroupStub].self, from: data) {

            snapshots = decoded
                .filter { group in
                    if let activeGroupIds {
                        return activeGroupIds.contains(group.id)
                    }
                    return group.hasActiveSettings
                }
                .map { group in
                let budgetKey = SharedKeys.usageBudgetKey(group.id)
                let budgetMinutes = g.integer(forKey: budgetKey)
                let budgetInitial = g.integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))

                let intervals: Set<AccessWindow> = {
                    guard let raw = group.enabledIntervals else {
                        return [.minutes10, .minutes30, .hour1]
                    }
                    let parsed = Set(raw.compactMap { AccessWindow(rawValue: $0) })
                    return parsed.isEmpty ? [.minutes10, .minutes30, .hour1] : parsed
                }()

                let expiryDate: Date? = budgetMinutes > 0
                    ? date.addingTimeInterval(TimeInterval(budgetMinutes * 60))
                    : nil

                return UnlockEntry.GroupSnapshot(
                    id: group.id,
                    name: group.name,
                    enabledIntervals: intervals,
                    isUnlocked: budgetMinutes > 0,
                    templateApp: group.templateApp,
                    appsCount: 1,
                    spentToday: 0,
                    budgetMinutes: budgetMinutes,
                    budgetInitial: budgetInitial,
                    budgetExpiryDate: expiryDate
                )
            }
        }

        let bgMode = g.string(forKey: SharedKeys.widgetBackgroundMode) ?? "basic"
        let wallpaperImage: UIImage? = bgMode == "wallpaper" ? loadWallpaperBackground() : nil

        return UnlockEntry(
            date: date,
            groups: snapshots,
            colorsBalance: balance,
            selectedGroupIds: selectedIds,
            mediumMode: mediumMode,
            wallpaperBackground: wallpaperImage,
            energyData: energy
        )
    }

    private func fallbackEntry(at date: Date) -> UnlockEntry {
        UnlockEntry(
            date: date, groups: [], colorsBalance: 0,
            selectedGroupIds: [], mediumMode: .stats,
            wallpaperBackground: nil,
            energyData: .init(remaining: 0, earned: 0, bonus: 0, maxEnergy: 100,
                              stepsPoints: 0, sleepPoints: 0,
                              bodyPoints: 0, mindPoints: 0, heartPoints: 0,
                              resetDate: nil)
        )
    }

    // MARK: - Energy Data

    private func buildEnergyData(defaults g: UserDefaults, at date: Date) -> (balance: Int, earned: Int, energy: UnlockEntry.EnergyData) {
        let dayEndHour = g.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndMinute = g.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let resetDate = nextResetDate(hour: dayEndHour, minute: dayEndMinute)
        let bonus = g.integer(forKey: SharedKeys.bonusSteps)

        let snap = WidgetDataFile.read()
        let sameDay = snap.map { isSameWidgetDay($0.timestamp, date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute) } ?? false

        if let snap, sameDay {
            let remaining = min(100, max(0, snap.balance - bonus))
            return (
                balance: snap.balance,
                earned: snap.earned,
                energy: UnlockEntry.EnergyData(
                    remaining: remaining,
                    earned: min(100, snap.earned),
                    bonus: bonus,
                    maxEnergy: 100,
                    stepsPoints: snap.stepsPoints,
                    sleepPoints: snap.sleepPoints,
                    bodyPoints: snap.bodyPoints,
                    mindPoints: snap.mindPoints,
                    heartPoints: snap.heartPoints,
                    resetDate: resetDate
                )
            )
        }

        let stepsBalance = g.integer(forKey: SharedKeys.stepsBalance)
        let balance = stepsBalance + bonus
        let earned = g.integer(forKey: SharedKeys.baseEnergyToday)

        return (
            balance: balance,
            earned: earned,
            energy: UnlockEntry.EnergyData(
                remaining: min(100, max(0, stepsBalance)),
                earned: min(100, earned),
                bonus: bonus,
                maxEnergy: 100,
                stepsPoints: 0, sleepPoints: 0,
                bodyPoints: 0, mindPoints: 0, heartPoints: 0,
                resetDate: resetDate
            )
        )
    }

    private func isSameWidgetDay(_ a: Date, _ b: Date, dayEndHour: Int, dayEndMinute: Int) -> Bool {
        DayBoundary.currentDayStart(for: a, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
            == DayBoundary.currentDayStart(for: b, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }

    private func nextResetDate(hour: Int, minute: Int) -> Date? {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.nextDate(
            after: Date(),
            matching: comps,
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
    }

    // MARK: - Image Loading

    private func loadWallpaperBackground() -> UIImage? {
        loadSharedImage(named: "wallpaper_bg.jpg")
    }

    private func loadSharedImage(named filename: String) -> UIImage? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedKeys.appGroupId
        ) else { return nil }

        let url = containerURL
            .appendingPathComponent("widget_snapshots", isDirectory: true)
            .appendingPathComponent(filename)

        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func loadActiveGroupIds(defaults: UserDefaults) -> Set<String>? {
        if let data = defaults.data(forKey: SharedKeys.liteTicketConfig),
           let lite = try? JSONDecoder().decode(WidgetLiteTicketConfig.self, from: data) {
            return Set(lite.groups.filter(\.active).map(\.id))
        }

        guard let legacyData = defaults.data(forKey: SharedKeys.liteShieldConfig),
              let lite = try? JSONDecoder().decode(WidgetLiteTicketConfig.self, from: legacyData) else {
            return nil
        }
        return Set(lite.groups.filter(\.active).map(\.id))
    }

    private struct WidgetGroupStub: Decodable {
        let id: String
        let name: String
        let enabledIntervals: [String]?
        let templateApp: String?
        let settings: SettingsBlock?

        var hasActiveSettings: Bool {
            settings?.familyControlsModeEnabled ?? true
        }

        struct SettingsBlock: Decodable {
            let familyControlsModeEnabled: Bool?
        }
    }

    private struct WidgetLiteTicketConfig: Decodable {
        let groups: [LiteGroup]

        struct LiteGroup: Decodable {
            let id: String
            let active: Bool
        }
    }
}

// MARK: - Static Timeline Provider (for medium — no configuration)

struct StatusTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> UnlockEntry {
        UnlockEntry(
            date: .now,
            groups: [],
            colorsBalance: 0,
            selectedGroupIds: [],
            mediumMode: .stats,
            wallpaperBackground: nil,
            energyData: .init(remaining: 0, earned: 0, bonus: 0, maxEnergy: 100,
                              stepsPoints: 0, sleepPoints: 0,
                              bodyPoints: 0, mindPoints: 0, heartPoints: 0,
                              resetDate: nil)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UnlockEntry) -> Void) {
        completion(buildStatusEntry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnlockEntry>) -> Void) {
        UserDefaults(suiteName: SharedKeys.appGroupId)?.set(true, forKey: SharedKeys.hasMediumWidget)

        let now = Date()
        let entry = buildStatusEntry(at: now)

        var entries: [UnlockEntry] = [entry]

        let g = UserDefaults(suiteName: SharedKeys.appGroupId)
        let dayEndHour = g?.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndMinute = g?.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0

        let hasUnlock = g.map { WidgetRefreshPolicy.hasAnyActiveUnlock(defaults: $0) } ?? false
        var refreshPolicy = WidgetRefreshPolicy.nextRefreshDate(from: now, hasActiveUnlock: hasUnlock)

        if let resetDate = nextResetDate(hour: dayEndHour, minute: dayEndMinute),
           resetDate < refreshPolicy {
            let resetEntry = buildStatusEntry(at: resetDate)
            entries.append(resetEntry)
            refreshPolicy = resetDate.addingTimeInterval(60)
        }

        completion(Timeline(entries: entries, policy: .after(refreshPolicy)))
    }

    private func nextResetDate(hour: Int, minute: Int) -> Date? {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.nextDate(
            after: Date(),
            matching: comps,
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
    }

    private func buildStatusEntry(at date: Date) -> UnlockEntry {
        guard let g = UserDefaults(suiteName: SharedKeys.appGroupId) else {
            return fallbackEntry(at: date)
        }

        let dayEndHour = g.object(forKey: SharedKeys.dayEndHour) as? Int ?? 0
        let dayEndMinute = g.object(forKey: SharedKeys.dayEndMinute) as? Int ?? 0
        let bonus = g.integer(forKey: SharedKeys.bonusSteps)

        let snap = WidgetDataFile.read()
        let sameDay = snap.map { isSameDay($0.timestamp, date, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute) } ?? false

        let balance: Int
        let earned: Int
        let stepsPoints: Int
        let sleepPoints: Int
        let bodyPoints: Int
        let mindPoints: Int
        let heartPoints: Int

        if let snap, sameDay {
            balance = snap.balance
            earned = snap.earned
            stepsPoints = snap.stepsPoints
            sleepPoints = snap.sleepPoints
            bodyPoints = snap.bodyPoints
            mindPoints = snap.mindPoints
            heartPoints = snap.heartPoints
        } else {
            let stepsBalance = g.integer(forKey: SharedKeys.stepsBalance)
            balance = stepsBalance + bonus
            earned = g.integer(forKey: SharedKeys.baseEnergyToday)
            stepsPoints = 0
            sleepPoints = 0
            bodyPoints = 0
            mindPoints = 0
            heartPoints = 0
        }

        let remaining = min(100, max(0, balance - bonus))

        let resetDate: Date? = {
            var comps = DateComponents()
            comps.hour = dayEndHour
            comps.minute = dayEndMinute
            return Calendar.current.nextDate(after: Date(), matching: comps,
                                             matchingPolicy: .nextTimePreservingSmallerComponents)
        }()

        return UnlockEntry(
            date: date,
            groups: [],
            colorsBalance: balance,
            selectedGroupIds: [],
            mediumMode: .stats,
            wallpaperBackground: nil,
            energyData: UnlockEntry.EnergyData(
                remaining: remaining,
                earned: min(100, earned),
                bonus: bonus,
                maxEnergy: 100,
                stepsPoints: stepsPoints,
                sleepPoints: sleepPoints,
                bodyPoints: bodyPoints,
                mindPoints: mindPoints,
                heartPoints: heartPoints,
                resetDate: resetDate
            )
        )
    }

    private func fallbackEntry(at date: Date) -> UnlockEntry {
        UnlockEntry(
            date: date, groups: [], colorsBalance: 0,
            selectedGroupIds: [], mediumMode: .stats,
            wallpaperBackground: nil,
            energyData: .init(remaining: 0, earned: 0, bonus: 0, maxEnergy: 100,
                              stepsPoints: 0, sleepPoints: 0,
                              bodyPoints: 0, mindPoints: 0, heartPoints: 0,
                              resetDate: nil)
        )
    }

    private func isSameDay(_ a: Date, _ b: Date, dayEndHour: Int, dayEndMinute: Int) -> Bool {
        DayBoundary.currentDayStart(for: a, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
            == DayBoundary.currentDayStart(for: b, dayEndHour: dayEndHour, dayEndMinute: dayEndMinute)
    }
}
