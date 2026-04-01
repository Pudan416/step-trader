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
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            guard !Task.isCancelled else { return }
            let latest = pendingTicketGroupsPayload
            await performTicketGroupsSync(rows: latest)
        }
    }
    
    /// Delete a single ticket/shield row for current user and bundle id.
    func deleteTicket(bundleId: String) async {
        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Ticket delete skipped: no auth")
            return
        }

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

        await AuthenticationService.shared.waitForInitialization()
        guard let token = await AuthenticationService.shared.accessToken,
              let userId = await AuthenticationService.shared.currentUser?.id else {
            AppLogger.network.debug("📡 Ticket groups sync skipped: no auth")
            return
        }

        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/shields")

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

            let (deleteData, deleteResponse) = try await network.data(for: deleteRequest)
            guard deleteResponse.statusCode < 400 else {
                let body = String(data: deleteData, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket groups delete-before-insert failed: HTTP \(deleteResponse.statusCode) - \(body)")
                return
            }

            if rows.isEmpty {
                lastSentTicketGroupsPayload = []
                AppLogger.network.debug("📡 Ticket groups synced: cleared")
                return
            }

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

            var insertRequest = URLRequest(url: endpoint)
            insertRequest.httpMethod = "POST"
            insertRequest.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            insertRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            insertRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            insertRequest.setValue("return=minimal", forHTTPHeaderField: "prefer")
            insertRequest.httpBody = try JSONEncoder().encode(payload)

            let (insertData, insertResponse) = try await network.data(for: insertRequest)
            if insertResponse.statusCode < 400 {
                lastSentTicketGroupsPayload = rows
                AppLogger.network.debug("📡 Ticket groups synced: \(rows.count) rows")
            } else {
                let body = String(data: insertData, encoding: .utf8) ?? "no body"
                AppLogger.network.error("📡 Ticket groups insert failed: HTTP \(insertResponse.statusCode) - \(body)")
            }
        } catch {
            AppLogger.network.error("📡 Ticket groups sync error: \(error.localizedDescription)")
        }
    }
}
