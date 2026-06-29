import Foundation
import os.log

// MARK: - Supabase Sync Service
/// Handles syncing user data to Supabase
actor SupabaseSyncService {
    
    nonisolated static let shared = SupabaseSyncService()
    
    let network = NetworkClient.shared

    private init() {
        let g = UserDefaults(suiteName: SharedKeys.appGroupId) ?? .standard
        let ttl = g.double(forKey: SharedKeys.supabaseTodayCacheTTLSeconds)
        self.todayCacheTTL = ttl > 0 ? ttl : 30
        let pageSize = g.integer(forKey: SharedKeys.supabaseHistoryPageSize)
        self.historicalPageSize = pageSize > 0 ? pageSize : 500
        let refreshTTL = g.double(forKey: SharedKeys.supabaseHistoryRefreshTTLSeconds)
        self.historicalRefreshTTL = refreshTTL > 0 ? refreshTTL : 86_400
    }
    
    // MARK: - Debounce Timers
    
    var customActivitiesSyncTask: Task<Void, Never>?
    var dailySelectionsSyncTask: Task<Void, Never>?
    var dailyStatsSyncTask: Task<Void, Never>?
    var dailySpentSyncTask: Task<Void, Never>?
    var ticketGroupsSyncTask: Task<Void, Never>?
    var analyticsFlushTask: Task<Void, Never>?
    var dayCanvasSyncTask: Task<Void, Never>?
    var preferencesSyncTask: Task<Void, Never>?
    var daySnapshotSyncTask: Task<Void, Never>?
    var entriesSyncTask: Task<Void, Never>?
    
    // MARK: - Debounce Windows (nanoseconds)
    
    let selectionsDebounceDuration: Duration = .seconds(1.5)
    let statsDebounceDuration: Duration = .seconds(2)
    let spentDebounceDuration: Duration = .seconds(1.5)
    
    var lastSyncedCustomActivitiesHash: Int = 0
    var lastSyncedDayKey: String = ""
    
    // MARK: - Read-Cache (TTL) for Today's Data
    
    struct CachedTodayValue<T> {
        let dayKey: String
        let value: T
        let timestamp: Date
    }
    
    // Cached at init to avoid reading UserDefaults from actor context on every call.
    let todayCacheTTL: TimeInterval
    var cachedTodaySelections: CachedTodayValue<(body: [String], mind: [String], heart: [String])>?
    var cachedTodayStats: CachedTodayValue<(steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int)>?
    var cachedTodaySpent: CachedTodayValue<(totalSpent: Int, spentByApp: [String: Int])>?
    
    // MARK: - Historical Pagination
    
    let historicalPageSize: Int
    let historicalRefreshTTL: TimeInterval
    var historicalLastFullSyncKey: String { "supabaseHistoryLastFullSync_v1" }
    var historicalLastDayKeyKey: String { "supabaseHistoryLastDayKey_v1" }
    
    // MARK: - Payload Coalescing + Dedup
    
    struct DailySelectionsPayload: Equatable {
        let dayKey: String
        let activityIds: [String]
        let recoveryIds: [String]
        let joysIds: [String]
    }
    
    struct DailyStatsPayload: Equatable {
        let dayKey: String
        let steps: Int
        let sleepHours: Double
        let baseEnergy: Int
        let bonusEnergy: Int
        let remainingBalance: Int
    }
    
    struct DailySpentPayload: Equatable {
        let dayKey: String
        let totalSpent: Int
        let spentByApp: [String: Int]
    }
    
    struct DayCanvasSyncPayload: Equatable {
        let dayKey: String
        let canvasJsonData: Data
        let lastModified: Date
        
        static func == (lhs: DayCanvasSyncPayload, rhs: DayCanvasSyncPayload) -> Bool {
            lhs.dayKey == rhs.dayKey && lhs.canvasJsonData == rhs.canvasJsonData
        }
    }
    
    struct UserPreferencesPayload: Equatable {
        let stepsTarget: Double
        let sleepTarget: Double
        let dayEndHour: Int
        let dayEndMinute: Int
        let restDayOverride: Bool
        let preferredBody: [String]
        let preferredMind: [String]
        let preferredHeart: [String]
        let canvasSlots: [DayCanvasSlot]
        let hasWallpaperShortcut: Bool
        let wallpaperShortcutUses: Int
        let notifyOneMinBefore: Bool
        let notifyWhenTimerOver: Bool
        let notifyCanvasReminder: Bool
        let canvasReminderHour: Int
        let canvasReminderMinute: Int
        let notifyDayResetWarning: Bool
        let dayResetWarningHours: Int
        let hasMediumWidget: Bool
        let hasLargeWidget: Bool
        let lastOpenedAt: Date?
        let gradientStyle: String
        let gradientPalette: String
        let userGradientStyle: String
        let userGradientPalette: String
        let dailyRandomThemeEnabled: Bool
        let canvasOverlayStyle: String
        let bodyCanvasShape: String
        let mindCanvasShape: String
        let heartCanvasShape: String
    }
    
    var pendingDailySelections: DailySelectionsPayload?
    var pendingDailyStats: DailyStatsPayload?
    var pendingDailySpent: DailySpentPayload?
    var pendingDayCanvas: DayCanvasSyncPayload?
    var pendingPreferences: UserPreferencesPayload?
    
    var lastSentDailySelections: DailySelectionsPayload?
    var lastSentDailyStats: DailyStatsPayload?
    var lastSentDailySpent: DailySpentPayload?
    var lastSentDayCanvas: DayCanvasSyncPayload?
    var lastSentPreferences: UserPreferencesPayload?
    var pendingTicketGroupsPayload: [TicketGroupSyncRow] = []
    var lastSentTicketGroupsPayload: [TicketGroupSyncRow] = []
    var pendingAnalyticsEvents: [AnalyticsEventPayload] = loadAnalyticsQueueFromDefaults()
    var analyticsDedupeKeys: Set<String> = []
    
    
    // MARK: - Offline Retry Queue
    
    private struct PendingSyncRequest: Codable {
        let urlString: String
        let method: String
        let body: Data?
        let preferHeader: String?
        let createdAt: Date
        
        var isExpired: Bool { Date.now.timeIntervalSince(createdAt) > 86_400 * 3 } // 3 days TTL
    }
    
    private static let retryQueueKey = "supabaseSyncRetryQueue_v1"
    private static let maxRetryQueueSize = 50
    
    func enqueueForRetry(_ request: URLRequest) {
        guard let url = request.url?.absoluteString else { return }
        let entry = PendingSyncRequest(
            urlString: url,
            method: request.httpMethod ?? "POST",
            body: request.httpBody,
            preferHeader: request.value(forHTTPHeaderField: "prefer"),
            createdAt: Date.now
        )
        var queue = loadRetryQueue()
        queue.append(entry)
        if queue.count > Self.maxRetryQueueSize {
            queue = Array(queue.suffix(Self.maxRetryQueueSize))
        }
        saveRetryQueue(queue)
        AppLogger.network.debug("📡 Enqueued failed sync for offline retry (\(queue.count) pending)")
    }
    
    private func loadRetryQueue() -> [PendingSyncRequest] {
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: Self.retryQueueKey),
              let decoded = try? JSONDecoder().decode([PendingSyncRequest].self, from: data) else {
            return []
        }
        return decoded
    }
    
    private func saveRetryQueue(_ queue: [PendingSyncRequest]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        let g = UserDefaults.stepsTrader()
        g.set(data, forKey: Self.retryQueueKey)
    }
    
    /// Drain the offline retry queue. Call on app launch or when connectivity is restored.
    func drainRetryQueue() async {
        let queue = loadRetryQueue().filter { !$0.isExpired }
        guard !queue.isEmpty else { return }
        AppLogger.network.debug("📡 Draining \(queue.count) queued sync requests")
        
        await AuthenticationService.shared.waitForInitialization()
        guard let freshToken = await AuthenticationService.shared.accessToken else {
            AppLogger.network.debug("📡 Retry queue drain skipped: no auth token")
            return
        }
        
        let anonKey: String
        do {
            anonKey = try SupabaseConfig.load().anonKey
        } catch {
            AppLogger.network.error("📡 Retry queue drain skipped: config unavailable")
            return
        }
        
        var remaining: [PendingSyncRequest] = []
        for entry in queue {
            guard let url = URL(string: entry.urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = entry.method
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            if let prefer = entry.preferHeader {
                request.setValue(prefer, forHTTPHeaderField: "prefer")
            }
            request.httpBody = entry.body
            
            do {
                let (_, response) = try await network.data(for: request)
                if response.statusCode >= 400 {
                    remaining.append(entry)
                }
            } catch {
                remaining.append(entry)
            }
        }
        
        saveRetryQueue(remaining)
        AppLogger.network.debug("📡 Retry queue drained: \(queue.count - remaining.count) succeeded, \(remaining.count) still pending")
    }
    
    // MARK: - Shared Helpers

    struct AuthContext {
        let token: String
        let userId: String
    }

    /// Waits for auth initialization and returns token + userId, or nil if unauthenticated.
    func authenticatedContext() async -> AuthContext? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.freshAccessToken(),
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        return AuthContext(token: token, userId: userId)
    }

    func iso8601String(_ date: Date) -> String {
        CachedFormatters.iso8601.string(from: date)
    }
    
    func fetchPagedRows<T: Decodable>(
        endpoint: URL,
        token: String,
        anonKey: String,
        baseQuery: [URLQueryItem],
        pageSize: Int
    ) async throws -> [T] {
        var all: [T] = []
        var offset = 0
        let decoder = JSONDecoder()
        
        while true {
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                throw SyncError.misconfigured
            }
            comps.queryItems = baseQuery + [
                URLQueryItem(name: "limit", value: "\(pageSize)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
            
            guard let url = comps.url else { throw SyncError.misconfigured }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else {
                throw SyncError.networkError
            }
            
            let rows = try decoder.decode([T].self, from: data)
            all.append(contentsOf: rows)
            
            if rows.count < pageSize {
                break
            }
            
            offset += pageSize
        }
        
        return all
    }
    
    // MARK: - Full Sync (Orchestrator)
    
    /// Full sync - call on app launch or after login
    func performFullSync(model: AppModel) async {
        AppLogger.network.debug("📡 performFullSync called, waiting for auth initialization...")
        
        await AuthenticationService.shared.waitForInitialization()
        let isAuthenticated = await AuthenticationService.shared.isAuthenticated
        let currentUserId = await AuthenticationService.shared.currentUser?.id
        let hasToken = await AuthenticationService.shared.accessToken != nil
        
        AppLogger.network.debug("📡 Auth initialized. isAuthenticated: \(isAuthenticated)")
        AppLogger.network.debug("📡 currentUser: \(currentUserId ?? "nil")")
        AppLogger.network.debug("📡 accessToken: \(hasToken ? "exists" : "nil")")
        
        guard isAuthenticated, currentUserId != nil else {
            AppLogger.network.debug("📡 Sync skipped: user not authenticated")
            return
        }
        
        AppLogger.network.debug("📡 Starting full Supabase sync...")
        
        let snapshot = await MainActor.run {
            let g = UserDefaults.stepsTrader()
            return (
                customEnergyOptions: model.customEnergyOptions,
                dailyBodySelections: model.dailyBodySelections,
                dailyRestSelections: model.dailyRestSelections,
                dailyHeartSelections: model.dailyHeartSelections,
                stepsToday: model.healthStore.stepsToday,
                dailySleepHours: model.healthStore.dailySleepHours,
                baseEnergyToday: model.healthStore.baseEnergyToday,
                bonusSteps: 0,
                totalStepsBalance: model.userEconomyStore.totalStepsBalance,
                appStepsSpentByDay: model.userEconomyStore.appStepsSpentByDay,
                stepsTarget: g.object(forKey: SharedKeys.userStepsTarget) as? Double ?? EnergyDefaults.stepsTarget,
                sleepTarget: g.object(forKey: SharedKeys.userSleepTarget) as? Double ?? EnergyDefaults.sleepTargetHours,
                dayEndHour: model.dayEndHour,
                dayEndMinute: model.dayEndMinute,
                restDayOverride: model.isRestDayOverrideEnabled,
                preferredBody: model.preferredBodyOptions,
                preferredMind: model.preferredRestOptions,
                preferredHeart: model.preferredHeartOptions,
                canvasSlots: model.dailyCanvasSlots,
                ticketGroups: model.ticketGroups
            )
        }
        
        let today = AppModel.dayKey(for: Date.now)
        let todaySpent = snapshot.appStepsSpentByDay[today] ?? [:]
        let totalSpent = todaySpent.values.reduce(0, +)
        let g = UserDefaults(suiteName: SharedKeys.appGroupId) ?? UserDefaults.standard
        let ticketRows = snapshot.ticketGroups
            .map { TicketGroupSyncRow.from(group: $0) }
            .sorted { $0.bundleId < $1.bundleId }

        let hasLocalData = !snapshot.dailyBodySelections.isEmpty
            || !snapshot.dailyRestSelections.isEmpty
            || !snapshot.dailyHeartSelections.isEmpty
            || snapshot.stepsToday > 0

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.performCustomActivitiesSync(snapshot.customEnergyOptions) }
            if hasLocalData {
                group.addTask {
                    await self.performDailySelectionsSync(
                        payload: DailySelectionsPayload(
                            dayKey: today,
                            activityIds: snapshot.dailyBodySelections,
                            recoveryIds: snapshot.dailyRestSelections,
                            joysIds: snapshot.dailyHeartSelections
                        )
                    )
                }
                group.addTask {
                    await self.performDailyStatsSync(
                        payload: DailyStatsPayload(
                            dayKey: today,
                            steps: Int(snapshot.stepsToday),
                            sleepHours: snapshot.dailySleepHours,
                            baseEnergy: snapshot.baseEnergyToday,
                            bonusEnergy: 0,
                            remainingBalance: snapshot.totalStepsBalance
                        )
                    )
                }
                group.addTask {
                    await self.performDailySpentSync(
                        payload: DailySpentPayload(
                            dayKey: today,
                            totalSpent: totalSpent,
                            spentByApp: todaySpent
                        )
                    )
                }
            } else {
                AppLogger.network.debug("📡 Skipping daily data push — local state is empty (likely fresh install)")
            }
            group.addTask {
                let std = UserDefaults.standard
                await self.performPreferencesSync(
                    payload: UserPreferencesPayload(
                        stepsTarget: snapshot.stepsTarget,
                        sleepTarget: snapshot.sleepTarget,
                        dayEndHour: snapshot.dayEndHour,
                        dayEndMinute: snapshot.dayEndMinute,
                        restDayOverride: snapshot.restDayOverride,
                        preferredBody: snapshot.preferredBody,
                        preferredMind: snapshot.preferredMind,
                        preferredHeart: snapshot.preferredHeart,
                        canvasSlots: snapshot.canvasSlots,
                        hasWallpaperShortcut: g.bool(forKey: "hasWallpaperShortcut"),
                        wallpaperShortcutUses: g.integer(forKey: "wallpaperShortcutUses"),
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
                )
            }
            group.addTask { await self.performTicketGroupsSync(rows: ticketRows) }
        }
        
        AppLogger.network.debug("📡 Full sync completed")
    }
    
    // MARK: - Full Restore (Orchestrator)
    
    /// Full restore - load all data from Supabase and apply to AppModel
    func restoreFromServer(model: AppModel) async -> Bool {
        AppLogger.network.debug("📡 Starting restore from Supabase...")
        
        await AuthenticationService.shared.waitForInitialization()
        let isAuthenticated = await AuthenticationService.shared.isAuthenticated
        let currentUser = await AuthenticationService.shared.currentUser
        guard isAuthenticated, currentUser != nil else {
            AppLogger.network.debug("📡 Restore skipped: user not authenticated")
            return false
        }
        
        var didRestore = false
        
        if let customActivities = await loadCustomActivitiesFromServer(), !customActivities.isEmpty {
            await MainActor.run {
                model.customEnergyOptions = customActivities
            }
            didRestore = true
        }
        
        if let selections = await loadTodaySelectionsFromServer() {
            let hasData = !selections.body.isEmpty || !selections.mind.isEmpty || !selections.heart.isEmpty
            if hasData {
                await MainActor.run {
                    model.dailyBodySelections = selections.body
                    model.dailyRestSelections = selections.mind
                    model.dailyHeartSelections = selections.heart
                    model.persistDailyEnergyState()
                }
                didRestore = true
            }
        }
        
        if let spent = await loadTodaySpentFromServer() {
            if spent.totalSpent > 0 {
                await MainActor.run {
                    model.spentStepsToday = spent.totalSpent
                    let today = AppModel.dayKey(for: Date.now)
                    model.appStepsSpentByDay[today] = spent.spentByApp
                    model.persistAppStepsSpentToday()
                }
                didRestore = true
            }
        }
        
        if let prefs = await loadUserPreferencesFromServer() {
            await MainActor.run {
                let g = UserDefaults.stepsTrader()
                let std = UserDefaults.standard
                g.set(prefs.stepsTarget, forKey: SharedKeys.userStepsTarget)
                g.set(prefs.sleepTarget, forKey: SharedKeys.userSleepTarget)
                g.set(prefs.dayEndHour, forKey: SharedKeys.dayEndHour)
                g.set(prefs.dayEndMinute, forKey: SharedKeys.dayEndMinute)
                g.set(prefs.restDayOverride, forKey: SharedKeys.restDayOverrideEnabled)
                g.set(prefs.hasWallpaperShortcut, forKey: "hasWallpaperShortcut")
                g.set(prefs.wallpaperShortcutUses, forKey: "wallpaperShortcutUses")
                g.set(prefs.notifyOneMinBefore, forKey: SharedKeys.notifyOneMinBefore)
                g.set(prefs.notifyWhenTimerOver, forKey: SharedKeys.notifyWhenTimerOver)
                g.set(prefs.notifyCanvasReminder, forKey: SharedKeys.notifyCanvasReminder)
                g.set(prefs.canvasReminderHour, forKey: SharedKeys.canvasReminderHour)
                g.set(prefs.canvasReminderMinute, forKey: SharedKeys.canvasReminderMinute)
                g.set(prefs.notifyDayResetWarning, forKey: SharedKeys.notifyDayResetWarning)
                g.set(prefs.dayResetWarningHours, forKey: SharedKeys.dayResetWarningHours)
                // Appearance: theme + overlay
                std.set(prefs.gradientStyle, forKey: SharedKeys.gradientStyle)
                std.set(prefs.gradientPalette, forKey: SharedKeys.gradientPalette)
                std.set(prefs.userGradientStyle, forKey: SharedKeys.userGradientStyle)
                std.set(prefs.userGradientPalette, forKey: SharedKeys.userGradientPalette)
                std.set(prefs.dailyRandomThemeEnabled, forKey: SharedKeys.dailyRandomThemeEnabled)
                g.set(prefs.canvasOverlayStyle, forKey: SharedKeys.canvasOverlayStyle)
                std.set(prefs.bodyCanvasShape, forKey: SharedKeys.bodyCanvasShape)
                std.set(prefs.mindCanvasShape, forKey: SharedKeys.mindCanvasShape)
                std.set(prefs.heartCanvasShape, forKey: SharedKeys.heartCanvasShape)
                // Mirror theme to app group for widget/extension
                if let group = UserDefaults(suiteName: SharedKeys.appGroupId) {
                    group.set(prefs.gradientStyle, forKey: SharedKeys.gradientStyle)
                    group.set(prefs.gradientPalette, forKey: SharedKeys.gradientPalette)
                }
                model.dayEndHour = prefs.dayEndHour
                model.dayEndMinute = prefs.dayEndMinute
                model.preferredBodyOptions = prefs.preferredBody
                model.preferredRestOptions = prefs.preferredMind
                model.preferredHeartOptions = prefs.preferredHeart
                if !prefs.canvasSlots.isEmpty {
                    model.dailyCanvasSlots = prefs.canvasSlots
                }
                model.persistDailyEnergyState()
            }
            didRestore = true
            AppLogger.network.debug("📡 Restored user preferences (including theme + notification settings)")
        }
        
        let serverSnapshots = await loadDaySnapshotsFromServer()
        if !serverSnapshots.isEmpty {
            await MainActor.run {
                var local = model.loadPastDaySnapshots()
                for (dayKey, serverSnapshot) in serverSnapshots {
                    local[dayKey] = serverSnapshot
                }
                let url = PersistenceManager.pastDaySnapshotsFileURL
                if let data = try? JSONEncoder().encode(local) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            didRestore = true
            AppLogger.network.debug("📡 Merged \(serverSnapshots.count) day snapshots from server")
        }

        // Restore option entries (journal notes/colors) for today
        let today = AppModel.dayKey(for: Date.now)
        if let entries = await loadOptionEntriesFromServer(dayKey: today), !entries.isEmpty {
            AppLogger.network.debug("📡 Restored \(entries.count) option entries for today")
            didRestore = true
        }

        // Restore saved routines
        if let routines = await loadSavedRoutinesFromServer(), !routines.isEmpty {
            await MainActor.run {
                model.savedRoutines = routines
                let g = UserDefaults.stepsTrader()
                if let data = try? JSONEncoder().encode(routines) {
                    g.set(data, forKey: SharedKeys.savedRoutines)
                }
            }
            didRestore = true
            AppLogger.network.debug("📡 Restored \(routines.count) saved routines from server")
        }
        
        if didRestore {
            AppLogger.network.debug("📡 Restore completed, recalculating energy...")
            await MainActor.run {
                model.recalculateDailyEnergy()
            }
        } else {
            AppLogger.network.debug("📡 No data to restore from server (or all empty)")
        }
        
        return didRestore
    }
}
