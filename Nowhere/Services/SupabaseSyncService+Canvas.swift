import Foundation
import os.log

enum DayCanvasFetchResult {
    case found(DayCanvas)
    case confirmedAbsent
    case failed

    static func decode(statusCode: Int, data: Data) -> Self {
        guard (200..<300).contains(statusCode) else { return .failed }
        do {
            let rows = try JSONDecoder().decode([DayCanvasReadRow].self, from: data)
            guard let row = rows.first else { return .confirmedAbsent }
            let canvasData = try JSONSerialization.data(withJSONObject: row.canvasJson)
            return .found(try JSONDecoder().decode(DayCanvas.self, from: canvasData))
        } catch {
            return .failed
        }
    }
}

/// Actor-owned admission state shared by live Canvas writes and raw retries.
struct CanvasUploadOrdering {
    private(set) var isDrainingRetries = false
    private var uploadingDays = Set<String>()
    private var recoveringDays = Set<String>()
    private var followupDays = Set<String>()

    mutating func beginRecovery(for dayKey: String) -> Bool {
        guard !isDrainingRetries else { return false }
        return recoveringDays.insert(dayKey).inserted
    }
    /// The caller schedules only after releasing recovery, including when a
    /// successful child upload requested another pass before its parent resumed.
    mutating func endRecovery(for dayKey: String) -> Bool {
        recoveringDays.remove(dayKey)
        return followupDays.remove(dayKey) != nil
    }
    mutating func requestFollowup(for dayKey: String) -> Bool {
        if recoveringDays.contains(dayKey) {
            followupDays.insert(dayKey)
            return false
        }
        return true
    }

    mutating func beginUpload(for dayKey: String) -> Bool {
        guard !isDrainingRetries else { return false }
        return uploadingDays.insert(dayKey).inserted
    }
    mutating func endUpload(for dayKey: String) { uploadingDays.remove(dayKey) }
    mutating func beginRetryDrain() -> Bool {
        guard !isDrainingRetries else { return false }
        isDrainingRetries = true
        return true
    }
    mutating func endRetryDrain() { isDrainingRetries = false }
    func canReplay(dayKey: String) -> Bool {
        !uploadingDays.contains(dayKey) && !recoveringDays.contains(dayKey)
    }

    /// Once a write starts, cancellation of a Gallery fetch/debounce must not
    /// release its ordering gate while the server may still apply the request.
    static func runUpload(_ operation: @escaping @Sendable () async -> Void) async {
        await Task { await operation() }.value
    }
}

enum CanvasCloudIdentity {
    static func matches(session: SupabaseSessionResponse?, token: String, userID: String,
                        currentUserID: String?) -> Bool {
        guard let session, currentUserID == userID else { return false }
        return session.user.id == userID && session.accessToken == token
    }
}

enum CanvasUploadSnapshot {
    static func latest(local: DayCanvas?, fallback: SupabaseSyncService.DayCanvasSyncPayload,
                       userID: String) -> SupabaseSyncService.DayCanvasSyncPayload? {
        guard let local else { return fallback }
        guard local.dayKey == fallback.dayKey, !local.needsRemoteHydration,
              local.belongsToCloudUser(userID),
              let json = try? JSONEncoder().encode(local.cloudSnapshot) else { return nil }
        return .init(dayKey: local.dayKey, canvasJsonData: json, lastModified: local.lastModified)
    }
}

struct CanvasQueuedUpload {
    let canvas: DayCanvas
    let ownerUserID: String

    init?(request: SupabasePendingSyncRequest) {
        guard request.method == "POST", URL(string: request.urlString)?.path.hasSuffix("/user_day_canvases") == true,
              let body = request.body,
              let value = try? JSONSerialization.jsonObject(with: body),
              let row = value as? [String: Any],
              let owner = row["user_id"] as? String,
              let json = row["canvas_json"],
              let data = try? JSONSerialization.data(withJSONObject: json),
              let canvas = try? JSONDecoder().decode(DayCanvas.self, from: data) else { return nil }
        self.canvas = canvas
        ownerUserID = owner
    }

