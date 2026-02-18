import Foundation
import os.log

/// Loads persisted analytics queue from UserDefaults. Used from actor property default (nonisolated).
private func loadAnalyticsQueueFromDefaults() -> [AnalyticsEventPayload] {
    let g = UserDefaults.stepsTrader()
    guard let data = g.data(forKey: SharedKeys.analyticsEventsQueue),
          let decoded = try? JSONDecoder().decode([AnalyticsEventPayload].self, from: data) else {
        return []
    }
    return decoded
}

// MARK: - Supabase Sync Service
/// Handles syncing user activity data to Supabase
actor SupabaseSyncService {
    
    nonisolated static let shared = SupabaseSyncService()
    
    private let network = NetworkClient.shared
    
    // Debounce timers to avoid too frequent syncs (also used for batching/coalescing)
    private var customActivitiesSyncTask: Task<Void, Never>?
    private var dailySelectionsSyncTask: Task<Void, Never>?
    private var dailyStatsSyncTask: Task<Void, Never>?
    private var dailySpentSyncTask: Task<Void, Never>?
    private var activityStatsSyncTask: Task<Void, Never>?
    private var ticketGroupsSyncTask: Task<Void, Never>?
    private var analyticsFlushTask: Task<Void, Never>?
    private var dayCanvasSyncTask: Task<Void, Never>?
    private var preferencesSyncTask: Task<Void, Never>?
    private var daySnapshotSyncTask: Task<Void, Never>?
    
    // Debounce windows (nanoseconds)
    private let selectionsDebounceNs: UInt64 = 1_500_000_000 // 1.5 sec
    private let statsDebounceNs: UInt64 = 2_000_000_000 // 2 sec
    private let spentDebounceNs: UInt64 = 1_500_000_000 // 1.5 sec
    
    private var lastSyncedCustomActivitiesHash: Int = 0
    private var lastSyncedDayKey: String = ""
    
    // Read-cache (TTL) for today's data
    private struct CachedTodayValue<T> {
        let dayKey: String
        let value: T
        let timestamp: Date
    }
    
    private var todayCacheTTL: TimeInterval {
        let g = UserDefaults.stepsTrader()
        let stored = g.double(forKey: "supabaseTodayCacheTTLSeconds_v1")
        return stored > 0 ? stored : 30
    }
    private var cachedTodaySelections: CachedTodayValue<(activity: [String], rest: [String], joys: [String])>?
    private var cachedTodayStats: CachedTodayValue<(steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int)>?
    private var cachedTodaySpent: CachedTodayValue<(totalSpent: Int, spentByApp: [String: Int])>?
    
    // Historical pagination
    private var historicalPageSize: Int {
        let g = UserDefaults.stepsTrader()
        let stored = g.integer(forKey: "supabaseHistoryPageSize_v1")
        return stored > 0 ? stored : 500
    }
    
    private var historicalRefreshTTL: TimeInterval {
        let g = UserDefaults.stepsTrader()
        let stored = g.double(forKey: "supabaseHistoryRefreshTTLSeconds_v1")
        return stored > 0 ? stored : 86_400 // 24h
    }
    private var historicalLastFullSyncKey: String { "supabaseHistoryLastFullSync_v1" }
    private var historicalLastDayKeyKey: String { "supabaseHistoryLastDayKey_v1" }
    
    // Payload coalescing + dedup
    private struct DailySelectionsPayload: Equatable {
        let dayKey: String
        let activityIds: [String]
        let recoveryIds: [String]
        let joysIds: [String]
    }
    
    private struct DailyStatsPayload: Equatable {
        let dayKey: String
        let steps: Int
        let sleepHours: Double
        let baseEnergy: Int
        let bonusEnergy: Int
        let remainingBalance: Int
    }
    
    private struct DailySpentPayload: Equatable {
        let dayKey: String
        let totalSpent: Int
        let spentByApp: [String: Int]
    }
    
    private struct DayCanvasSyncPayload: Equatable {
        let dayKey: String
        let canvasJsonData: Data // Pre-encoded DayCanvas JSON
        let lastModified: Date
        
        static func == (lhs: DayCanvasSyncPayload, rhs: DayCanvasSyncPayload) -> Bool {
            lhs.dayKey == rhs.dayKey && lhs.canvasJsonData == rhs.canvasJsonData
        }
    }
    
    private struct UserPreferencesPayload: Equatable {
        let stepsTarget: Double
        let sleepTarget: Double
        let dayEndHour: Int
        let dayEndMinute: Int
        let restDayOverride: Bool
        let preferredBody: [String]
        let preferredMind: [String]
        let preferredHeart: [String]
        let gallerySlots: [DayGallerySlot]
    }
    
    private var pendingDailySelections: DailySelectionsPayload?
    private var pendingDailyStats: DailyStatsPayload?
    private var pendingDailySpent: DailySpentPayload?
    private var pendingDayCanvas: DayCanvasSyncPayload?
    private var pendingPreferences: UserPreferencesPayload?
    
    private var lastSentDailySelections: DailySelectionsPayload?
    private var lastSentDailyStats: DailyStatsPayload?
    private var lastSentDailySpent: DailySpentPayload?
    private var lastSentDayCanvas: DayCanvasSyncPayload?
    private var lastSentPreferences: UserPreferencesPayload?
    private var pendingTicketGroupsPayload: [TicketGroupSyncRow] = []
    private var lastSentTicketGroupsPayload: [TicketGroupSyncRow] = []
    private var pendingAnalyticsEvents: [AnalyticsEventPayload] = loadAnalyticsQueueFromDefaults()
    private var analyticsDedupeKeys: Set<String> = []
    
    // Track which activities we've already counted for this user today
    private var countedActivitiesToday: Set<String> = []
    private var countedActivitiesDate: String = ""
    
    // MARK: - Offline Retry Queue
    
    private struct PendingSyncRequest: Codable {
        let urlString: String
        let method: String
        let headers: [String: String]
        let body: Data?
        let createdAt: Date
        
        var isExpired: Bool { Date().timeIntervalSince(createdAt) > 86_400 * 3 } // 3 days TTL
    }
    
    private static let retryQueueKey = "supabaseSyncRetryQueue_v1"
    private static let maxRetryQueueSize = 50
    
    private func enqueueForRetry(_ request: URLRequest) {
        guard let url = request.url?.absoluteString else { return }
        let entry = PendingSyncRequest(
            urlString: url,
            method: request.httpMethod ?? "POST",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody,
            createdAt: Date()
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
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(queue) {
            g.set(data, forKey: Self.retryQueueKey)
        }
    }
    
    /// Drain the offline retry queue. Call on app launch or when connectivity is restored.
    func drainRetryQueue() async {
        let queue = loadRetryQueue().filter { !$0.isExpired }
        guard !queue.isEmpty else { return }
        AppLogger.network.debug("📡 Draining \(queue.count) queued sync requests")
        
        var remaining: [PendingSyncRequest] = []
        for entry in queue {
            guard let url = URL(string: entry.urlString) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = entry.method
            for (k, v) in entry.headers { request.setValue(v, forHTTPHeaderField: k) }
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
    
    // MARK: - Public Sync Methods
    
    /// Sync custom activities to Supabase
    func syncCustomActivities(_ activities: [CustomEnergyOption]) {
        customActivitiesSyncTask?.cancel()
        customActivitiesSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            await self.performCustomActivitiesSync(activities)
        }
    }
    
    /// Sync daily selections for a given day
    func syncDailySelections(dayKey: String, activityIds: [String], recoveryIds: [String], joysIds: [String]) {
        let payload = DailySelectionsPayload(
            dayKey: dayKey,
            activityIds: activityIds,
            recoveryIds: recoveryIds,
            joysIds: joysIds
        )
        
        // Skip if payload already queued (coalesce to latest)
        if payload == pendingDailySelections {
            return
        }
        // If payload matches last successful send, cancel any pending work
        if payload == lastSentDailySelections {
            pendingDailySelections = nil
            dailySelectionsSyncTask?.cancel()
            return
        }
        
        pendingDailySelections = payload
        AppLogger.network.debug("📡 syncDailySelections CALLED for \(dayKey)")
        dailySelectionsSyncTask?.cancel()
        dailySelectionsSyncTask = Task {
            AppLogger.network.debug("📡 syncDailySelections Task started, waiting debounce...")
            try? await Task.sleep(nanoseconds: selectionsDebounceNs)
            if Task.isCancelled {
                AppLogger.network.debug("📡 syncDailySelections Task was CANCELLED")
                return
            }
            AppLogger.network.debug("📡 syncDailySelections Task proceeding to perform sync")
            guard let latest = pendingDailySelections else { return }
            await performDailySelectionsSync(payload: latest)
        }
    }
    
    /// Sync daily stats (steps, sleep, balance)
    func syncDailyStats(dayKey: String, steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int) {
        let payload = DailyStatsPayload(
            dayKey: dayKey,
            steps: steps,
            sleepHours: sleepHours,
            baseEnergy: baseEnergy,
            bonusEnergy: bonusEnergy,
            remainingBalance: remainingBalance
        )
        
        // Skip if payload already queued (coalesce to latest)
        if payload == pendingDailyStats {
            return
        }
        // If payload matches last successful send, cancel any pending work
        if payload == lastSentDailyStats {
            pendingDailyStats = nil
            dailyStatsSyncTask?.cancel()
            return
        }
        
        pendingDailyStats = payload
        dailyStatsSyncTask?.cancel()
        dailyStatsSyncTask = Task {
            try? await Task.sleep(nanoseconds: statsDebounceNs)
            guard !Task.isCancelled else { return }
            guard let latest = pendingDailyStats else { return }
            await performDailyStatsSync(payload: latest)
        }
    }
    
    /// Sync daily spent points
    func syncDailySpent(dayKey: String, totalSpent: Int, spentByApp: [String: Int]) {
        let payload = DailySpentPayload(
            dayKey: dayKey,
            totalSpent: totalSpent,
            spentByApp: spentByApp
        )
        
        // Skip if payload already queued (coalesce to latest)
        if payload == pendingDailySpent {
            return
        }
        // If payload matches last successful send, cancel any pending work
        if payload == lastSentDailySpent {
            pendingDailySpent = nil
            dailySpentSyncTask?.cancel()
            return
        }
        
        pendingDailySpent = payload
        dailySpentSyncTask?.cancel()
        dailySpentSyncTask = Task {
            try? await Task.sleep(nanoseconds: spentDebounceNs)
            guard !Task.isCancelled else { return }
            guard let latest = pendingDailySpent else { return }
            await performDailySpentSync(payload: latest)
        }
    }

    /// Sync full DayCanvas to Supabase `user_day_canvases` table.
    /// Stores the entire canvas JSON (elements, colors, ink) keyed by day.
    func syncDayCanvas(_ canvas: DayCanvas) {
        guard let jsonData = try? JSONEncoder().encode(canvas) else {
            AppLogger.network.error("📡 syncDayCanvas: failed to encode canvas for \(canvas.dayKey)")
            return
        }
        let payload = DayCanvasSyncPayload(
            dayKey: canvas.dayKey,
            canvasJsonData: jsonData,
            lastModified: canvas.lastModified
        )
        
        if payload == pendingDayCanvas { return }
        if payload == lastSentDayCanvas {
            pendingDayCanvas = nil
            dayCanvasSyncTask?.cancel()
            return
        }
        
        pendingDayCanvas = payload
        dayCanvasSyncTask?.cancel()
        dayCanvasSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            guard let latest = pendingDayCanvas else { return }
            await performDayCanvasSync(payload: latest)
        }
    }
    
    /// Fetch canvas from Supabase for a given day. Returns nil if not found or not authenticated.
    func fetchDayCanvas(for dayKey: String) async -> DayCanvas? {
        await AuthenticationService.shared.waitForInitialization()
        
        let token = await AuthenticationService.shared.accessToken
        let userId = await AuthenticationService.shared.currentUser?.id
        guard let token, let userId else { return nil }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_day_canvases")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(dayKey)"),
                URLQueryItem(name: "select", value: "canvas_json"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let url = comps.url else { return nil }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 fetchDayCanvas failed: HTTP \(response.statusCode)")
                return nil
            }
            
            // Response is [{ "canvas_json": { ... } }]
            let rows = try JSONDecoder().decode([DayCanvasReadRow].self, from: data)
            guard let row = rows.first else { return nil }
            
            // canvas_json is already a DayCanvas JSON object — re-encode and decode
            let canvasData = try JSONSerialization.data(withJSONObject: row.canvasJson)
            let canvas = try JSONDecoder().decode(DayCanvas.self, from: canvasData)
            AppLogger.network.debug("📡 fetchDayCanvas: restored canvas for \(dayKey) with \(canvas.elements.count) elements")
            return canvas
        } catch {
            AppLogger.network.error("📡 fetchDayCanvas error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Sync ticket groups to Supabase `shields` table.
    /// Stores each ticket group as a synthetic `bundle_id` (`group:<groupId>`) row.
    func syncTicketGroups(_ groups: [TicketGroup]) {
        let rows = groups
            .map { TicketGroupSyncRow.from(group: $0) }
            .sorted { $0.bundleId < $1.bundleId }

        if rows == pendingTicketGroupsPayload { return }
        if rows == lastSentTicketGroupsPayload {
            pendingTicketGroupsPayload = []
            ticketGroupsSyncTask?.cancel()
            return
        }

        pendingTicketGroupsPayload = rows
        ticketGroupsSyncTask?.cancel()
        ticketGroupsSyncTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            guard !Task.isCancelled else { return }
            let latest = pendingTicketGroupsPayload
            await performTicketGroupsSync(rows: latest)
        }
    }
    
    /// Sync user preferences (targets, day boundary, preferred options, gallery slots)
    func syncUserPreferences(
        stepsTarget: Double,
        sleepTarget: Double,
        dayEndHour: Int,
        dayEndMinute: Int,
        restDayOverride: Bool,
        preferredBody: [String],
        preferredMind: [String],
        preferredHeart: [String],
        gallerySlots: [DayGallerySlot]
    ) {
        let payload = UserPreferencesPayload(
            stepsTarget: stepsTarget,
            sleepTarget: sleepTarget,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute,
            restDayOverride: restDayOverride,
            preferredBody: preferredBody,
            preferredMind: preferredMind,
            preferredHeart: preferredHeart,
            gallerySlots: gallerySlots
        )
        
        if payload == pendingPreferences { return }
        if payload == lastSentPreferences {
            pendingPreferences = nil
            preferencesSyncTask?.cancel()
            return
        }
        
        pendingPreferences = payload
        preferencesSyncTask?.cancel()
        preferencesSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            guard let latest = pendingPreferences else { return }
            await performPreferencesSync(payload: latest)
        }
    }
    
    /// Sync a day-end snapshot to Supabase (called when the day resets)
    func syncDaySnapshot(dayKey: String, snapshot: PastDaySnapshot) {
        daySnapshotSyncTask?.cancel()
        daySnapshotSyncTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec debounce
            guard !Task.isCancelled else { return }
            await performDaySnapshotSync(dayKey: dayKey, snapshot: snapshot)
        }
    }
    
    /// Track activity selection in global stats
    /// Only increments count once per user per day per activity
    func trackActivitySelection(activityId: String, category: EnergyCategory, titleEn: String, titleRu: String, icon: String, isCustom: Bool) {
        let today = AppModel.dayKey(for: Date())
        
        // Reset tracking if day changed
        if countedActivitiesDate != today {
            countedActivitiesToday = []
            countedActivitiesDate = today
        }
        
        // Skip if already counted today
        guard !countedActivitiesToday.contains(activityId) else { return }
        countedActivitiesToday.insert(activityId)
        
        activityStatsSyncTask?.cancel()
        activityStatsSyncTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 sec debounce
            guard !Task.isCancelled else { return }
            await self.performActivityStatsIncrement(
                activityId: activityId,
                category: category.rawValue,
                titleEn: titleEn,
                titleRu: titleRu,
                icon: icon,
                isCustom: isCustom
            )
        }
    }
    
    /// Track multiple activities at once (for batch updates)
    func trackActivitySelections(_ selections: [(id: String, category: EnergyCategory, titleEn: String, titleRu: String, icon: String, isCustom: Bool)]) {
        for selection in selections {
            trackActivitySelection(
                activityId: selection.id,
                category: selection.category,
                titleEn: selection.titleEn,
                titleRu: selection.titleRu,
                icon: selection.icon,
                isCustom: selection.isCustom
            )
        }
    }
    
    /// Queue analytics event for KPI tracking.
    /// Uses best-effort delivery to `user_analytics_events` with local queue fallback.
    func trackAnalyticsEvent(name: String, properties: [String: String] = [:], dedupeKey: String? = nil) {
        if let dedupeKey {
            if analyticsDedupeKeys.contains(dedupeKey) { return }
            analyticsDedupeKeys.insert(dedupeKey)
        }
        
        let payload = AnalyticsEventPayload(
            id: UUID().uuidString,
            eventName: name,
            dayKey: AppModel.dayKey(for: Date()),
            properties: properties,
            occurredAt: Date()
        )
        
        pendingAnalyticsEvents.append(payload)
        if pendingAnalyticsEvents.count > 250 {
            pendingAnalyticsEvents = Array(pendingAnalyticsEvents.suffix(250))
        }
        persistAnalyticsQueueToDefaults()
        scheduleAnalyticsFlush()
    }
    
    /// Full sync - call on app launch or after login
    func performFullSync(model: AppModel) async {
        AppLogger.network.debug("📡 performFullSync called, waiting for auth initialization...")
        
        // Wait for AuthenticationService to finish restoring session
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
                dailyActivitySelections: model.dailyActivitySelections,
                dailyRestSelections: model.dailyRestSelections,
                dailyJoysSelections: model.dailyJoysSelections,
                stepsToday: model.healthStore.stepsToday,
                dailySleepHours: model.healthStore.dailySleepHours,
                baseEnergyToday: model.healthStore.baseEnergyToday,
                bonusSteps: model.userEconomyStore.bonusSteps,
                totalStepsBalance: model.userEconomyStore.totalStepsBalance,
                appStepsSpentByDay: model.userEconomyStore.appStepsSpentByDay,
                // Preferences
                stepsTarget: g.object(forKey: SharedKeys.userStepsTarget) as? Double ?? EnergyDefaults.stepsTarget,
                sleepTarget: g.object(forKey: SharedKeys.userSleepTarget) as? Double ?? EnergyDefaults.sleepTargetHours,
                dayEndHour: model.dayEndHour,
                dayEndMinute: model.dayEndMinute,
                restDayOverride: model.isRestDayOverrideEnabled,
                preferredBody: model.preferredActivityOptions,
                preferredMind: model.preferredRestOptions,
                preferredHeart: model.preferredJoysOptions,
                gallerySlots: model.dailyGallerySlots,
                ticketGroups: model.ticketGroups
            )
        }
        
        // Sync custom activities
        await performCustomActivitiesSync(snapshot.customEnergyOptions)
        
        // Sync today's data
        let today = AppModel.dayKey(for: Date())
        
        await performDailySelectionsSync(
            payload: DailySelectionsPayload(
                dayKey: today,
                activityIds: snapshot.dailyActivitySelections,
                recoveryIds: snapshot.dailyRestSelections,
                joysIds: snapshot.dailyJoysSelections
            )
        )
        
        await performDailyStatsSync(
            payload: DailyStatsPayload(
                dayKey: today,
                steps: Int(snapshot.stepsToday),
                sleepHours: snapshot.dailySleepHours,
                baseEnergy: snapshot.baseEnergyToday,
                bonusEnergy: snapshot.bonusSteps,
                remainingBalance: snapshot.totalStepsBalance
            )
        )
        
        let todaySpent = snapshot.appStepsSpentByDay[today] ?? [:]
        let totalSpent = todaySpent.values.reduce(0, +)
        await performDailySpentSync(
            payload: DailySpentPayload(
                dayKey: today,
                totalSpent: totalSpent,
                spentByApp: todaySpent
            )
        )
        
        // Sync user preferences
        await performPreferencesSync(
            payload: UserPreferencesPayload(
                stepsTarget: snapshot.stepsTarget,
                sleepTarget: snapshot.sleepTarget,
                dayEndHour: snapshot.dayEndHour,
                dayEndMinute: snapshot.dayEndMinute,
                restDayOverride: snapshot.restDayOverride,
                preferredBody: snapshot.preferredBody,
                preferredMind: snapshot.preferredMind,
                preferredHeart: snapshot.preferredHeart,
                gallerySlots: snapshot.gallerySlots
            )
        )
        
        // Sync ticket groups (full settings)
        let ticketRows = snapshot.ticketGroups
            .map { TicketGroupSyncRow.from(group: $0) }
            .sorted { $0.bundleId < $1.bundleId }
        await performTicketGroupsSync(rows: ticketRows)
        
        AppLogger.network.debug("📡 Full sync completed")
    }

    /// Delete a single ticket/shield row for current user and bundle id.
    func deleteTicket(bundleId: String) async {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Ticket delete skipped: no auth")
            return
        }

        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/shields")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Ticket delete failed: invalid endpoint")
                return
            }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "bundle_id", value: "eq.\(bundleId)")
            ]

            guard let url = comps.url else {
                AppLogger.network.error("📡 Ticket delete failed: invalid URL components")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("return=minimal", forHTTPHeaderField: "prefer")

            let (data, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Ticket deleted for bundleId=\(bundleId)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket delete failed for bundleId=\(bundleId): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Ticket delete error for bundleId=\(bundleId): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Sync Implementations
    
    private func performCustomActivitiesSync(_ activities: [CustomEnergyOption]) async {
        await AuthenticationService.shared.waitForInitialization()
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Custom activities sync skipped: no auth")
            return
        }
        
        // Check if data changed
        let hash = activities.hashValue
        guard hash != lastSyncedCustomActivitiesHash else {
            AppLogger.network.debug("📡 Custom activities unchanged, skipping sync")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            
            // If empty, just delete all for this user (no destructive delete-before-insert)
            if activities.isEmpty {
                let deleteURL = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
                guard var deleteComps = URLComponents(url: deleteURL, resolvingAgainstBaseURL: false) else { return }
                deleteComps.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
                
                guard let url = deleteComps.url else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                
                let (_, response) = try await network.data(for: request)
                if response.statusCode < 400 {
                    lastSyncedCustomActivitiesHash = hash
                    AppLogger.network.debug("📡 Custom activities cleared on server")
                } else {
                    AppLogger.network.error("📡 Custom activities clear failed")
                }
                return
            }
            
            // Upsert current activities
            let insertURL = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
            guard var insertComps = URLComponents(url: insertURL, resolvingAgainstBaseURL: false) else { return }
            insertComps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
            
            guard let finalInsertURL = insertComps.url else { return }
            var request = URLRequest(url: finalInsertURL)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "prefer")
            
            let rows = activities.map { activity in
                CustomActivityRow(
                    id: activity.id,
                    userId: userId,
                    titleEn: activity.titleEn,
                    titleRu: activity.titleRu,
                    category: activity.category.rawValue,
                    icon: activity.icon
                )
            }
            
            request.httpBody = try JSONEncoder().encode(rows)
            
            let (_, response) = try await network.data(for: request)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 Custom activities upsert failed")
                return
            }
            
            // Delete server records not present in current payload (safe after successful upsert)
            let deleteURL = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
            guard var deleteComps = URLComponents(url: deleteURL, resolvingAgainstBaseURL: false) else { return }
            let idList = activities.map { $0.id }.joined(separator: ",")
            deleteComps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "id", value: "not.in.(\(idList))")
            ]
            
            guard let deleteFinalURL = deleteComps.url else { return }
            var deleteRequest = URLRequest(url: deleteFinalURL)
            deleteRequest.httpMethod = "DELETE"
            deleteRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            
            let (_, deleteResponse) = try await network.data(for: deleteRequest)
            if deleteResponse.statusCode < 400 {
                lastSyncedCustomActivitiesHash = hash
                AppLogger.network.debug("📡 Custom activities synced: \(activities.count) items")
            } else {
                AppLogger.network.error("📡 Custom activities delete-missing failed")
            }
        } catch {
            AppLogger.network.error("📡 Custom activities sync error: \(error.localizedDescription)")
        }
    }

    private func performTicketGroupsSync(rows: [TicketGroupSyncRow]) async {
        defer {
            if pendingTicketGroupsPayload == rows {
                pendingTicketGroupsPayload = []
            }
        }

        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Ticket groups sync skipped: no auth")
            return
        }

        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/shields")

            // Step 1: delete existing synthetic ticket-group rows for current user.
            guard var deleteComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            deleteComps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "bundle_id", value: "like.group:%")
            ]
            guard let deleteURL = deleteComps.url else { return }

            var deleteRequest = URLRequest(url: deleteURL)
            deleteRequest.httpMethod = "DELETE"
            deleteRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            deleteRequest.setValue("return=minimal", forHTTPHeaderField: "prefer")

            let (deleteData, deleteResponse) = try await network.data(for: deleteRequest)
            guard deleteResponse.statusCode < 400 else {
                let body = String(data: deleteData, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket groups delete-before-insert failed: HTTP \(deleteResponse.statusCode) - \(body)")
                return
            }

            // Step 2: insert current rows.
            if rows.isEmpty {
                lastSentTicketGroupsPayload = []
                AppLogger.network.debug("📡 Ticket groups synced: cleared")
                return
            }

            let payload = rows.map { row -> TicketGroupSyncInsertRow in
                let settingsDict: [String: AnyCodableValue]?
                if let obj = try? JSONSerialization.jsonObject(with: row.settingsJson) as? [String: Any] {
                    var dict: [String: AnyCodableValue] = [:]
                    for (k, v) in obj {
                        if let i = v as? Int { dict[k] = .int(i) }
                        else if let b = v as? Bool { dict[k] = .bool(b) }
                        else if let s = v as? String { dict[k] = .string(s) }
                        else if let a = v as? [String] { dict[k] = .array(a) }
                    }
                    settingsDict = dict
                } else {
                    settingsDict = nil
                }
                return TicketGroupSyncInsertRow(
                    userId: userId,
                    bundleId: row.bundleId,
                    mode: row.mode,
                    name: row.name,
                    templateApp: row.templateApp,
                    stickerThemeIndex: row.stickerThemeIndex,
                    enabledIntervals: row.enabledIntervals,
                    settingsJson: settingsDict
                )
            }

            var insertRequest = URLRequest(url: endpoint)
            insertRequest.httpMethod = "POST"
            insertRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            insertRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            insertRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            insertRequest.setValue("return=minimal", forHTTPHeaderField: "prefer")
            insertRequest.httpBody = try JSONEncoder().encode(payload)

            let (insertData, insertResponse) = try await network.data(for: insertRequest)
            if insertResponse.statusCode < 400 {
                lastSentTicketGroupsPayload = rows
                AppLogger.network.debug("📡 Ticket groups synced: \(rows.count) rows")
            } else {
                let body = String(data: insertData, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket groups insert failed: HTTP \(insertResponse.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Ticket groups sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailySelectionsSync(payload: DailySelectionsPayload) async {
        if payload == lastSentDailySelections { return }
        let dayKey = payload.dayKey
        let activityIds = payload.activityIds
        let recoveryIds = payload.recoveryIds
        let joysIds = payload.joysIds
        
        defer {
            if pendingDailySelections == payload {
                pendingDailySelections = nil
            }
        }
        
        AppLogger.network.debug("📡 performDailySelectionsSync called for \(dayKey)")
        AppLogger.network.debug("📡   activities: \(activityIds), recovery: \(recoveryIds), joys: \(joysIds)")
        
        // Wait for auth to be ready
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        let token = await AuthenticationService.shared.accessToken
        let userId = await AuthenticationService.shared.currentUser?.id
        guard let token, let userId else {
            let hasToken = token != nil
            AppLogger.network.debug("📡 Daily selections sync skipped: no auth (token=\(hasToken), user=\(userId ?? "nil"))")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_selections")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Error: Failed to create URLComponents for daily selections")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                AppLogger.network.error("📡 Error: Failed to get URL from components for daily selections")
                return
            }
            AppLogger.network.debug("📡 POST URL: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let row = DailySelectionsRow(
                userId: userId,
                dayKey: dayKey,
                activityIds: activityIds,
                restIds: recoveryIds,
                joysIds: joysIds
            )
            
            let bodyData = try JSONEncoder().encode(row)
            request.httpBody = bodyData
            AppLogger.network.debug("📡 POST body: \(String(data: bodyData, encoding: .utf8) ?? "nil")")
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentDailySelections = payload
                AppLogger.network.debug("📡 Daily selections synced for \(dayKey)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Daily selections sync failed for \(dayKey): HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Daily selections sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailyStatsSync(payload: DailyStatsPayload) async {
        if payload == lastSentDailyStats { return }
        let dayKey = payload.dayKey
        let steps = payload.steps
        let sleepHours = payload.sleepHours
        let baseEnergy = payload.baseEnergy
        let bonusEnergy = payload.bonusEnergy
        let remainingBalance = payload.remainingBalance
        
        defer {
            if pendingDailyStats == payload {
                pendingDailyStats = nil
            }
        }
        
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Daily stats sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_stats")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Error: Failed to create URLComponents for daily stats")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                AppLogger.network.error("📡 Error: Failed to get URL from components for daily stats")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let row = DailyStatsRow(
                userId: userId,
                dayKey: dayKey,
                stepsCount: steps,
                sleepHours: sleepHours,
                baseEnergy: baseEnergy,
                bonusEnergy: bonusEnergy,
                remainingBalance: remainingBalance
            )
            
            request.httpBody = try JSONEncoder().encode(row)
            
            let (_, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentDailyStats = payload
                AppLogger.network.debug("📡 Daily stats synced for \(dayKey): steps=\(steps), sleep=\(sleepHours)h, balance=\(remainingBalance)")
            } else {
                AppLogger.network.error("📡 Daily stats sync failed for \(dayKey)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Daily stats sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailySpentSync(payload: DailySpentPayload) async {
        if payload == lastSentDailySpent { return }
        let dayKey = payload.dayKey
        let totalSpent = payload.totalSpent
        let spentByApp = payload.spentByApp
        
        defer {
            if pendingDailySpent == payload {
                pendingDailySpent = nil
            }
        }
        
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Daily spent sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_spent")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Error: Failed to create URLComponents for daily spent")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                AppLogger.network.error("📡 Error: Failed to get URL from components for daily spent")
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let row = DailySpentRow(
                userId: userId,
                dayKey: dayKey,
                totalSpent: totalSpent,
                spentByApp: spentByApp
            )
            
            request.httpBody = try JSONEncoder().encode(row)
            
            let (_, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentDailySpent = payload
                AppLogger.network.debug("📡 Daily spent synced for \(dayKey): total=\(totalSpent)")
            } else {
                AppLogger.network.error("📡 Daily spent sync failed for \(dayKey)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Daily spent sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDayCanvasSync(payload: DayCanvasSyncPayload) async {
        if payload == lastSentDayCanvas { return }
        
        defer {
            if pendingDayCanvas == payload {
                pendingDayCanvas = nil
            }
        }
        
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Day canvas sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_day_canvases")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Error: Failed to create URLComponents for day canvas")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            guard let url = urlComps.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            // Build the row: canvas_json is the raw JSON object (not a string)
            let canvasJsonObject = try JSONSerialization.jsonObject(with: payload.canvasJsonData)
            let row: [String: Any] = [
                "user_id": userId,
                "day_key": payload.dayKey,
                "canvas_json": canvasJsonObject,
                "last_modified": CachedFormatters.iso8601.string(from: payload.lastModified)
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: row)
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentDayCanvas = payload
                AppLogger.network.debug("📡 Day canvas synced for \(payload.dayKey)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Day canvas sync failed for \(payload.dayKey): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Day canvas sync error: \(error.localizedDescription)")
        }
    }
    
    private func performPreferencesSync(payload: UserPreferencesPayload) async {
        if payload == lastSentPreferences { return }
        
        defer {
            if pendingPreferences == payload {
                pendingPreferences = nil
            }
        }
        
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Preferences sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_preferences")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id")]
            guard let url = urlComps.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let slotsData = (try? JSONEncoder().encode(payload.gallerySlots)) ?? Data("[]".utf8)
            let slotsJson = try JSONSerialization.jsonObject(with: slotsData)
            
            let row: [String: Any] = [
                "user_id": userId,
                "steps_target": payload.stepsTarget,
                "sleep_target": payload.sleepTarget,
                "day_end_hour": payload.dayEndHour,
                "day_end_minute": payload.dayEndMinute,
                "rest_day_override": payload.restDayOverride,
                "preferred_body": payload.preferredBody,
                "preferred_mind": payload.preferredMind,
                "preferred_heart": payload.preferredHeart,
                "gallery_slots": slotsJson,
                "updated_at": iso8601String(Date())
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: row)
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentPreferences = payload
                AppLogger.network.debug("📡 User preferences synced")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Preferences sync failed: HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Preferences sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDaySnapshotSync(dayKey: String, snapshot: PastDaySnapshot) async {
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Day snapshot sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_day_snapshots")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            guard let url = urlComps.url else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            
            let row = DaySnapshotRow(
                userId: userId,
                dayKey: dayKey,
                inkEarned: snapshot.inkEarned,
                inkSpent: snapshot.inkSpent,
                bodyIds: snapshot.bodyIds,
                mindIds: snapshot.mindIds,
                heartIds: snapshot.heartIds,
                steps: snapshot.steps,
                sleepHours: snapshot.sleepHours,
                stepsTarget: snapshot.stepsTarget,
                sleepTargetHours: snapshot.sleepTargetHours
            )
            
            request.httpBody = try JSONEncoder().encode(row)
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Day snapshot synced for \(dayKey)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Day snapshot sync failed for \(dayKey): HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Day snapshot sync error: \(error.localizedDescription)")
        }
    }
    
    private func performActivityStatsIncrement(activityId: String, category: String, titleEn: String, titleRu: String, icon: String, isCustom: Bool) async {
        AppLogger.network.debug("📡 performActivityStatsIncrement called for \(activityId)")
        
        await AuthenticationService.shared.waitForInitialization()
        
        guard let token = await AuthenticationService.shared.accessToken else {
            AppLogger.network.debug("📡 Activity stats sync skipped: no auth token")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            
            // Use RPC to upsert and increment atomically
            let url = cfg.baseURL.appendingPathComponent("rest/v1/rpc/increment_activity_stat")
            AppLogger.network.debug("📡 Calling RPC: \(url.absoluteString)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            
            let params = ActivityStatRpcParams(
                pActivityId: activityId,
                pCategory: category,
                pTitleEn: titleEn,
                pTitleRu: titleRu,
                pIcon: icon,
                pIsCustom: isCustom
            )
            
            request.httpBody = try JSONEncoder().encode(params)
            
            let (data, response) = try await network.data(for: request, policy: NetworkClient.RetryPolicy.none)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Activity stat incremented: \(activityId)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Activity stat increment failed for \(activityId): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Activity stat sync error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Analytics Events
    
    private func scheduleAnalyticsFlush() {
        analyticsFlushTask?.cancel()
        analyticsFlushTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled else { return }
            await flushAnalyticsEvents()
        }
    }
    
    private func flushAnalyticsEvents() async {
        guard !pendingAnalyticsEvents.isEmpty else { return }
        
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_analytics_events")
            let rows = pendingAnalyticsEvents.map {
                AnalyticsEventInsertRow(
                    userId: userId,
                    eventName: $0.eventName,
                    dayKey: $0.dayKey,
                    properties: $0.properties,
                    eventId: $0.id,
                    occurredAt: iso8601String($0.occurredAt)
                )
            }
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("return=minimal,resolution=ignore-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONEncoder().encode(rows)
            
            let (_, response) = try await network.data(for: request, policy: NetworkClient.RetryPolicy.none)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 Analytics flush failed: HTTP \(response.statusCode)")
                return
            }
            
            pendingAnalyticsEvents.removeAll()
            persistAnalyticsQueueToDefaults()
            AppLogger.network.debug("📡 Analytics flushed: \(rows.count) events")
        } catch {
            AppLogger.network.error("📡 Analytics flush error: \(error.localizedDescription)")
        }
    }
    
    private func persistAnalyticsQueueToDefaults() {
        let g = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(pendingAnalyticsEvents) {
            g.set(data, forKey: SharedKeys.analyticsEventsQueue)
        }
    }
    
    private func iso8601String(_ date: Date) -> String {
        CachedFormatters.iso8601.string(from: date)
    }
    
    // MARK: - Restore from Supabase
    
    /// Load custom activities from Supabase (for restoring on new device)
    func loadCustomActivitiesFromServer() async -> [CustomEnergyOption]? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "*")
            ]
            
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([CustomActivityRow].self, from: data)
            
            AppLogger.network.debug("📡 Loaded \(rows.count) custom activities from server")
            
            return rows.compactMap { row -> CustomEnergyOption? in
                guard let category = EnergyCategory(rawValue: row.category) else { return nil }
                return CustomEnergyOption(
                    id: row.id,
                    titleEn: row.titleEn,
                    titleRu: row.titleRu ?? row.titleEn,
                    category: category,
                    icon: row.icon ?? "pencil"
                )
            }
        } catch {
            AppLogger.network.error("📡 Failed to load custom activities: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load today's daily selections from Supabase
    func loadTodaySelectionsFromServer() async -> (activity: [String], rest: [String], joys: [String])? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        if let cached = cachedTodaySelections,
           cached.dayKey == today,
           Date().timeIntervalSince(cached.timestamp) < todayCacheTTL {
            return cached.value
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_selections")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(today)"),
                URLQueryItem(name: "select", value: "*")
            ]
            
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            AppLogger.network.debug("📡 Raw selections response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySelectionsRow].self, from: data)
            
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No selections found for today on server (empty array)")
                return nil
            }
            
            AppLogger.network.debug("📡 Loaded today's selections from server: activity=\(row.activityIds), rest=\(row.restIds), joys=\(row.joysIds)")
            
            let value = (row.activityIds, row.restIds, row.joysIds)
            cachedTodaySelections = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            AppLogger.network.error("📡 Failed to load today's selections: \(error)")
            return nil
        }
    }
    
    /// Load today's daily stats from Supabase
    func loadTodayStatsFromServer() async -> (steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int)? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        if let cached = cachedTodayStats,
           cached.dayKey == today,
           Date().timeIntervalSince(cached.timestamp) < todayCacheTTL {
            return cached.value
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_stats")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(today)"),
                URLQueryItem(name: "select", value: "*")
            ]
            
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailyStatsRow].self, from: data)
            
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No stats found for today on server")
                return nil
            }
            
            AppLogger.network.debug("📡 Loaded today's stats from server: steps=\(row.stepsCount), balance=\(row.remainingBalance)")
            
            let value = (row.stepsCount, row.sleepHours, row.baseEnergy, row.bonusEnergy, row.remainingBalance)
            cachedTodayStats = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            AppLogger.network.error("📡 Failed to load today's stats: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load today's spent points from Supabase
    func loadTodaySpentFromServer() async -> (totalSpent: Int, spentByApp: [String: Int])? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        if let cached = cachedTodaySpent,
           cached.dayKey == today,
           Date().timeIntervalSince(cached.timestamp) < todayCacheTTL {
            return cached.value
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_spent")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(today)"),
                URLQueryItem(name: "select", value: "*")
            ]
            
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            AppLogger.network.debug("📡 Raw spent response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySpentRow].self, from: data)
            
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No spent data found for today on server (empty array)")
                return nil
            }
            
            AppLogger.network.debug("📡 Loaded today's spent from server: total=\(row.totalSpent), byApp=\(row.spentByApp)")
            
            let value = (row.totalSpent, row.spentByApp)
            cachedTodaySpent = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            AppLogger.network.error("📡 Failed to load today's spent: \(error)")
            return nil
        }
    }
    
    /// Load user preferences from Supabase
    func loadUserPreferencesFromServer() async -> (
        stepsTarget: Double, sleepTarget: Double,
        dayEndHour: Int, dayEndMinute: Int,
        restDayOverride: Bool,
        preferredBody: [String], preferredMind: [String], preferredHeart: [String],
        gallerySlots: [DayGallerySlot]
    )? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return nil
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_preferences")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let finalURL = comps.url else { return nil }
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else { return nil }
            
            let rows = try JSONDecoder().decode([UserPreferencesRow].self, from: data)
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No preferences found on server")
                return nil
            }
            
            // Decode gallery slots from raw JSONB
            var gallerySlots: [DayGallerySlot] = []
            if let rawSlots = row.gallerySlots?.value {
                let slotsData = try JSONSerialization.data(withJSONObject: rawSlots)
                gallerySlots = (try? JSONDecoder().decode([DayGallerySlot].self, from: slotsData)) ?? []
            }
            
            AppLogger.network.debug("📡 Loaded user preferences from server")
            return (
                stepsTarget: row.stepsTarget,
                sleepTarget: row.sleepTarget,
                dayEndHour: row.dayEndHour,
                dayEndMinute: row.dayEndMinute,
                restDayOverride: row.restDayOverride,
                preferredBody: row.preferredBody,
                preferredMind: row.preferredMind,
                preferredHeart: row.preferredHeart,
                gallerySlots: gallerySlots
            )
        } catch {
            AppLogger.network.error("📡 Failed to load preferences: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load day snapshots from Supabase (for restoring history on new device)
    func loadDaySnapshotsFromServer() async -> [String: PastDaySnapshot] {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            return [:]
        }
        
        guard let config = try? SupabaseConfig.load() else { return [:] }
        
        let endpoint = config.baseURL.appendingPathComponent("rest/v1/user_day_snapshots")
        let baseQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "day_key.desc")
        ]
        
        do {
            let rows: [DaySnapshotRow] = try await fetchPagedRows(
                endpoint: endpoint,
                token: token,
                anonKey: config.anonKey,
                baseQuery: baseQuery,
                pageSize: historicalPageSize
            )
            
            var result: [String: PastDaySnapshot] = [:]
            for row in rows {
                result[row.dayKey] = PastDaySnapshot(
                    inkEarned: row.inkEarned,
                    inkSpent: row.inkSpent,
                    bodyIds: row.bodyIds,
                    mindIds: row.mindIds,
                    heartIds: row.heartIds,
                    steps: row.steps,
                    sleepHours: row.sleepHours,
                    stepsTarget: row.stepsTarget,
                    sleepTargetHours: row.sleepTargetHours
                )
            }
            
            AppLogger.network.debug("📡 Loaded \(result.count) day snapshots from server")
            return result
        } catch {
            AppLogger.network.error("📡 Failed to load day snapshots: \(error.localizedDescription)")
            return [:]
        }
    }
    
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
        
        // 1. Restore custom activities
        if let customActivities = await loadCustomActivitiesFromServer(), !customActivities.isEmpty {
            await MainActor.run {
                model.customEnergyOptions = customActivities
            }
            didRestore = true
        }
        
        // 2. Restore today's selections
        if let selections = await loadTodaySelectionsFromServer() {
            let hasData = !selections.activity.isEmpty || !selections.rest.isEmpty || !selections.joys.isEmpty
            if hasData {
                await MainActor.run {
                    model.dailyActivitySelections = selections.activity
                    model.dailyRestSelections = selections.rest
                    model.dailyJoysSelections = selections.joys
                    // Persist locally so it doesn't get overwritten
                    model.persistDailyEnergyState()
                }
                didRestore = true
            }
        }
        
        // 3. Restore today's spent
        if let spent = await loadTodaySpentFromServer() {
            if spent.totalSpent > 0 {
                await MainActor.run {
                    model.spentStepsToday = spent.totalSpent
                    let today = AppModel.dayKey(for: Date())
                    model.appStepsSpentByDay[today] = spent.spentByApp
                    // Persist locally
                    model.persistAppStepsSpentToday()
                }
                didRestore = true
            }
        }
        
        // 4. Restore preferences (targets, day boundary, preferred options, gallery slots)
        if let prefs = await loadUserPreferencesFromServer() {
            await MainActor.run {
                let g = UserDefaults.stepsTrader()
                g.set(prefs.stepsTarget, forKey: SharedKeys.userStepsTarget)
                g.set(prefs.sleepTarget, forKey: SharedKeys.userSleepTarget)
                g.set(prefs.dayEndHour, forKey: SharedKeys.dayEndHour)
                g.set(prefs.dayEndMinute, forKey: SharedKeys.dayEndMinute)
                g.set(prefs.restDayOverride, forKey: SharedKeys.restDayOverrideEnabled)
                model.dayEndHour = prefs.dayEndHour
                model.dayEndMinute = prefs.dayEndMinute
                model.preferredActivityOptions = prefs.preferredBody
                model.preferredRestOptions = prefs.preferredMind
                model.preferredJoysOptions = prefs.preferredHeart
                if !prefs.gallerySlots.isEmpty {
                    model.dailyGallerySlots = prefs.gallerySlots
                }
                model.persistDailyEnergyState()
            }
            didRestore = true
            AppLogger.network.debug("📡 Restored user preferences from server")
        }
        
        // 5. Restore day snapshots (merge with local, server wins on conflict)
        let serverSnapshots = await loadDaySnapshotsFromServer()
        if !serverSnapshots.isEmpty {
            await MainActor.run {
                var local = model.loadPastDaySnapshots()
                for (dayKey, serverSnapshot) in serverSnapshots {
                    // Server wins on conflict (more likely to be complete)
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
    
    // MARK: - Load Historical Snapshots
    
    /// Load all historical day snapshots from Supabase
    /// Combines data from user_daily_selections, user_daily_stats, and user_daily_spent
    func loadHistoricalSnapshots() async -> [String: PastDaySnapshot] {
        await AuthenticationService.shared.waitForInitialization()
        let isAuthenticated = await AuthenticationService.shared.isAuthenticated
        let userId = await AuthenticationService.shared.currentUser?.id
        let token = await AuthenticationService.shared.accessToken
        guard isAuthenticated,
              let userId,
              let token else {
            AppLogger.network.debug("📡 Historical load skipped: no auth")
            return [:]
        }
        
        guard let config = try? SupabaseConfig.load() else {
            return [:]
        }
        
        var snapshots: [String: PastDaySnapshot] = [:]
        
        let g = UserDefaults.stepsTrader()
        let now = Date()
        let lastFullSync = g.object(forKey: historicalLastFullSyncKey) as? Date ?? .distantPast
        let shouldFullSync = now.timeIntervalSince(lastFullSync) >= historicalRefreshTTL
        let lastDayKey = g.string(forKey: historicalLastDayKeyKey)
        
        let selections: [String: DailySelectionsRow]
        let stats: [String: DailyStatsRow]
        let spent: [String: DailySpentRow]
        
        if shouldFullSync || lastDayKey == nil {
            selections = await loadAllSelections(config: config, userId: userId, token: token)
            stats = await loadAllStats(config: config, userId: userId, token: token)
            spent = await loadAllSpent(config: config, userId: userId, token: token)
            g.set(now, forKey: historicalLastFullSyncKey)
        } else {
            selections = await loadAllSelections(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
            stats = await loadAllStats(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
            spent = await loadAllSpent(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
        }
        
        // Combine all day keys
        var allDayKeys = Set<String>()
        allDayKeys.formUnion(selections.keys)
        allDayKeys.formUnion(stats.keys)
        allDayKeys.formUnion(spent.keys)
        
        // Build snapshots for each day
        for dayKey in allDayKeys {
            let sel = selections[dayKey]
            let stat = stats[dayKey]
            let sp = spent[dayKey]
            
            let snapshot = PastDaySnapshot(
                inkEarned: stat?.baseEnergy ?? 0,
                inkSpent: sp?.totalSpent ?? 0,
                bodyIds: sel?.activityIds ?? [],
                mindIds: sel?.restIds ?? [],
                heartIds: sel?.joysIds ?? [],
                steps: stat?.stepsCount ?? 0,
                sleepHours: stat?.sleepHours ?? 0
            )
            
            snapshots[dayKey] = snapshot
        }
        
        AppLogger.network.debug("📡 Loaded \(snapshots.count) historical snapshots from Supabase")
        
        if let maxDayKey = allDayKeys.max() {
            g.set(maxDayKey, forKey: historicalLastDayKeyKey)
        }
        return snapshots
    }
    
    private func loadAllSelections(config: SupabaseConfig, userId: String, token: String, fromDayKey: String? = nil) async -> [String: DailySelectionsRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_selections")
        var baseQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "day_key.asc")
        ]
        if let fromDayKey {
            baseQuery.append(URLQueryItem(name: "day_key", value: "gt.\(fromDayKey)"))
        }
        
        do {
            let rows: [DailySelectionsRow] = try await fetchPagedRows(
                endpoint: endpoint,
                token: token,
                anonKey: config.anonKey,
                baseQuery: baseQuery,
                pageSize: historicalPageSize
            )
            
            var result: [String: DailySelectionsRow] = [:]
            for row in rows {
                result[row.dayKey] = row
            }
            return result
        } catch {
            AppLogger.network.error("📡 Failed to load all selections: \(error)")
            return [:]
        }
    }
    
    private func loadAllStats(config: SupabaseConfig, userId: String, token: String, fromDayKey: String? = nil) async -> [String: DailyStatsRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_stats")
        var baseQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "day_key.asc")
        ]
        if let fromDayKey {
            baseQuery.append(URLQueryItem(name: "day_key", value: "gt.\(fromDayKey)"))
        }
        
        do {
            let rows: [DailyStatsRow] = try await fetchPagedRows(
                endpoint: endpoint,
                token: token,
                anonKey: config.anonKey,
                baseQuery: baseQuery,
                pageSize: historicalPageSize
            )
            
            var result: [String: DailyStatsRow] = [:]
            for row in rows {
                result[row.dayKey] = row
            }
            return result
        } catch {
            AppLogger.network.error("📡 Failed to load all stats: \(error)")
            return [:]
        }
    }
    
    private func loadAllSpent(config: SupabaseConfig, userId: String, token: String, fromDayKey: String? = nil) async -> [String: DailySpentRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_spent")
        var baseQuery = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "day_key.asc")
        ]
        if let fromDayKey {
            baseQuery.append(URLQueryItem(name: "day_key", value: "gt.\(fromDayKey)"))
        }
        
        do {
            let rows: [DailySpentRow] = try await fetchPagedRows(
                endpoint: endpoint,
                token: token,
                anonKey: config.anonKey,
                baseQuery: baseQuery,
                pageSize: historicalPageSize
            )
            
            var result: [String: DailySpentRow] = [:]
            for row in rows {
                result[row.dayKey] = row
            }
            return result
        } catch {
            AppLogger.network.error("📡 Failed to load all spent: \(error)")
            return [:]
        }
    }

    private func fetchPagedRows<T: Decodable>(
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
}

