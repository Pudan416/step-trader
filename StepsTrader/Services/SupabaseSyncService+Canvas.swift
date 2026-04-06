import Foundation
import os.log

// MARK: - Day Canvas Sync
extension SupabaseSyncService {
    
    /// Sync full DayCanvas to Supabase `user_day_canvases` table.
    /// Stores the entire canvas JSON (elements, palette, shapes) keyed by day.
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
            
            let rows = try JSONDecoder().decode([DayCanvasReadRow].self, from: data)
            guard let row = rows.first else { return nil }
            
            let canvasData = try JSONSerialization.data(withJSONObject: row.canvasJson)
            let canvas = try JSONDecoder().decode(DayCanvas.self, from: canvasData)
            AppLogger.network.debug("📡 fetchDayCanvas: restored canvas for \(dayKey) with \(canvas.elements.count) elements")
            return canvas
        } catch {
            AppLogger.network.error("📡 fetchDayCanvas error: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Private Canvas Sync
    
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
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Day canvas sync error: \(error.localizedDescription)")
        }
    }
}
