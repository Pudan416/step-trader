import Foundation
import os.log

// MARK: - Custom Activities & Daily Selections
extension SupabaseSyncService {
    
    // MARK: - Public Sync Methods

    
    /// Sync daily selections for a given day
    func syncDailySelections(dayKey: String, activityIds: [String], recoveryIds: [String], joysIds: [String]) {
        let payload = DailySelectionsPayload(
            dayKey: dayKey,
            activityIds: activityIds,
            recoveryIds: recoveryIds,
            joysIds: joysIds
        )
        
        if payload == pendingDailySelections {
            return
        }
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
            try? await Task.sleep(for: selectionsDebounceDuration)
            if Task.isCancelled {
                AppLogger.network.debug("📡 syncDailySelections Task was CANCELLED")
                return
            }
            AppLogger.network.debug("📡 syncDailySelections Task proceeding to perform sync")
            guard let latest = pendingDailySelections else { return }
            await performDailySelectionsSync(payload: latest)
        }
    }
    
    // MARK: - Perform Sync Implementations

    
    func performDailySelectionsSync(payload: DailySelectionsPayload) async {
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
        AppLogger.network.debug("📡   body: \(activityIds), mind: \(recoveryIds), heart: \(joysIds)")
        
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Daily selections sync skipped: no auth")
            return
        }
        if Task.isCancelled { return }
        let token = auth.token
        let userId = auth.userId
        
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
            
            // §5.5 — moment IDs are device-local; strip before the upsert hits
            // user_daily_selections. Moments were device-local and are now gone.
            let row = DailySelectionsRow(
                userId: userId,
                dayKey: dayKey,
                activityIds: activityIds,
                restIds: recoveryIds,
                joysIds: joysIds,
                updatedAt: iso8601String(Date.now) // §C3 stale-write guard
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
    
    // MARK: - Restore from Server

    
    /// Load today's daily selections from Supabase
    func loadTodaySelectionsFromServer() async -> (body: [String], mind: [String], heart: [String])? {
        guard let auth = await authenticatedContext() else { return nil }
        let token = auth.token
        let userId = auth.userId
        
        let today = AppModel.dayKey(for: Date.now)
        if let cached = cachedTodaySelections,
           cached.dayKey == today,
           Date.now.timeIntervalSince(cached.timestamp) < todayCacheTTL {
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
            let rows = try decoder.decode([DailySelectionsRow].self, from: data)
            
            guard let row = rows.first else {
                AppLogger.network.debug("📡 No selections found for today on server (empty array)")
                return nil
            }
            
            AppLogger.network.debug("📡 Loaded today's selections from server: body=\(row.activityIds), mind=\(row.restIds), heart=\(row.joysIds)")
            
            let value = (row.activityIds, row.restIds, row.joysIds)
            cachedTodaySelections = CachedTodayValue(dayKey: today, value: value, timestamp: Date.now)
            return value
        } catch {
            AppLogger.network.error("📡 Failed to load today's selections: \(error)")
            return nil
        }
    }
}
