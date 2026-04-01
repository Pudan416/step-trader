import Foundation
import os.log

// MARK: - Option Entry Sync
extension SupabaseSyncService {
    
    func syncOptionEntries(_ entries: [OptionEntry]) {
        let payload = entries.sorted(by: { $0.optionId < $1.optionId })
        
        entriesSyncTask?.cancel()
        entriesSyncTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await performEntriesSync(entries: payload)
        }
    }
    
    private func performEntriesSync(entries: [OptionEntry]) async {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else { return }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_option_entries")
            guard var urlComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            urlComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,day_key,option_id")]
            guard let url = urlComps.url else { return }
            
            let rows: [[String: Any]] = entries.map { entry in
                var row: [String: Any] = [
                    "user_id": userId,
                    "day_key": entry.dayKey,
                    "option_id": entry.optionId,
                    "category": entry.category.rawValue,
                    "color_hex": entry.colorHex,
                    "note": entry.text,
                    "created_at": iso8601String(entry.timestamp)
                ]
                if let variant = entry.assetVariant {
                    row["asset_variant"] = variant
                }
                return row
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: rows)
            
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
    
    func loadOptionEntriesFromServer(dayKey: String) async -> [OptionEntry]? {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else { return nil }
        
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/user_option_entries")
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
            return rows.map { row in
                OptionEntry(
                    id: "\(row.optionId)_\(row.dayKey)",
                    dayKey: row.dayKey,
                    optionId: row.optionId,
                    category: EnergyCategory(rawValue: row.category) ?? .body,
                    colorHex: row.colorHex,
                    text: row.note,
                    timestamp: ISO8601DateFormatter().date(from: row.createdAt) ?? Date(),
                    assetVariant: row.assetVariant
                )
            }
        } catch {
            AppLogger.network.error("📡 Failed to load option entries: \(error.localizedDescription)")
            return nil
        }
    }
}

private struct OptionEntryRow: Codable {
    let dayKey: String
    let optionId: String
    let category: String
    let colorHex: String
    let note: String
    let assetVariant: Int?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case dayKey = "day_key"
        case optionId = "option_id"
        case category
        case colorHex = "color_hex"
        case note
        case assetVariant = "asset_variant"
        case createdAt = "created_at"
    }
}
