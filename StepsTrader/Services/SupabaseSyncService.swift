import Foundation

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
    
    private var pendingDailySelections: DailySelectionsPayload?
    private var pendingDailyStats: DailyStatsPayload?
    private var pendingDailySpent: DailySpentPayload?
    
    private var lastSentDailySelections: DailySelectionsPayload?
    private var lastSentDailyStats: DailyStatsPayload?
    private var lastSentDailySpent: DailySpentPayload?
    
    // Track which activities we've already counted for this user today
    private var countedActivitiesToday: Set<String> = []
    private var countedActivitiesDate: String = ""
    
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
        print("📡 syncDailySelections CALLED for \(dayKey)")
        dailySelectionsSyncTask?.cancel()
        dailySelectionsSyncTask = Task {
            print("📡 syncDailySelections Task started, waiting debounce...")
            try? await Task.sleep(nanoseconds: selectionsDebounceNs)
            if Task.isCancelled {
                print("📡 syncDailySelections Task was CANCELLED")
                return
            }
            print("📡 syncDailySelections Task proceeding to perform sync")
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
    
    /// Full sync - call on app launch or after login
    func performFullSync(model: AppModel) async {
        print("📡 performFullSync called, waiting for auth initialization...")
        
        // Wait for AuthenticationService to finish restoring session
        await AuthenticationService.shared.waitForInitialization()
        let isAuthenticated = await AuthenticationService.shared.isAuthenticated
        let currentUserId = await AuthenticationService.shared.currentUser?.id
        let hasToken = await AuthenticationService.shared.accessToken != nil
        
        print("📡 Auth initialized. isAuthenticated: \(isAuthenticated)")
        print("📡 currentUser: \(currentUserId ?? "nil")")
        print("📡 accessToken: \(hasToken ? "exists" : "nil")")
        
        guard isAuthenticated, currentUserId != nil else {
            print("📡 Sync skipped: user not authenticated")
            return
        }
        
        print("📡 Starting full Supabase sync...")
        
        let snapshot = await MainActor.run {
            (
                customEnergyOptions: model.customEnergyOptions,
                dailyActivitySelections: model.dailyActivitySelections,
                dailyRestSelections: model.dailyRestSelections,
                dailyJoysSelections: model.dailyJoysSelections,
                stepsToday: model.stepsToday,
                dailySleepHours: model.dailySleepHours,
                baseEnergyToday: model.baseEnergyToday,
                bonusSteps: model.bonusSteps,
                totalStepsBalance: model.totalStepsBalance,
                appStepsSpentByDay: model.appStepsSpentByDay
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
        
        print("📡 Full sync completed")
    }
    
    // MARK: - Private Sync Implementations
    
    private func performCustomActivitiesSync(_ activities: [CustomEnergyOption]) async {
        await AuthenticationService.shared.waitForInitialization()
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            print("📡 Custom activities sync skipped: no auth")
            return
        }
        
        // Check if data changed
        let hash = activities.hashValue
        guard hash != lastSyncedCustomActivitiesHash else {
            print("📡 Custom activities unchanged, skipping sync")
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
                    print("📡 Custom activities cleared on server")
                } else {
                    print("📡 Custom activities clear failed")
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
                print("📡 Custom activities upsert failed")
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
                print("📡 Custom activities synced: \(activities.count) items")
            } else {
                print("📡 Custom activities delete-missing failed")
            }
        } catch {
            print("📡 Custom activities sync error: \(error.localizedDescription)")
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
        
        print("📡 performDailySelectionsSync called for \(dayKey)")
        print("📡   activities: \(activityIds), recovery: \(recoveryIds), joys: \(joysIds)")
        
        // Wait for auth to be ready
        await AuthenticationService.shared.waitForInitialization()
        if Task.isCancelled { return }
        
        let token = await AuthenticationService.shared.accessToken
        let userId = await AuthenticationService.shared.currentUser?.id
        guard let token, let userId else {
            let hasToken = token != nil
            print("📡 Daily selections sync skipped: no auth (token=\(hasToken), user=\(userId ?? "nil"))")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_selections")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                print("📡 Error: Failed to create URLComponents for daily selections")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                print("📡 Error: Failed to get URL from components for daily selections")
                return
            }
            print("📡 POST URL: \(url.absoluteString)")
            
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
            print("📡 POST body: \(String(data: bodyData, encoding: .utf8) ?? "nil")")
            
            let (data, response) = try await network.data(for: request)
            if Task.isCancelled { return }
            if response.statusCode < 400 {
                lastSentDailySelections = payload
                print("📡 Daily selections synced for \(dayKey)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                print("📡 Daily selections sync failed for \(dayKey): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            print("📡 Daily selections sync error: \(error.localizedDescription)")
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
            print("📡 Daily stats sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_stats")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                print("📡 Error: Failed to create URLComponents for daily stats")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                print("📡 Error: Failed to get URL from components for daily stats")
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
                print("📡 Daily stats synced for \(dayKey): steps=\(steps), sleep=\(sleepHours)h, balance=\(remainingBalance)")
            } else {
                print("📡 Daily stats sync failed for \(dayKey)")
            }
        } catch {
            print("📡 Daily stats sync error: \(error.localizedDescription)")
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
            print("📡 Daily spent sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_daily_spent")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                print("📡 Error: Failed to create URLComponents for daily spent")
                return
            }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            
            guard let url = urlComps.url else {
                print("📡 Error: Failed to get URL from components for daily spent")
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
                print("📡 Daily spent synced for \(dayKey): total=\(totalSpent)")
            } else {
                print("📡 Daily spent sync failed for \(dayKey)")
            }
        } catch {
            print("📡 Daily spent sync error: \(error.localizedDescription)")
        }
    }
    
    private func performActivityStatsIncrement(activityId: String, category: String, titleEn: String, titleRu: String, icon: String, isCustom: Bool) async {
        print("📡 performActivityStatsIncrement called for \(activityId)")
        
        await AuthenticationService.shared.waitForInitialization()
        
        guard let token = await AuthenticationService.shared.accessToken else {
            print("📡 Activity stats sync skipped: no auth token")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            
            // Use RPC to upsert and increment atomically
            let url = cfg.baseURL.appendingPathComponent("rest/v1/rpc/increment_activity_stat")
            print("📡 Calling RPC: \(url.absoluteString)")
            
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
                print("📡 Activity stat incremented: \(activityId)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                print("📡 Activity stat increment failed for \(activityId): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            print("📡 Activity stat sync error: \(error.localizedDescription)")
        }
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
            
            print("📡 Loaded \(rows.count) custom activities from server")
            
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
            print("📡 Failed to load custom activities: \(error.localizedDescription)")
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
            
            print("📡 Raw selections response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySelectionsRow].self, from: data)
            
            guard let row = rows.first else {
                print("📡 No selections found for today on server (empty array)")
                return nil
            }
            
            print("📡 Loaded today's selections from server: activity=\(row.activityIds), rest=\(row.restIds), joys=\(row.joysIds)")
            
            let value = (row.activityIds, row.restIds, row.joysIds)
            cachedTodaySelections = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            print("📡 Failed to load today's selections: \(error)")
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
                print("📡 No stats found for today on server")
                return nil
            }
            
            print("📡 Loaded today's stats from server: steps=\(row.stepsCount), balance=\(row.remainingBalance)")
            
            let value = (row.stepsCount, row.sleepHours, row.baseEnergy, row.bonusEnergy, row.remainingBalance)
            cachedTodayStats = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            print("📡 Failed to load today's stats: \(error.localizedDescription)")
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
            
            print("📡 Raw spent response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySpentRow].self, from: data)
            
            guard let row = rows.first else {
                print("📡 No spent data found for today on server (empty array)")
                return nil
            }
            
            print("📡 Loaded today's spent from server: total=\(row.totalSpent), byApp=\(row.spentByApp)")
            
            let value = (row.totalSpent, row.spentByApp)
            cachedTodaySpent = CachedTodayValue(dayKey: today, value: value, timestamp: Date())
            return value
        } catch {
            print("📡 Failed to load today's spent: \(error)")
            return nil
        }
    }
    
    /// Full restore - load all data from Supabase and apply to AppModel
    func restoreFromServer(model: AppModel) async -> Bool {
        print("📡 Starting restore from Supabase...")
        
        await AuthenticationService.shared.waitForInitialization()
        let isAuthenticated = await AuthenticationService.shared.isAuthenticated
        let currentUser = await AuthenticationService.shared.currentUser
        guard isAuthenticated, currentUser != nil else {
            print("📡 Restore skipped: user not authenticated")
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
        
        if didRestore {
            print("📡 Restore completed, recalculating energy...")
            await MainActor.run {
                model.recalculateDailyEnergy()
            }
        } else {
            print("📡 No data to restore from server (or all empty)")
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
            print("📡 Historical load skipped: no auth")
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
                controlGained: stat?.baseEnergy ?? 0,
                controlSpent: sp?.totalSpent ?? 0,
                activityIds: sel?.activityIds ?? [],
                creativityIds: sel?.restIds ?? [],
                joysIds: sel?.joysIds ?? [],
                steps: stat?.stepsCount ?? 0,
                sleepHours: stat?.sleepHours ?? 0
            )
            
            snapshots[dayKey] = snapshot
        }
        
        print("📡 Loaded \(snapshots.count) historical snapshots from Supabase")
        
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
            print("📡 Failed to load all selections: \(error)")
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
            print("📡 Failed to load all stats: \(error)")
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
            print("📡 Failed to load all spent: \(error)")
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

// MARK: - Supabase Config (shared)

private struct SupabaseConfig {
    let baseURL: URL
    let anonKey: String
    
    static func load() throws -> SupabaseConfig {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        
        guard let urlString, let anonKey, let url = URL(string: urlString), !anonKey.isEmpty else {
            print("📡 SupabaseConfig FAILED: url=\(urlString ?? "nil"), anonKey=\(anonKey != nil ? "exists" : "nil")")
            throw SyncError.misconfigured
        }
        return SupabaseConfig(baseURL: url, anonKey: anonKey)
    }
}

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