// SupabaseConfig is now defined in NetworkClient.swift

private enum SyncError: Error {
    case misconfigured
    case networkError
}

// MARK: - DTOs for Supabase

private struct CustomActivityRow: Codable {
    let id: String
    let userId: String
    let titleEn: String
    let titleRu: String?
    let category: String
    let icon: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case titleEn = "title_en"
        case titleRu = "title_ru"
        case category
        case icon
    }
}

private struct DailySelectionsRow: Codable {
    let userId: String
    let dayKey: String
    let activityIds: [String]
    let restIds: [String]
    let joysIds: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case activityIds = "activity_ids"
        case restIds = "recovery_ids"
        case joysIds = "joys_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        activityIds = try container.decodeIfPresent([String].self, forKey: .activityIds) ?? []
        restIds = try container.decodeIfPresent([String].self, forKey: .restIds) ?? []
        joysIds = try container.decodeIfPresent([String].self, forKey: .joysIds) ?? []
    }

    init(userId: String, dayKey: String, activityIds: [String], restIds: [String], joysIds: [String]) {
        self.userId = userId
        self.dayKey = dayKey
        self.activityIds = activityIds
        self.restIds = restIds
        self.joysIds = joysIds
    }
}

private struct DailyStatsRow: Codable {
    let userId: String
    let dayKey: String
    let stepsCount: Int
    let sleepHours: Double
    let baseEnergy: Int
    let bonusEnergy: Int
    let remainingBalance: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case stepsCount = "steps_count"
        case sleepHours = "sleep_hours"
        case baseEnergy = "base_energy"
        case bonusEnergy = "bonus_energy"
        case remainingBalance = "remaining_balance"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        stepsCount = try container.decodeIfPresent(Int.self, forKey: .stepsCount) ?? 0
        sleepHours = try container.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        baseEnergy = try container.decodeIfPresent(Int.self, forKey: .baseEnergy) ?? 0
        bonusEnergy = try container.decodeIfPresent(Int.self, forKey: .bonusEnergy) ?? 0
        remainingBalance = try container.decodeIfPresent(Int.self, forKey: .remainingBalance) ?? 0
    }
    
    init(userId: String, dayKey: String, stepsCount: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int) {
        self.userId = userId
        self.dayKey = dayKey
        self.stepsCount = stepsCount
        self.sleepHours = sleepHours
        self.baseEnergy = baseEnergy
        self.bonusEnergy = bonusEnergy
        self.remainingBalance = remainingBalance
    }
}

