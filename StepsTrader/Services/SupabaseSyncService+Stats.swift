import Foundation
import os.log

// MARK: - Daily Stats, Snapshots & Historical Data
extension SupabaseSyncService {
    
    // MARK: - Public Sync Methods
    
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
        
        if payload == pendingDailyStats {
            return
        }
        if payload == lastSentDailyStats {
            pendingDailyStats = nil
            dailyStatsSyncTask?.cancel()
            return
        }
        
        pendingDailyStats = payload
        dailyStatsSyncTask?.cancel()
        dailyStatsSyncTask = Task {
            try? await Task.sleep(for: statsDebounceDuration)
            guard !Task.isCancelled else { return }
            guard let latest = pendingDailyStats else { return }
            await performDailyStatsSync(payload: latest)
        }
    }
    
    /// Sync a day-end snapshot to Supabase (called when the day resets)
    func syncDaySnapshot(dayKey: String, snapshot: PastDaySnapshot) {
        daySnapshotSyncTask?.cancel()
        daySnapshotSyncTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await performDaySnapshotSync(dayKey: dayKey, snapshot: snapshot)
        }
    }
    
    // MARK: - Perform Sync Implementations
    
    func performDailyStatsSync(payload: DailyStatsPayload) async {
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
        
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Daily stats sync skipped: no auth")
            return
        }
        if Task.isCancelled { return }
        let token = auth.token
        let userId = auth.userId
        
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
    
    private func performDaySnapshotSync(dayKey: String, snapshot: PastDaySnapshot) async {
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Day snapshot sync skipped: no auth")
            return
        }
        if Task.isCancelled { return }
        let token = auth.token
        let userId = auth.userId
        
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
    
    // MARK: - Restore from Server
    
    /// Load today's daily stats from Supabase
    func loadTodayStatsFromServer() async -> (steps: Int, sleepHours: Double, baseEnergy: Int, bonusEnergy: Int, remainingBalance: Int)? {
        guard let auth = await authenticatedContext() else { return nil }
        let token = auth.token
        let userId = auth.userId
        
        let today = AppModel.dayKey(for: Date.now)
        if let cached = cachedTodayStats,
           cached.dayKey == today,
           Date.now.timeIntervalSince(cached.timestamp) < todayCacheTTL {
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
            let rows = try decoder.decode([DailyStatsRow].self, from: data)
            
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No stats found for today on server")
                return nil
            }
            
            AppLogger.network.debug("📡 Loaded today's stats from server: steps=\(row.stepsCount), balance=\(row.remainingBalance)")
            
            let value = (row.stepsCount, row.sleepHours, row.baseEnergy, row.bonusEnergy, row.remainingBalance)
            cachedTodayStats = CachedTodayValue(dayKey: today, value: value, timestamp: Date.now)
            return value
        } catch {
            AppLogger.network.error("📡 Failed to load today's stats: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load day snapshots from Supabase (for restoring history on new device)
    func loadDaySnapshotsFromServer() async -> [String: PastDaySnapshot] {
        guard let auth = await authenticatedContext() else { return [:] }
        let token = auth.token
        let userId = auth.userId
        
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
    
    // MARK: - Historical Snapshots
    
    /// Load all historical day snapshots from Supabase
    /// Combines data from user_daily_selections, user_daily_stats, and user_daily_spent
    func loadHistoricalSnapshots() async -> [String: PastDaySnapshot] {
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Historical load skipped: no auth")
            return [:]
        }
        let token = auth.token
        let userId = auth.userId
        
        guard let config = try? SupabaseConfig.load() else {
            return [:]
        }
        
        var snapshots: [String: PastDaySnapshot] = [:]
        
        let g = UserDefaults.stepsTrader()
        let now = Date.now
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
            let fetchedAnything = !selections.isEmpty || !stats.isEmpty || !spent.isEmpty
            if fetchedAnything {
                g.set(now, forKey: historicalLastFullSyncKey)
            } else {
                AppLogger.network.debug("📡 Historical full sync returned no data — will retry next time")
            }
        } else {
            selections = await loadAllSelections(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
            stats = await loadAllStats(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
            spent = await loadAllSpent(config: config, userId: userId, token: token, fromDayKey: lastDayKey)
        }
        
        var allDayKeys = Set<String>()
        allDayKeys.formUnion(selections.keys)
        allDayKeys.formUnion(stats.keys)
        allDayKeys.formUnion(spent.keys)
        
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
    
    // MARK: - Private Historical Helpers
    
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
            AppLogger.network.error("📡 Failed to load all selections: \(error.localizedDescription) — \(String(describing: error))")
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
            AppLogger.network.error("📡 Failed to load all stats: \(error.localizedDescription) — \(String(describing: error))")
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
            AppLogger.network.error("📡 Failed to load all spent: \(error.localizedDescription) — \(String(describing: error))")
            return [:]
        }
    }
}
