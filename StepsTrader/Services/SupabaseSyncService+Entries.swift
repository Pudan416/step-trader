import Foundation
import os.log

// MARK: - Option Entry Sync
extension SupabaseSyncService {
    
    func syncOptionEntries(_ entries: [OptionEntry]) {
        let payload = entries.sorted(by: { $0.timestamp < $1.timestamp })
        
        entriesSyncTask?.cancel()
        entriesSyncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await performEntriesSync(entries: payload)
        }
    }
    
    private func performEntriesSync(entries: [OptionEntry]) async {
        guard let auth = await authenticatedContext() else { return }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
            guard let url = urlComps.url else { return }
            
            let rows = entries.map { entry in
                OptionEntryUpsertRow(
                    entry: entry,
                    userID: userId,
                    createdAt: iso8601String(entry.timestamp)
                )
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONEncoder().encode(rows)
            
            let (data, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Option entries synced: \(entries.count)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Option entries sync failed: HTTP \(response.statusCode) - \(body)")
                enqueueForRetry(request)
            }
        } catch {
            AppLogger.network.error("📡 Option entries sync error: \(error.localizedDescription)")
        }
    }

    func performEntriesSyncForFullSync(_ entries: [OptionEntry]) async {
        await performEntriesSync(entries: entries)
    }

    /// Syncs one client-identified addition. Upserting by `id` makes retries
    /// idempotent while still allowing the same happening multiple times.
    func syncOptionEntry(_ entry: OptionEntry) async {
        await performEntriesSync(entries: [entry])
    }

    func deleteOptionEntry(id: String) async {
        guard let auth = await authenticatedContext() else { return }
        var pendingRequest: URLRequest?
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            comps.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "user_id", value: "eq.\(auth.userId)")
            ]
            guard let url = comps.url else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "authorization")
            pendingRequest = request
            let (data, response) = try await network.data(for: request)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 Option entry delete failed: HTTP \(response.statusCode)")
                enqueueForRetry(request)
                return
            }
            AppLogger.network.debug("📡 Option entry deleted: \(id, privacy: .public)")
            _ = data
        } catch {
            AppLogger.network.error("📡 Option entry delete error: \(error.localizedDescription)")
            if let pendingRequest { enqueueForRetry(pendingRequest) }
        }
    }
    
    func loadOptionEntriesFromServer(dayKey: String) async -> [OptionEntry]? {
        guard let auth = await authenticatedContext() else { return nil }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_happening_additions")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "day_key", value: "eq.\(dayKey)"),
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
            
            let rows = try JSONDecoder().decode([OptionEntryRow].self, from: data)
            let formatter = ISO8601DateFormatter()
            return rows.map { row in
                OptionEntry(
                    id: row.id,
                    dayKey: row.dayKey,
                    optionId: row.optionId,
                    colorHex: row.colorHex,
                    timestamp: formatter.date(from: row.createdAt) ?? Date.now,
                    assetVariant: row.assetVariant
                )
            }
        } catch {
            AppLogger.network.error("📡 Failed to load option entries: \(error.localizedDescription)")
            return nil
        }
    }
}

struct OptionEntryUpsertRow: Encodable {
    let id: String
    let userID: String
    let dayKey: String
    let optionID: String
    let colorHex: String
    let assetVariant: Int?
    let createdAt: String

    init(entry: OptionEntry, userID: String, createdAt: String) {
        id = entry.id
        self.userID = userID
        dayKey = entry.dayKey
        optionID = entry.optionId
        colorHex = entry.colorHex
        assetVariant = entry.assetVariant
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case dayKey = "day_key"
        case optionID = "option_id"
        case colorHex = "color_hex"
        case assetVariant = "asset_variant"
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(dayKey, forKey: .dayKey)
        try container.encode(optionID, forKey: .optionID)
        try container.encode(colorHex, forKey: .colorHex)
        if let assetVariant {
            try container.encode(assetVariant, forKey: .assetVariant)
        } else {
            try container.encodeNil(forKey: .assetVariant)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct OptionEntryRow: Codable {
    let id: String
    let dayKey: String
    let optionId: String
    let colorHex: String
    let assetVariant: Int?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case dayKey = "day_key"
        case optionId = "option_id"
        case colorHex = "color_hex"
        case assetVariant = "asset_variant"
        case createdAt = "created_at"
    }
}