private struct DailySpentRow: Codable {
    let userId: String
    let dayKey: String
    let totalSpent: Int
    let spentByApp: [String: Int]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case totalSpent = "total_spent"
        case spentByApp = "spent_by_app"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        totalSpent = try container.decodeIfPresent(Int.self, forKey: .totalSpent) ?? 0
        spentByApp = try container.decodeIfPresent([String: Int].self, forKey: .spentByApp) ?? [:]
    }
    
    init(userId: String, dayKey: String, totalSpent: Int, spentByApp: [String: Int]) {
        self.userId = userId
        self.dayKey = dayKey
        self.totalSpent = totalSpent
        self.spentByApp = spentByApp
    }
}

private struct ActivityStatRpcParams: Codable {
    let pActivityId: String
    let pCategory: String
    let pTitleEn: String
    let pTitleRu: String
    let pIcon: String
    let pIsCustom: Bool
    
    enum CodingKeys: String, CodingKey {
        case pActivityId = "p_activity_id"
        case pCategory = "p_category"
        case pTitleEn = "p_title_en"
        case pTitleRu = "p_title_ru"
        case pIcon = "p_icon"
        case pIsCustom = "p_is_custom"
    }
}

private struct AnalyticsEventPayload: Codable, Equatable {
    let id: String
    let eventName: String
    let dayKey: String
    let properties: [String: String]
    let occurredAt: Date
}

