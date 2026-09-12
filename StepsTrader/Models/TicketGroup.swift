import Foundation
import os.log
#if canImport(FamilyControls)
import FamilyControls
#endif

struct TicketGroup: Identifiable, Codable {
    let id: String
    var name: String
    var selection: FamilyActivitySelection
    var settings: AppUnlockSettings
    var enabledIntervals: Set<AccessWindow> = [.minutes10, .minutes30, .hour1]
    var templateApp: String? = nil
    var stickerThemeIndex: Int = 0

    init(id: String = UUID().uuidString, name: String, selection: FamilyActivitySelection = FamilyActivitySelection(), settings: AppUnlockSettings, enabledIntervals: Set<AccessWindow> = [.minutes10, .minutes30, .hour1], templateApp: String? = nil, stickerThemeIndex: Int = 0) {
        self.id = id
        self.name = name
        self.selection = selection
        self.settings = settings
        self.enabledIntervals = enabledIntervals
        self.templateApp = templateApp
        self.stickerThemeIndex = stickerThemeIndex
    }

    static func cost(for interval: AccessWindow) -> Int {
        let baseCosts: [AccessWindow: Int] = [
            .minutes10: 4,
            .minutes30: 10,
            .hour1: 20
        ]
        return baseCosts[interval] ?? 5
    }

    func cost(for interval: AccessWindow) -> Int {
        Self.cost(for: interval)
    }

    // Custom Codable implementation for FamilyActivitySelection
    enum CodingKeys: String, CodingKey {
        case id, name, selectionData, settings, enabledIntervals, templateApp, stickerThemeIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(AppUnlockSettings.self, forKey: .settings)

        if let rawArray = try? container.decodeIfPresent([String].self, forKey: .enabledIntervals) {
            enabledIntervals = Set(rawArray.compactMap { AccessWindow(rawValue: $0) })
        }
        if enabledIntervals.isEmpty {
            enabledIntervals = [.minutes10, .minutes30, .hour1]
        }
        templateApp = try container.decodeIfPresent(String.self, forKey: .templateApp)
        stickerThemeIndex = try container.decodeIfPresent(Int.self, forKey: .stickerThemeIndex) ?? 0

        #if canImport(FamilyControls)
        if let data = try? container.decode(Data.self, forKey: .selectionData),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        } else {
            selection = FamilyActivitySelection()
        }
        #else
        selection = FamilyActivitySelection()
        #endif
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(settings, forKey: .settings)
        try container.encode(enabledIntervals, forKey: .enabledIntervals)
        try container.encodeIfPresent(templateApp, forKey: .templateApp)
        try container.encode(stickerThemeIndex, forKey: .stickerThemeIndex)

        #if canImport(FamilyControls)
        do {
            let data = try JSONEncoder().encode(selection)
            try container.encode(data, forKey: .selectionData)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader", category: "FamilyControls")
                .error("Failed to encode selection for group \(id): \(error.localizedDescription)")
        }
        #endif
    }
}


/// The same group name and scope on every purchase surface, including widgets.
/// A preset must never replace a user's group name.
struct AppGroupIdentity: Equatable {
    let title: String
    let detail: String

    static let applicationNames: [String: String] = [
        "com.burbn.instagram": "Instagram", "com.zhiliaoapp.musically": "TikTok",
        "com.google.ios.youtube": "YouTube", "com.toyopagroup.picaboo": "Snapchat",
        "com.reddit.Reddit": "Reddit", "com.atebits.Tweetie2": "X",
        "com.facebook.Facebook": "Facebook", "com.linkedin.LinkedIn": "LinkedIn",
        "com.pinterest": "Pinterest", "ph.telegra.Telegraph": "Telegram",
        "net.whatsapp.WhatsApp": "WhatsApp"
    ]

    init(name: String, templateApp: String?, applicationCount: Int?, categoryCount: Int = 0, webDomainCount: Int = 0) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = templateApp.flatMap { Self.applicationNames[$0] }
        title = name.isEmpty ? (app ?? String(localized: "App group")) : name
        if let app, app != title {
            detail = app
        } else if templateApp != nil {
            detail = String(localized: "1 app")
        } else {
            var parts: [String] = []
            if let count = applicationCount, count > 0 {
                parts.append(count == 1 ? String(localized: "1 app") : String(localized: "\(count) apps"))
            }
            if categoryCount > 0 {
                parts.append(categoryCount == 1 ? String(localized: "1 category") : String(localized: "\(categoryCount) categories"))
            }
            if webDomainCount > 0 {
                parts.append(webDomainCount == 1 ? String(localized: "1 website") : String(localized: "\(webDomainCount) websites"))
            }
            detail = parts.isEmpty ? String(localized: "App group") : parts.joined(separator: " · ")
        }
    }

    init(name: String, templateApp: String?, selectionData: Data?) {
        #if canImport(FamilyControls)
        let selection = selectionData.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) }
        self.init(name: name, templateApp: templateApp,
                  applicationCount: selection?.applicationTokens.count,
                  categoryCount: selection?.categoryTokens.count ?? 0,
                  webDomainCount: selection?.webDomainTokens.count ?? 0)
        #else
        self.init(name: name, templateApp: templateApp, applicationCount: nil)
        #endif
    }
}

extension TicketGroup {
    var displayIdentity: AppGroupIdentity {
        #if canImport(FamilyControls)
        return AppGroupIdentity(name: name, templateApp: templateApp,
                         applicationCount: selection.applicationTokens.count,
                         categoryCount: selection.categoryTokens.count,
                         webDomainCount: selection.webDomainTokens.count)
        #else
        return AppGroupIdentity(name: name, templateApp: templateApp, applicationCount: nil)
        #endif
    }
}
