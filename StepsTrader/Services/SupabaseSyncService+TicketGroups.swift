import Foundation
import os.log

// MARK: - Ticket Groups Sync
extension SupabaseSyncService {
    
    /// Sync ticket groups to Supabase `shields` table.
    /// Stores each ticket group as a synthetic `bundle_id` (`group:<groupId>`) row.
    func syncTicketGroups(_ groups: [TicketGroup]) {
        let rows = groups
            .map { TicketGroupSyncRow.from(group: $0) }
            .sorted { $0.bundleId < $1.bundleId }

        if rows == pendingTicketGroupsPayload { return }
        if rows == lastSentTicketGroupsPayload {
            pendingTicketGroupsPayload = []
            ticketGroupsSyncTask?.cancel()
            return
        }

        pendingTicketGroupsPayload = rows
        ticketGroupsSyncTask?.cancel()
        ticketGroupsSyncTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let latest = pendingTicketGroupsPayload
            await performTicketGroupsSync(rows: latest)
        }
    }
    
    /// Delete a single ticket/shield row for current user and bundle id.
    func deleteTicket(bundleId: String) async {
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Ticket delete skipped: no auth")
            return
        }
        let token = auth.token
        let userId = auth.userId

        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/shields")
            guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
                AppLogger.network.error("📡 Ticket delete failed: invalid endpoint")
                return
            }
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "bundle_id", value: "eq.\(bundleId)")
            ]

            guard let url = comps.url else {
                AppLogger.network.error("📡 Ticket delete failed: invalid URL components")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("return=minimal", forHTTPHeaderField: "prefer")

            let (data, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Ticket deleted for bundleId=\(bundleId)")
            } else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket delete failed for bundleId=\(bundleId): HTTP \(response.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Ticket delete error for bundleId=\(bundleId): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Perform Ticket Groups Sync
    
    func performTicketGroupsSync(rows: [TicketGroupSyncRow]) async {
        defer {
            if pendingTicketGroupsPayload == rows {
                pendingTicketGroupsPayload = []
            }
        }

        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Ticket groups sync skipped: no auth")
            return
        }
        let token = auth.token
        let userId = auth.userId

        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/shields")

            // If rows is empty, just delete all group rows and return.
            if rows.isEmpty {
                guard var deleteComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
                deleteComps.queryItems = [
                    URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                    URLQueryItem(name: "bundle_id", value: "like.group:%")
                ]
                guard let deleteURL = deleteComps.url else { return }

                var deleteRequest = URLRequest(url: deleteURL)
                deleteRequest.httpMethod = "DELETE"
                deleteRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
                deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                deleteRequest.setValue("return=minimal", forHTTPHeaderField: "prefer")

                let (_, deleteResponse) = try await network.data(for: deleteRequest)
                if deleteResponse.statusCode < 400 {
                    lastSentTicketGroupsPayload = []
                    AppLogger.network.debug("📡 Ticket groups synced: cleared")
                }
                return
            }

            // Upsert all current rows (atomic — no gap between delete and insert)
            let payload = rows.map { row -> TicketGroupSyncInsertRow in
                let settingsDict: [String: AnyCodableValue]?
                if let obj = try? JSONSerialization.jsonObject(with: row.settingsJson) as? [String: Any] {
                    var dict: [String: AnyCodableValue] = [:]
                    for (k, v) in obj {
                        if let i = v as? Int { dict[k] = .int(i) }
                        else if let b = v as? Bool { dict[k] = .bool(b) }
                        else if let s = v as? String { dict[k] = .string(s) }
                        else if let a = v as? [String] { dict[k] = .array(a) }
                    }
                    settingsDict = dict
                } else {
                    settingsDict = nil
                }
                return TicketGroupSyncInsertRow(
                    userId: userId,
                    bundleId: row.bundleId,
                    mode: row.mode,
                    name: row.name,
                    templateApp: row.templateApp,
                    stickerThemeIndex: row.stickerThemeIndex,
                    enabledIntervals: row.enabledIntervals,
                    settingsJson: settingsDict
                )
            }

            guard var upsertComps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
            upsertComps.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,bundle_id")]
            guard let upsertURL = upsertComps.url else { return }

            var upsertRequest = URLRequest(url: upsertURL)
            upsertRequest.httpMethod = "POST"
            upsertRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            upsertRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            upsertRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            upsertRequest.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "prefer")
            upsertRequest.httpBody = try JSONEncoder().encode(payload)

            let (upsertData, upsertResponse) = try await network.data(for: upsertRequest)
            if upsertResponse.statusCode < 400 {
                // Clean up stale rows that no longer exist locally
                let currentBundleIds = Set(rows.map(\.bundleId))
                if let lastSent = lastSentTicketGroupsPayload as [TicketGroupSyncRow]? {
                    let removed = lastSent.filter { !currentBundleIds.contains($0.bundleId) }
                    for stale in removed {
                        await deleteTicket(bundleId: stale.bundleId)
                    }
                }
                lastSentTicketGroupsPayload = rows
                AppLogger.network.debug("📡 Ticket groups synced: \(rows.count) rows (upsert)")
            } else {
                let body = String(data: upsertData, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket groups upsert failed: HTTP \(upsertResponse.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Ticket groups sync error: \(error.localizedDescription)")
        }
    }
}