private struct AnalyticsEventInsertRow: Codable {
    let userId: String
    let eventName: String
    let dayKey: String
    let properties: [String: String]
    let eventId: String
    let occurredAt: String
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case eventName = "event_name"
        case dayKey = "day_key"
        case properties
        case eventId = "event_id"
        case occurredAt = "occurred_at"
    }
}

private struct TicketGroupSyncRow: Equatable {
    let bundleId: String
    let mode: String
    let name: String
    let templateApp: String?
    let stickerThemeIndex: Int
    let enabledIntervals: [String]
    let settingsJson: Data

    static func from(group: TicketGroup) -> TicketGroupSyncRow {
        let mode = group.settings.minuteTariffEnabled ? "minute" : "ticket"
        let settingsData = (try? JSONEncoder().encode(group.settings)) ?? Data("{}".utf8)
        return TicketGroupSyncRow(
            bundleId: "group:\(group.id)",
            mode: mode,
            name: group.name,
            templateApp: group.templateApp,
            stickerThemeIndex: group.stickerThemeIndex,
            enabledIntervals: group.enabledIntervals.map(\.rawValue).sorted(),
            settingsJson: settingsData
        )
    }
}

private struct TicketGroupSyncInsertRow: Codable {
    let userId: String
    let bundleId: String
    let mode: String
    let name: String?
    let templateApp: String?
    let stickerThemeIndex: Int
    let enabledIntervals: [String]
    let settingsJson: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case bundleId = "bundle_id"
        case mode
        case name
        case templateApp = "template_app"
        case stickerThemeIndex = "sticker_theme_index"
        case enabledIntervals = "enabled_intervals"
        case settingsJson = "settings_json"
    }
}

