import Foundation
import os.log

// MARK: - Custom Activities & Daily Selections
extension SupabaseSyncService {
    
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
    
    // MARK: - Perform Sync Implementations
    
    func performCustomActivitiesSync(_ activities: [CustomEnergyOption]) async {
        await AuthenticationService.shared.waitForInitialization()
        
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Custom activities sync skipped: no auth")
            return
        }
        
        let hash = activities.hashValue
        guard hash != lastSyncedCustomActivitiesHash else {
            AppLogger.network.debug("📡 Custom activities unchanged, skipping sync")
            return
        }
        
        do {
            let cfg = try SupabaseConfig.load()
            
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
        AppLogger.network.debug("📡   activities: \(activityIds), recovery: \(recoveryIds), joys: \(joysIds)")
        
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
    
    // MARK: - Restore from Server
    
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
}
