import Foundation

// MARK: - Supabase Sync Service
/// Handles syncing user activity data to Supabase
@MainActor
class SupabaseSyncService: ObservableObject {
    
    static let shared = SupabaseSyncService()
    
    private let authService = AuthenticationService.shared
    
    // Debounce timers to avoid too frequent syncs
    private var customActivitiesSyncTask: Task<Void, Never>?
    private var dailySelectionsSyncTask: Task<Void, Never>?
    private var dailyStatsSyncTask: Task<Void, Never>?
    private var dailySpentSyncTask: Task<Void, Never>?
    private var activityStatsSyncTask: Task<Void, Never>?
    
    private var lastSyncedCustomActivitiesHash: Int = 0
    private var lastSyncedDayKey: String = ""
    
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
            await performCustomActivitiesSync(activities)
        }
    }
    
    /// Sync daily selections for a given day
    func syncDailySelections(dayKey: String, activityIds: [String], recoveryIds: [String], joysIds: [String]) {
        print("📡 syncDailySelections CALLED for \(dayKey)")
        dailySelectionsSyncTask?.cancel()
        dailySelectionsSyncTask = Task {
            print("📡 syncDailySelections Task started, waiting 1 sec...")
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec debounce
            if Task.isCancelled {
                print("📡 syncDailySelections Task was CANCELLED")
                return
            }
            print("📡 syncDailySelections Task proceeding to perform sync")
            await performDailySelectionsSync(dayKey: dayKey, activityIds: activityIds, recoveryIds: recoveryIds, joysIds: joysIds)
        }
    }
    
    /// Sync daily stats (steps, sleep, balance)
    func syncDailyStats(dayKey: String, steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int) {
        dailyStatsSyncTask?.cancel()
        dailyStatsSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 sec debounce
            guard !Task.isCancelled else { return }
            await performDailyStatsSync(dayKey: dayKey, steps: steps, sleepHours: sleepHours, baseEnergy: baseEnergy, bonusEnergy: bonusEnergy, remainingBalance: remainingBalance)
        }
    }
    
    /// Sync daily spent points
    func syncDailySpent(dayKey: String, totalSpent: Int, spentByApp: [String: Int]) {
        dailySpentSyncTask?.cancel()
        dailySpentSyncTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec debounce
            guard !Task.isCancelled else { return }
            await performDailySpentSync(dayKey: dayKey, totalSpent: totalSpent, spentByApp: spentByApp)
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
            await performActivityStatsIncrement(
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
        await authService.waitForInitialization()
        
        print("📡 Auth initialized. isAuthenticated: \(authService.isAuthenticated)")
        print("📡 currentUser: \(authService.currentUser?.id ?? "nil")")
        print("📡 accessToken: \(authService.accessToken != nil ? "exists" : "nil")")
        
        guard authService.isAuthenticated, authService.currentUser != nil else {
            print("📡 Sync skipped: user not authenticated")
            return
        }
        
        print("📡 Starting full Supabase sync...")
        
        // Sync custom activities
        await performCustomActivitiesSync(model.customEnergyOptions)
        
        // Sync today's data
        let today = AppModel.dayKey(for: Date())
        
        await performDailySelectionsSync(
            dayKey: today,
            activityIds: model.dailyActivitySelections,
            recoveryIds: model.dailyRecoverySelections,
            joysIds: model.dailyJoysSelections
        )
        
        await performDailyStatsSync(
            dayKey: today,
            steps: Int(model.stepsToday),
            sleepHours: model.dailySleepHours,
            baseEnergy: model.baseEnergyToday,
            bonusEnergy: model.bonusSteps,
            remainingBalance: model.totalStepsBalance
        )
        
        let todaySpent = model.appStepsSpentByDay[today] ?? [:]
        let totalSpent = todaySpent.values.reduce(0, +)
        await performDailySpentSync(dayKey: today, totalSpent: totalSpent, spentByApp: todaySpent)
        
        print("📡 Full sync completed")
    }
    
    // MARK: - Private Sync Implementations
    
    private func performCustomActivitiesSync(_ activities: [CustomEnergyOption]) async {
        await authService.waitForInitialization()
        
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
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
            
            // First, delete existing custom activities for this user
            let deleteURL = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
            guard var deleteComps = URLComponents(url: deleteURL, resolvingAgainstBaseURL: false) else { return }
            deleteComps.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
            
            if let url = deleteComps.url {
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                _ = try? await URLSession.shared.data(for: request)
            }
            
            // Then insert all current activities
            guard !activities.isEmpty else {
                lastSyncedCustomActivitiesHash = hash
                print("📡 Custom activities cleared on server")
                return
            }
            
            let insertURL = cfg.baseURL.appendingPathComponent("rest/v1/user_custom_activities")
            var request = URLRequest(url: insertURL)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("return=minimal", forHTTPHeaderField: "prefer")
            
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
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 400 {
                lastSyncedCustomActivitiesHash = hash
                print("📡 Custom activities synced: \(activities.count) items")
            } else {
                print("📡 Custom activities sync failed")
            }
        } catch {
            print("📡 Custom activities sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailySelectionsSync(dayKey: String, activityIds: [String], recoveryIds: [String], joysIds: [String]) async {
        print("📡 performDailySelectionsSync called for \(dayKey)")
        print("📡   activities: \(activityIds), recovery: \(recoveryIds), joys: \(joysIds)")
        
        // Wait for auth to be ready
        await authService.waitForInitialization()
        
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            print("📡 Daily selections sync skipped: no auth (token=\(authService.accessToken != nil), user=\(authService.currentUser?.id ?? "nil"))")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            var urlComps = URLComponents(url: cfg.baseURL.appendingPathComponent("rest/v1/user_daily_selections"), resolvingAgainstBaseURL: false)!
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            let url = urlComps.url!
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
                recoveryIds: recoveryIds,
                joysIds: joysIds
            )
            
            let bodyData = try JSONEncoder().encode(row)
            request.httpBody = bodyData
            print("📡 POST body: \(String(data: bodyData, encoding: .utf8) ?? "nil")")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode < 400 {
                    print("📡 Daily selections synced for \(dayKey)")
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "no body"
                    print("📡 Daily selections sync failed for \(dayKey): HTTP \(http.statusCode) - \(body)")
                }
            }
        } catch {
            print("📡 Daily selections sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailyStatsSync(dayKey: String, steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int) async {
        await authService.waitForInitialization()
        
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            print("📡 Daily stats sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            var urlComps = URLComponents(url: cfg.baseURL.appendingPathComponent("rest/v1/user_daily_stats"), resolvingAgainstBaseURL: false)!
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            let url = urlComps.url!
            
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
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 400 {
                print("📡 Daily stats synced for \(dayKey): steps=\(steps), sleep=\(sleepHours)h, balance=\(remainingBalance)")
            } else {
                print("📡 Daily stats sync failed for \(dayKey)")
            }
        } catch {
            print("📡 Daily stats sync error: \(error.localizedDescription)")
        }
    }
    
    private func performDailySpentSync(dayKey: String, totalSpent: Int, spentByApp: [String: Int]) async {
        await authService.waitForInitialization()
        
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            print("📡 Daily spent sync skipped: no auth")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            var urlComps = URLComponents(url: cfg.baseURL.appendingPathComponent("rest/v1/user_daily_spent"), resolvingAgainstBaseURL: false)!
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key")]
            let url = urlComps.url!
            
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
            
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode < 400 {
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
        
        await authService.waitForInitialization()
        
        guard let token = authService.accessToken else {
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode < 400 {
                    print("📡 Activity stat incremented: \(activityId)")
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "no body"
                    print("📡 Activity stat increment failed for \(activityId): HTTP \(http.statusCode) - \(body)")
                }
            }
        } catch {
            print("📡 Activity stat sync error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Restore from Supabase
    
    /// Load custom activities from Supabase (for restoring on new device)
    func loadCustomActivitiesFromServer() async -> [CustomEnergyOption]? {
        await authService.waitForInitialization()
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([CustomActivityRow].self, from: data)
            
            print("📡 Loaded \(rows.count) custom activities from server")
            
            return rows.compactMap { row in
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
    func loadTodaySelectionsFromServer() async -> (activity: [String], recovery: [String], joys: [String])? {
        await authService.waitForInitialization()
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            
            print("📡 Raw selections response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySelectionsRow].self, from: data)
            
            guard let row = rows.first else {
                print("📡 No selections found for today on server (empty array)")
                return nil
            }
            
            print("📡 Loaded today's selections from server: activity=\(row.activityIds), recovery=\(row.recoveryIds), joys=\(row.joysIds)")
            
            return (row.activityIds, row.recoveryIds, row.joysIds)
        } catch {
            print("📡 Failed to load today's selections: \(error)")
            return nil
        }
    }
    
    /// Load today's daily stats from Supabase
    func loadTodayStatsFromServer() async -> (steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int)? {
        await authService.waitForInitialization()
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailyStatsRow].self, from: data)
            
            guard let row = rows.first else {
                print("📡 No stats found for today on server")
                return nil
            }
            
            print("📡 Loaded today's stats from server: steps=\(row.stepsCount), balance=\(row.remainingBalance)")
            
            return (row.stepsCount, row.sleepHours, row.baseEnergy, row.bonusEnergy, row.remainingBalance)
        } catch {
            print("📡 Failed to load today's stats: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load today's spent points from Supabase
    func loadTodaySpentFromServer() async -> (totalSpent: Int, spentByApp: [String: Int])? {
        await authService.waitForInitialization()
        guard let token = authService.accessToken,
              let userId = authService.currentUser?.id else {
            return nil
        }
        
        let today = AppModel.dayKey(for: Date())
        
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
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else { return nil }
            
            print("📡 Raw spent response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            let decoder = JSONDecoder()
            // CodingKeys already handle snake_case mapping
            let rows = try decoder.decode([DailySpentRow].self, from: data)
            
            guard let row = rows.first else {
                print("📡 No spent data found for today on server (empty array)")
                return nil
            }
            
            print("📡 Loaded today's spent from server: total=\(row.totalSpent), byApp=\(row.spentByApp)")
            
            return (row.totalSpent, row.spentByApp)
        } catch {
            print("📡 Failed to load today's spent: \(error)")
            return nil
        }
    }
    
    /// Full restore - load all data from Supabase and apply to AppModel
    func restoreFromServer(model: AppModel) async -> Bool {
        print("📡 Starting restore from Supabase...")
        
        await authService.waitForInitialization()
        guard authService.isAuthenticated, authService.currentUser != nil else {
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
            let hasData = !selections.activity.isEmpty || !selections.recovery.isEmpty || !selections.joys.isEmpty
            if hasData {
                await MainActor.run {
                    model.dailyActivitySelections = selections.activity
                    model.dailyRecoverySelections = selections.recovery
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
        await authService.waitForInitialization()
        guard authService.isAuthenticated,
              let userId = authService.currentUser?.id,
              let token = authService.accessToken else {
            print("📡 Historical load skipped: no auth")
            return [:]
        }
        
        guard let config = try? SupabaseConfig.load() else {
            return [:]
        }
        
        var snapshots: [String: PastDaySnapshot] = [:]
        
        // Load all selections
        let selections = await loadAllSelections(config: config, userId: userId, token: token)
        
        // Load all stats
        let stats = await loadAllStats(config: config, userId: userId, token: token)
        
        // Load all spent
        let spent = await loadAllSpent(config: config, userId: userId, token: token)
        
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
                recoveryIds: sel?.recoveryIds ?? [],
                joysIds: sel?.joysIds ?? [],
                steps: stat?.stepsCount ?? 0,
                sleepHours: stat?.sleepHours ?? 0
            )
            
            snapshots[dayKey] = snapshot
        }
        
        print("📡 Loaded \(snapshots.count) historical snapshots from Supabase")
        return snapshots
    }
    
    private func loadAllSelections(config: SupabaseConfig, userId: String, token: String) async -> [String: DailySelectionsRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_selections")
        var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]
        
        var request = URLRequest(url: urlComps.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let rows = try decoder.decode([DailySelectionsRow].self, from: data)
            
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
    
    private func loadAllStats(config: SupabaseConfig, userId: String, token: String) async -> [String: DailyStatsRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_stats")
        var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]
        
        var request = URLRequest(url: urlComps.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let rows = try decoder.decode([DailyStatsRow].self, from: data)
            
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
    
    private func loadAllSpent(config: SupabaseConfig, userId: String, token: String) async -> [String: DailySpentRow] {
        let endpoint = config.baseURL.appendingPathComponent("/rest/v1/user_daily_spent")
        var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComps.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]
        
        var request = URLRequest(url: urlComps.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let rows = try decoder.decode([DailySpentRow].self, from: data)
            
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
    let recoveryIds: [String]
    let joysIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dayKey = "day_key"
        case activityIds = "activity_ids"
        case recoveryIds = "recovery_ids"
        case joysIds = "joys_ids"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        activityIds = try container.decodeIfPresent([String].self, forKey: .activityIds) ?? []
        recoveryIds = try container.decodeIfPresent([String].self, forKey: .recoveryIds) ?? []
        joysIds = try container.decodeIfPresent([String].self, forKey: .joysIds) ?? []
    }
    
    init(userId: String, dayKey: String, activityIds: [String], recoveryIds: [String], joysIds: [String]) {
        self.userId = userId
        self.dayKey = dayKey
        self.activityIds = activityIds
        self.recoveryIds = recoveryIds
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
