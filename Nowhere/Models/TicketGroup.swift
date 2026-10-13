import Foundation
import SwiftUI
import os.log
#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
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
        self.templateApp = templateApp.map(AppLaunchCatalog.canonicalBundleId)
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
        templateApp = try container.decodeIfPresent(String.self, forKey: .templateApp).map(AppLaunchCatalog.canonicalBundleId)
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


/// Shared by the app and widget so names, selectable targets and launch routing
/// always describe the same public app identity.
enum AppLaunchCatalog {
    struct Target {
        let targets: [String]
        let bundleId: String
        let displayName: String
        let scheme: String?
        let fallbackSchemes: [String]
        /// Apple-verified Universal Links (https). Preferred over custom schemes when
        /// re-opening a blocked app: iOS routes them to the exact app that owns the
        /// domain, so a third-party app squatting a custom scheme (e.g. `x://`) can't
        /// intercept them. Empty = no known Universal Link, custom schemes only.
        ///
        /// `var`, not `let`: a `let` with an inline default is dropped from the
        /// memberwise initializer, so entries passing `universalLinks:` wouldn't compile.
        var universalLinks: [String] = []
    }

    static let targets: [Target] = [
        // Grailed's Apple-hosted association file permits /feed/*, not the
        // website root. Use only its verified Universal Link, with no guessed scheme.
        Target(targets: ["grailed"],
                  bundleId: "com.grailed.production",
                  displayName: "Grailed",
                  scheme: nil,
                  fallbackSchemes: [],
                  universalLinks: ["https://www.grailed.com/feed/"]),

        Target(targets: ["instagram"],
                  bundleId: "com.burbn.instagram",
                  displayName: "Instagram",
                  scheme: "instagram://",
                  fallbackSchemes: ["instagram://app", "instagram://", "instagram://feed", "instagram://camera"]),

        Target(targets: ["tiktok"],
                  bundleId: "com.zhiliaoapp.musically",
                  displayName: "TikTok",
                  scheme: "tiktok://",
                  fallbackSchemes: ["tiktok://"]),

        Target(targets: ["youtube"],
                  bundleId: "com.google.ios.youtube",
                  displayName: "YouTube",
                  scheme: "youtube://",
                  fallbackSchemes: ["youtube://"]),

        Target(targets: ["telegram"],
                  bundleId: "ph.telegra.Telegraph",
                  displayName: "Telegram",
                  scheme: "tg://",
                  fallbackSchemes: ["tg://", "telegram://"]),

        Target(targets: ["whatsapp"],
                  bundleId: "net.whatsapp.WhatsApp",
                  displayName: "WhatsApp",
                  scheme: "whatsapp://",
                  fallbackSchemes: ["whatsapp://"]),

        Target(targets: ["snapchat"],
                  bundleId: "com.toyopagroup.picaboo",
                  displayName: "Snapchat",
                  scheme: "snapchat://",
                  fallbackSchemes: ["snapchat://"]),

        Target(targets: ["facebook"],
                  bundleId: "com.facebook.Facebook",
                  displayName: "Facebook",
                  scheme: "fb://",
                  fallbackSchemes: ["fb://", "facebook://"]),

        Target(targets: ["linkedin"],
                  bundleId: "com.linkedin.LinkedIn",
                  displayName: "LinkedIn",
                  scheme: "linkedin://",
                  fallbackSchemes: ["linkedin://"]),

        Target(targets: ["x", "twitter"],
                  bundleId: "com.atebits.Tweetie2",
                  displayName: "X",
                  scheme: "twitter://",
                  // `x://` intentionally removed — it's a generic scheme other apps
                  // (e.g. Standoff 2) register, which hijacked the re-open and launched
                  // the wrong app. Universal Links below open the real X app reliably.
                  fallbackSchemes: ["twitter://"],
                  universalLinks: ["https://x.com", "https://twitter.com"]),

        Target(targets: ["reddit"],
                  bundleId: "com.reddit.Reddit",
                  displayName: "Reddit",
                  scheme: "reddit://",
                  fallbackSchemes: ["reddit://"]),

        Target(targets: ["pinterest"],
                  bundleId: "pinterest",
                  displayName: "Pinterest",
                  scheme: "pinterest://",
                  fallbackSchemes: ["pinterest://"]),

        // Public associated-domain routes. Source links and limits are maintained
        // in docs/architecture/widget-app-opening.md; iOS decides whether the
        // installed app claims the route. Never fall back to Safari.
        Target(targets: ["threads"], bundleId: "com.burbn.barcelona", displayName: "Threads",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.threads.com/"]),
        Target(targets: ["discord"], bundleId: "com.hammerandchisel.discord", displayName: "Discord",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://discord.com/app"]),
        Target(targets: ["twitch"], bundleId: "tv.twitch", displayName: "Twitch",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.twitch.tv/home"]),
        Target(targets: ["bluesky"], bundleId: "xyz.blueskyweb.app", displayName: "Bluesky",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://bsky.app/"]),
        Target(targets: ["spotify"], bundleId: "com.spotify.client", displayName: "Spotify",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://open.spotify.com/home"]),
        Target(targets: ["netflix"], bundleId: "com.netflix.Netflix", displayName: "Netflix",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.netflix.com/browse"]),
        Target(targets: ["youtubemusic"], bundleId: "com.google.ios.youtubemusic", displayName: "YouTube Music",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://music.youtube.com/"]),
        Target(targets: ["temu"], bundleId: "com.einnovation.temu", displayName: "Temu",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.temu.com/?_p_dp=1"]),
        Target(targets: ["shein"], bundleId: "zzkko.com.ZZKKO", displayName: "SHEIN",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://api-shein.shein.com/h5/sharejump/appjump"]),
        Target(targets: ["etsy"], bundleId: "com.etsy.etsyforios", displayName: "Etsy",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.etsy.com/"]),
        Target(targets: ["depop"], bundleId: "com.garageitaly.garage", displayName: "Depop",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.depop.com/"]),
        Target(targets: ["vinted"], bundleId: "lt.manodrabuziai.fr", displayName: "Vinted",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.vinted.com/"]),
        Target(targets: ["stockx"], bundleId: "com.Campless.Campless", displayName: "StockX",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://stockx.com/"]),
        Target(targets: ["goat"], bundleId: "com.airgoat.goat.ios", displayName: "GOAT",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.goat.com/"]),
        Target(targets: ["duolingo"], bundleId: "com.duolingo.DuolingoMobile", displayName: "Duolingo",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://www.duolingo.com/home"]),
        Target(targets: ["tinder"], bundleId: "com.cardify.tinder", displayName: "Tinder",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://go.tinder.com/"]),
        Target(targets: ["bumble"], bundleId: "com.moxco.bumble", displayName: "Bumble",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://bumble.com/nav/"]),
        Target(targets: ["hinge"], bundleId: "co.hinge.mobile.ios", displayName: "Hinge",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://hinge.co/app/"]),
        Target(targets: ["characterai"], bundleId: "ai.character.app", displayName: "Character.AI",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://character.ai/profile/"]),
        Target(targets: ["chatgpt"], bundleId: "com.openai.chat", displayName: "ChatGPT",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://chatgpt.com/open-app"]),
        Target(targets: ["brawlstars"], bundleId: "com.supercell.laser", displayName: "Brawl Stars",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://link.brawlstars.com/"]),
        Target(targets: ["clashroyale"], bundleId: "com.supercell.scroll", displayName: "Clash Royale",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://link.clashroyale.com/"]),
        Target(targets: ["clashofclans"], bundleId: "com.supercell.magic", displayName: "Clash of Clans",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://link.clashofclans.com/"]),
        Target(targets: ["hayday"], bundleId: "com.supercell.soil", displayName: "Hay Day",
               scheme: nil, fallbackSchemes: [], universalLinks: ["https://link.haydaygame.com/"])
    ]

    static func canonicalBundleId(_ bundleId: String) -> String {
        // Preserve associations saved before the public Pinterest ID was corrected.
        bundleId == "com.pinterest" ? "pinterest" : bundleId
    }
}

/// The same group name and scope on every purchase surface, including widgets.
/// A preset must never replace a user's group name.
struct AppGroupIdentity: Equatable {
    let title: String
    let detail: String
    #if canImport(FamilyControls)
    var applicationToken: ApplicationToken? = nil
    #endif

    static let applicationNames = Dictionary(uniqueKeysWithValues:
        AppLaunchCatalog.targets.map { ($0.bundleId, $0.displayName) })

    /// A widget can open a target only when its opaque selection is exactly one
    /// app and that app is one of the launchable targets Nowhere knows how to open.
    /// Family Controls keeps arbitrary application tokens private. Only the
    /// preset or explicit user association identifies an app; editable group names never do.
    static func widgetLaunchBundleId(templateApp: String?, selectionData: Data?) -> String? {
        #if canImport(FamilyControls)
        guard let selectionData,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: selectionData),
              selection.applicationTokens.count == 1,
              selection.categoryTokens.isEmpty,
              selection.webDomainTokens.isEmpty else { return nil }

        if let templateApp {
            let canonical = AppLaunchCatalog.canonicalBundleId(templateApp)
            if applicationNames[canonical] != nil { return canonical }
        }
        return nil
        #else
        return nil
        #endif
    }

    init(name: String, templateApp: String?, applicationCount: Int?, categoryCount: Int = 0, webDomainCount: Int = 0) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = templateApp.flatMap { Self.applicationNames[AppLaunchCatalog.canonicalBundleId($0)] }
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
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           templateApp == nil, let selection, selection.isSingleApplication {
            applicationToken = selection.applicationTokens.first
        }
        #else
        self.init(name: name, templateApp: templateApp, applicationCount: nil)
        #endif
    }
}

extension TicketGroup {
    var displayIdentity: AppGroupIdentity {
        #if canImport(FamilyControls)
        var identity = AppGroupIdentity(name: name, templateApp: templateApp,
                         applicationCount: selection.applicationTokens.count,
                         categoryCount: selection.categoryTokens.count,
                         webDomainCount: selection.webDomainTokens.count)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           templateApp == nil, selection.isSingleApplication {
            identity.applicationToken = selection.applicationTokens.first
        }
        return identity
        #else
        return AppGroupIdentity(name: name, templateApp: templateApp, applicationCount: nil)
        #endif
    }
}

/// Shared by the app and widget: an automatic title is rendered by iOS, never
/// decoded from a private application token or copied into the user's name.
struct AppGroupTitle: View {
    let identity: AppGroupIdentity

    var body: some View {
        #if canImport(FamilyControls)
        if let token = identity.applicationToken {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(identity.title)
        }
        #else
        Text(identity.title)
        #endif
    }
}

#if canImport(FamilyControls)
extension FamilyActivitySelection {
    var isSingleApplication: Bool {
        applicationTokens.count == 1 && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    var hasGroupTargets: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty
    }
}
#endif