/// Lightweight wrapper for encoding arbitrary JSON values in Codable structs.
private enum AnyCodableValue: Codable, Equatable {
    case int(Int)
    case bool(Bool)
    case string(String)
    case array([String])
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool must be checked before Int — NSJSONSerialization stores bools as NSNumber,
        // so decode(Int.self) succeeds on true/false and silently returns 1/0.
        if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Int.self) { self = .int(v) }
        else if let v = try? container.decode([String].self) { self = .array(v) }
        else { self = .string(try container.decode(String.self)) }
    }
}

private struct DaySnapshotRow: Codable {
    let userId: String
    let dayKey: String
    let inkEarned: Int
    let inkSpent: Int
    let bodyIds: [String]
    let mindIds: [String]
    let heartIds: [String]
    let steps: Int
    let sleepHours: Double
    let stepsTarget: Double
    let sleepTargetHours: Double
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case inkEarned = "experience_earned"
        case inkSpent = "experience_spent"
        case bodyIds = "body_ids"
        case mindIds = "mind_ids"
        case heartIds = "heart_ids"
        case steps
        case sleepHours = "sleep_hours"
        case stepsTarget = "steps_target"
        case sleepTargetHours = "sleep_target_hours"
    }
    
    init(userId: String, dayKey: String, inkEarned: Int, inkSpent: Int,
         bodyIds: [String], mindIds: [String], heartIds: [String],
         steps: Int, sleepHours: Double, stepsTarget: Double, sleepTargetHours: Double) {
        self.userId = userId
        self.dayKey = dayKey
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.bodyIds = bodyIds
        self.mindIds = mindIds
        self.heartIds = heartIds
        self.steps = steps
        self.sleepHours = sleepHours
        self.stepsTarget = stepsTarget
        self.sleepTargetHours = sleepTargetHours
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        inkEarned = try c.decodeIfPresent(Int.self, forKey: .inkEarned) ?? 0
        inkSpent = try c.decodeIfPresent(Int.self, forKey: .inkSpent) ?? 0
        bodyIds = try c.decodeIfPresent([String].self, forKey: .bodyIds) ?? []
        mindIds = try c.decodeIfPresent([String].self, forKey: .mindIds) ?? []
        heartIds = try c.decodeIfPresent([String].self, forKey: .heartIds) ?? []
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 0
        sleepHours = try c.decodeIfPresent(Double.self, forKey: .sleepHours) ?? 0
        stepsTarget = try c.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTargetHours = try c.decodeIfPresent(Double.self, forKey: .sleepTargetHours) ?? EnergyDefaults.sleepTargetHours
    }
}