    func isSuperseded(by local: DayCanvas?) -> Bool {
        guard let local, local.dayKey == canvas.dayKey, !local.needsRemoteHydration,
              local.localCloudOwnerID == ownerUserID else { return false }
        return local.lastModified >= canvas.lastModified
    }
}

// MARK: - Day Canvas Sync
extension SupabaseSyncService {
    
    /// Sync full DayCanvas to Supabase `user_day_canvases` table.
    /// Stores the entire canvas JSON (elements, palette, shapes) keyed by day.
    func syncDayCanvas(_ canvas: DayCanvas) async {
        await MainActor.run {
            CanvasStorageService.shared.recordCloudUploadIntent(for: canvas.dayKey,
                currentUserID: AuthenticationService.shared.currentUser?.id)
        }
        guard !canvas.needsRemoteHydration else {
            Task { await recoverPendingDayCanvas(for: canvas.dayKey) }
            return
        }
        guard let jsonData = try? JSONEncoder().encode(canvas.cloudSnapshot) else {
            AppLogger.network.error("📡 syncDayCanvas: failed to encode canvas for \(canvas.dayKey)")
            return
        }
        let payload = DayCanvasSyncPayload(
            dayKey: canvas.dayKey,
            canvasJsonData: jsonData,
            lastModified: canvas.lastModified
        )
        
        if payload == pendingDayCanvas { return }
        
        pendingDayCanvas = payload
        dayCanvasSyncTask?.cancel()
        dayCanvasSyncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard let latest = pendingDayCanvas else { return }
            dayCanvasSyncTask = nil
            await CanvasUploadOrdering.runUpload { await self.performDayCanvasSync(payload: latest) }
        }
    }

    /// Includes older offline days: leaving Gallery or crossing midnight must
    /// not strand a draft. Upload each recovery directly rather than feeding
    /// several days through the single-day UI debounce slot.
    func recoverPendingDayCanvases() async {
        let keys = await MainActor.run {
            CanvasStorageService.shared.pendingCloudRecoveryDayKeys()
        }
        for key in keys {
            guard !Task.isCancelled else { return }
            await recoverPendingDayCanvas(for: key)
        }
    }

    func recoverPendingDayCanvas(for dayKey: String) async {
        guard canvasUploadOrdering.beginRecovery(for: dayKey) else { return }
        defer {
            if canvasUploadOrdering.endRecovery(for: dayKey) {
                Task { await recoverPendingDayCanvas(for: dayKey) }
            }
        }
        guard let auth = await authenticatedCanvasContext() else { return }
        guard let initial = await MainActor.run(body: {
            guard Self.canvasAuthIsCurrent(auth),
                  var canvas = CanvasStorageService.shared.loadCanvas(for: dayKey),
                  canvas.belongsToCloudUser(auth.userId) else { return nil as DayCanvas? }
            if canvas.localCloudOwnerID == nil {
                canvas.localCloudOwnerID = auth.userId
                guard CanvasStorageService.shared.saveCanvas(canvas) else { return nil }
            }
            return canvas
        }) else { return }
        if initial.needsRemoteHydration {
            let remote = await fetchDayCanvas(for: dayKey, auth: auth)
            guard !Task.isCancelled else { return }
            let committed = await MainActor.run {
                guard Self.canvasAuthIsCurrent(auth),
                      CanvasStorageService.shared.loadCanvas(for: dayKey)?.localCloudOwnerID == auth.userId else { return false }
                return CanvasStorageService.shared.resolvePendingCanvas(for: dayKey, remote: remote) != nil
            }
            guard committed else { return }
        }
        guard let latest = await MainActor.run(body: {
            CanvasStorageService.shared.loadCanvas(for: dayKey)
        }), !latest.needsRemoteHydration, latest.pendingCloudUpload == true,
              let json = try? JSONEncoder().encode(latest.cloudSnapshot) else { return }
        let payload = DayCanvasSyncPayload(dayKey: dayKey, canvasJsonData: json, lastModified: latest.lastModified)
        await CanvasUploadOrdering.runUpload {
            await self.performDayCanvasSync(payload: payload, expectedUserID: auth.userId)
        }
    }
    
    @MainActor
    private static func canvasAuthIsCurrent(_ auth: AuthContext) -> Bool {
        let service = AuthenticationService.shared
        guard service.isAuthenticated, let data = SessionKeychain.loadSession() else { return false }
        let session = (try? service.supabaseDecoder.decode(SupabaseSessionResponse.self, from: data))
            ?? (try? JSONDecoder().decode(SupabaseSessionResponse.self, from: data))
        return CanvasCloudIdentity.matches(session: session, token: auth.token,
            userID: auth.userId, currentUserID: service.currentUser?.id)
    }

    private func authenticatedCanvasContext() async -> AuthContext? {
        await AuthenticationService.shared.waitForInitialization()
        let expectedUserID = await AuthenticationService.shared.currentUser?.id
        guard let auth = await authenticatedContext(), auth.userId == expectedUserID,
              await Self.canvasAuthIsCurrent(auth) else { return nil }
        return auth
    }

    /// A successful empty response is distinct from every failure path so a
    /// transient fetch problem can never publish an empty Canvas as truth.
    func fetchDayCanvas(for dayKey: String) async -> DayCanvasFetchResult {
        guard let auth = await authenticatedCanvasContext() else { return .failed }
        return await fetchDayCanvas(for: dayKey, auth: auth)
    }

    private func fetchDayCanvas(for dayKey: String, auth: AuthContext) async -> DayCanvasFetchResult {
        guard await Self.canvasAuthIsCurrent(auth) else { return .failed }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_day_canvases")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return .failed }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(dayKey)"),
                URLQueryItem(name: "select", value: "canvas_json"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let url = comps.url else { return .failed }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            
            let (data, response) = try await network.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                AppLogger.network.error("📡 fetchDayCanvas failed: HTTP \(response.statusCode)")
                return .failed
            }

            guard await Self.canvasAuthIsCurrent(auth) else { return .failed }
            let result = DayCanvasFetchResult.decode(
                statusCode: response.statusCode,
                data: data
            )
            if case let .found(canvas) = result {
                AppLogger.network.debug("📡 fetchDayCanvas: restored canvas for \(dayKey) with \(canvas.elements.count) elements")
            }
            return result
        } catch {
            AppLogger.network.error("📡 fetchDayCanvas error: \(error.localizedDescription)")
            return .failed
        }
    }
    
    // MARK: - Private Canvas Sync
    
    private func performDayCanvasSync(payload: DayCanvasSyncPayload, expectedUserID: String? = nil) async {
        guard canvasUploadOrdering.beginUpload(for: payload.dayKey) else { return }
        var succeeded = false
        defer {
            canvasUploadOrdering.endUpload(for: payload.dayKey)
            if pendingDayCanvas == payload { pendingDayCanvas = nil }
            // Edits made while the request was suspended retain their marker.
            // Flush them after a success; failures wait for the next retry trigger.
            if succeeded, canvasUploadOrdering.requestFollowup(for: payload.dayKey) {
                Task { await recoverPendingDayCanvas(for: payload.dayKey) }
            }
        }

        guard let auth = await authenticatedCanvasContext() else {
            AppLogger.network.debug("📡 Day canvas sync skipped: no auth")
            return
        }
        guard expectedUserID == nil || expectedUserID == auth.userId else { return }
        guard let currentPayload = await MainActor.run(body: {
            guard Self.canvasAuthIsCurrent(auth) else { return nil as DayCanvasSyncPayload? }
            return CanvasUploadSnapshot.latest(local: CanvasStorageService.shared.loadCanvas(for: payload.dayKey),
                                               fallback: payload, userID: auth.userId)
        }) else { return }
        let payload = currentPayload
        if Task.isCancelled { return }
        let token = auth.token
        let userId = auth.userId
        
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
                succeeded = true
                lastSentDayCanvas = payload
                await MainActor.run {
                    guard Self.canvasAuthIsCurrent(auth) else { return }
                    CanvasStorageService.shared.acknowledgeCloudUpload(dayKey: payload.dayKey, uploadedJSON: payload.canvasJsonData)
                }
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
