import Foundation
import os.log

// MARK: - Saved Routines Sync
extension SupabaseSyncService {

    func syncSavedRoutines(_ routines: [EnergyRoutine]) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await performSavedRoutinesSync(routines)
        }
    }

    private func performSavedRoutinesSync(_ routines: [EnergyRoutine]) async {
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Routines sync skipped: no auth")
            return
        }
        let token = auth.token
        let userId = auth.userId

        do {
            let cfg = try SupabaseConfig.load()

            if routines.isEmpty {
                let deleteURL = cfg.baseURL.appendingPathComponent("rest/v1/user_routines")
                guard var comps = URLComponents(url: deleteURL, resolvingAgainstBaseURL: false) else { return }
                comps.queryItems = [URLQueryItem(name: "user_id", value: "eq.\(userId)")]
                guard let url = comps.url else { return }

                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")

                let (_, response) = try await network.data(for: request)
                if response.statusCode < 400 {
                    AppLogger.network.debug("📡 Routines cleared on server")
                }
                return
            }

            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_routines")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            comps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,routine_id")]
            guard let url = comps.url else { return }

            let rows: [[String: Any]] = routines.map { routine in
                var row: [String: Any] = [
                    "user_id": userId,
                    "routine_id": routine.id,
                    "name": routine.name,
                    "body_ids": routine.bodyIds,
                    "mind_ids": routine.mindIds,
                    "heart_ids": routine.heartIds
                ]
                if let lastUsed = routine.lastUsed {
                    row["last_used"] = iso8601String(lastUsed)
                }
                return row
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: rows)

            let (data, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                // Delete stale routines no longer in local set
                let currentIds = Set(routines.map(\.id))
                let idList = currentIds.joined(separator: ",")
                let delEndpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_routines")
                guard var delComps = URLComponents(url: delEndpoint, resolvingAgainstBaseURL: false) else { return }
                delComps.queryItems = [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "routine_id", value: "not.in.(\(idList))")
                ]
                guard let delURL = delComps.url else { return }
                var delReq = URLRequest(url: delURL)
                delReq.httpMethod = "DELETE"
                delReq.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
                delReq.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                _ = try? await network.data(for: delReq)

                AppLogger.network.debug("📡 Routines synced: \(routines.count) items")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Routines sync failed: HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Routines sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore

    func loadSavedRoutinesFromServer() async -> [EnergyRoutine]? {
        guard let auth = await authenticatedContext() else { return nil }
        let token = auth.token
        let userId = auth.userId

        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_routines")
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

            let rows = try JSONDecoder().decode([RoutineRow].self, from: data)
            AppLogger.network.debug("📡 Loaded \(rows.count) routines from server")

            let formatter = ISO8601DateFormatter()
            return rows.map { row in
                EnergyRoutine(
                    id: row.routineId,
                    name: row.name,
                    bodyIds: row.bodyIds,
                    mindIds: row.mindIds,
                    heartIds: row.heartIds,
                    lastUsed: row.lastUsed.flatMap { formatter.date(from: $0) }
                )
            }
        } catch {
            AppLogger.network.error("📡 Failed to load routines: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct RoutineRow: Codable {
    let routineId: String
    let name: String
    let bodyIds: [String]
    let mindIds: [String]
    let heartIds: [String]
    let lastUsed: String?

    enum CodingKeys: String, CodingKey {
        case routineId = "routine_id"
        case name
        case bodyIds = "body_ids"
        case mindIds = "mind_ids"
        case heartIds = "heart_ids"
        case lastUsed = "last_used"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        routineId = try c.decode(String.self, forKey: .routineId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        bodyIds = try c.decodeIfPresent([String].self, forKey: .bodyIds) ?? []
        mindIds = try c.decodeIfPresent([String].self, forKey: .mindIds) ?? []
        heartIds = try c.decodeIfPresent([String].self, forKey: .heartIds) ?? []
        lastUsed = try c.decodeIfPresent(String.self, forKey: .lastUsed)
    }
}