private struct UserPreferencesRow: Decodable {
    let userId: String
    let stepsTarget: Double
    let sleepTarget: Double
    let dayEndHour: Int
    let dayEndMinute: Int
    let restDayOverride: Bool
    let preferredBody: [String]
    let preferredMind: [String]
    let preferredHeart: [String]
    let gallerySlots: AnyCodable? // Raw JSONB
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case stepsTarget = "steps_target"
        case sleepTarget = "sleep_target"
        case dayEndHour = "day_end_hour"
        case dayEndMinute = "day_end_minute"
        case restDayOverride = "rest_day_override"
        case preferredBody = "preferred_body"
        case preferredMind = "preferred_mind"
        case preferredHeart = "preferred_heart"
        case gallerySlots = "gallery_slots"
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        stepsTarget = try c.decodeIfPresent(Double.self, forKey: .stepsTarget) ?? EnergyDefaults.stepsTarget
        sleepTarget = try c.decodeIfPresent(Double.self, forKey: .sleepTarget) ?? EnergyDefaults.sleepTargetHours
        dayEndHour = try c.decodeIfPresent(Int.self, forKey: .dayEndHour) ?? 0
        dayEndMinute = try c.decodeIfPresent(Int.self, forKey: .dayEndMinute) ?? 0
        restDayOverride = try c.decodeIfPresent(Bool.self, forKey: .restDayOverride) ?? false
        preferredBody = try c.decodeIfPresent([String].self, forKey: .preferredBody) ?? []
        preferredMind = try c.decodeIfPresent([String].self, forKey: .preferredMind) ?? []
        preferredHeart = try c.decodeIfPresent([String].self, forKey: .preferredHeart) ?? []
        gallerySlots = try c.decodeIfPresent(AnyCodable.self, forKey: .gallerySlots)
    }
}

/// Row returned when reading canvas from Supabase. canvas_json is raw JSON (Any).
private struct DayCanvasReadRow: Decodable {
    let canvasJson: Any
    
    enum CodingKeys: String, CodingKey {
        case canvasJson = "canvas_json"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode as raw JSON via JSONSerialization
        let rawJSON = try container.decode(AnyCodable.self, forKey: .canvasJson)
        canvasJson = rawJSON.value
    }
}

/// Wrapper to decode arbitrary JSON from Supabase JSONB columns.
private struct AnyCodable: Decodable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = NSNull()
        }
    }
}
