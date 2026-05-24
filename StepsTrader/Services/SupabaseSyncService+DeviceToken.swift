import Foundation
import os.log

extension SupabaseSyncService {

    func registerDeviceToken(_ tokenHex: String) async {
        guard let auth = await authenticatedContext() else {
            AppLogger.network.debug("📡 Device token sync skipped: no auth")
            return
        }

        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/device_tokens")

            let body: [String: Any] = [
                "user_id": auth.userId,
                "token": tokenHex,
                "platform": "ios",
                "updated_at": iso8601String(Date.now)
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            // Upsert on token uniqueness — update updated_at if already exists
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await network.data(for: request)
            if response.statusCode < 400 {
                AppLogger.network.debug("📡 Device token registered successfully")
            } else {
                AppLogger.network.error("📡 Device token registration failed: \(response.statusCode)")
            }
        } catch {
            AppLogger.network.error("📡 Device token registration error: \(error.localizedDescription)")
        }
    }

    func removeDeviceToken(_ tokenHex: String) async {
        guard let auth = await authenticatedContext() else { return }

        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/device_tokens")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            comps.queryItems = [
                URLQueryItem(name: "token", value: "eq.\(tokenHex)"),
                URLQueryItem(name: "user_id", value: "eq.\(auth.userId)")
            ]
            guard let deleteURL = comps.url else { return }

            var request = URLRequest(url: deleteURL)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")

            let (_, response) = try await network.data(for: request)
            AppLogger.network.debug("📡 Device token removed: \(response.statusCode)")
        } catch {
            AppLogger.network.error("📡 Device token removal error: \(error.localizedDescription)")
        }
    }
}
