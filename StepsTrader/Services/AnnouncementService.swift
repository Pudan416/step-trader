import Foundation

struct AppAnnouncement: Decodable, Identifiable {
    let id: String
    let title: String
    let message: String
    let created_at: String
}

@MainActor
final class AnnouncementService: ObservableObject {
    static let shared = AnnouncementService()

    @Published var activeAnnouncement: AppAnnouncement?

    private let dismissedKey = "dismissedAnnouncementIds"
    private let network = NetworkClient.shared

    func fetchActiveAnnouncement() async {
        do {
            let cfg = try SupabaseConfig.load()
            let url = cfg.baseURL.appendingPathComponent("rest/v1/app_announcements")
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            comps.queryItems = [
                URLQueryItem(name: "is_active", value: "eq.true"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "1")
            ]
            guard let requestURL = comps.url else { return }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await network.data(for: request, policy: .none)
            guard response.statusCode < 400 else { return }

            let announcements = try JSONDecoder().decode([AppAnnouncement].self, from: data)
            guard let latest = announcements.first else {
                activeAnnouncement = nil
                return
            }

            let dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
            if dismissed.contains(latest.id) {
                activeAnnouncement = nil
            } else {
                activeAnnouncement = latest
            }
        } catch {
            AppLogger.network.error("📡 Announcement fetch error: \(error.localizedDescription)")
        }
    }

    func dismiss(_ announcement: AppAnnouncement) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        if !dismissed.contains(announcement.id) {
            dismissed.append(announcement.id)
            if dismissed.count > 50 {
                dismissed = Array(dismissed.suffix(20))
            }
            UserDefaults.standard.set(dismissed, forKey: dismissedKey)
        }
        activeAnnouncement = nil
    }
}
