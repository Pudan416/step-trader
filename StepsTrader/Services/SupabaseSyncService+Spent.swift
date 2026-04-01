import Foundation
import os.log

// MARK: - Daily Spent Sync
extension SupabaseSyncService {
    
    /// Sync daily spent points
    func syncDailySpent(dayKey: String, totalSpent: Int, spentByApp: [String: Int]) {
        let payload = DailySpentPayload(
            dayKey: dayKey,
            totalSpent: totalSpent,
            spentByApp: spentByApp
        )
        
        if payload == pendingDailySpent {
            return
        }
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
    
    // MARK: - Perform Spent Sync
    
    func performDailySpentSync(payload: DailySpentPayload) async {
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
    
    // MARK: - Restore from Server
    
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
}
