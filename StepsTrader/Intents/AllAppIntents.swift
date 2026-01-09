import AppIntents
import Foundation
import UserNotifications

private func recordJump(for bundleId: String) {
    let defaults = UserDefaults.stepsTrader()
    var logs: [AppModel.AppOpenLog] = []
    if let data = defaults.data(forKey: "appOpenLogs_v1"),
       let decoded = try? JSONDecoder().decode([AppModel.AppOpenLog].self, from: data) {
        logs = decoded
    }
    logs.append(.init(bundleId: bundleId, date: Date()))
    // Trim to avoid unbounded growth
    if logs.count > 500 {
        logs = Array(logs.suffix(500))
    }
    if let data = try? JSONEncoder().encode(logs) {
        defaults.set(data, forKey: "appOpenLogs_v1")
    }
    let name = CFNotificationName("com.steps.trader.logs" as CFString)
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        name,
        nil,
        nil,
        true
    )
}

@available(iOS 17.0, *)
struct TestOneShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "DOOM CTRL: Launcher"
    static var description = IntentDescription(
        "Opens PayGate for a selected app when no access window is active.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let _: AccessWindow = .single
        let selectedTarget: TargetApp = {
            if let saved = userDefaults.string(forKey: "lastCheckedPaygateTarget"),
               let resolved = TargetApp(rawValue: saved) {
                return resolved
            }
            return target
        }()

        // Анти-луп: если окно уже активно — выходим без флагов
        if isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) ?? -1
            print("🚫 TestOneShortcutIntent: blocked until window expires for \(selectedTarget.bundleId) (\(remaining)s left)")
            clearPayGateFlags(userDefaults)
            logCrawl(bundleId: selectedTarget.bundleId, userDefaults: userDefaults)
            return .result(value: true)
        }

        // Анти-спам: не чаще, чем раз в 5 секунд
        if let lastRun = userDefaults.object(forKey: "lastTestOneShortcutRun") as? Date {
            let elapsed = now.timeIntervalSince(lastRun)
            if elapsed < 5 {
                print("🚫 TestOneShortcutIntent: last run \(String(format: "%.1f", elapsed))s ago, skipping")
                return .result(value: false)
            }
        }
        userDefaults.set(now, forKey: "lastTestOneShortcutRun")

        print("🔍 TestOneShortcutIntent triggered for \(selectedTarget.bundleId) at \(Date())")
        userDefaults.set(selectedTarget.urlScheme, forKey: "selectedAppScheme")

        // Запрашиваем показ PayGate в приложении
        userDefaults.set(true, forKey: "shouldShowPayGate")
        userDefaults.set(selectedTarget.bundleId, forKey: "payGateTargetBundleId")
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(selectedTarget.rawValue, forKey: "shortcutTarget")
        userDefaults.set(now, forKey: "shortcutTriggerTime")

        // Уведомляем приложение через Darwin и локальное уведомление
        let notificationName = CFNotificationName("com.steps.trader.paygate" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            ["target": selectedTarget.rawValue, "bundleId": selectedTarget.bundleId] as CFDictionary,
            true
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .init("com.steps.trader.local.paygate"),
                object: nil,
                userInfo: [
                    "target": selectedTarget.rawValue,
                    "bundleId": selectedTarget.bundleId,
                    "action": "paygate"
                ]
            )
        }

        return .result(value: true)
    }
}

@available(iOS 17.0, *)
struct CheckAccessWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "DOOM CTRL: Engine check"
    static var description = IntentDescription(
        "Returns whether PayGate is allowed right now for the selected app (false when paid window is active).")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var target: TargetApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let isBlocked = isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: target.bundleId)
        if isBlocked {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: target.bundleId) ?? -1
            print("🚫 CheckAccessWindowIntent: blocked for \(target.bundleId) (\(remaining)s left)")
            logCrawl(bundleId: target.bundleId, userDefaults: userDefaults)
            return .result(value: false)
        } else {
            userDefaults.set(target.rawValue, forKey: "lastCheckedPaygateTarget")
            print("✅ CheckAccessWindowIntent: allowed for \(target.bundleId)")
            return .result(value: true)
        }
    }
}

@available(iOS 17.0, *)
enum TargetApp: String, AppEnum, CaseDisplayRepresentable {
    case instagram
    case tiktok
    case youtube
    case telegram
    case whatsapp
    case snapchat
    case facebook
    case linkedin
    case x
    case reddit
    case pinterest

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"

    static var caseDisplayRepresentations: [TargetApp: DisplayRepresentation] = [
        .instagram: "📱 Instagram",
        .tiktok: "🎵 TikTok",
        .youtube: "▶️ YouTube",
        .telegram: "✈️ Telegram",
        .whatsapp: "💬 WhatsApp",
        .snapchat: "👻 Snapchat",
        .facebook: "📘 Facebook",
        .linkedin: "💼 LinkedIn",
        .x: "❌ X (Twitter)",
        .reddit: "👽 Reddit",
        .pinterest: "📌 Pinterest",
    ]

    var bundleId: String {
        TargetResolver.bundleId(from: rawValue) ?? rawValue
    }
    
    var urlScheme: String {
        TargetResolver.urlScheme(for: rawValue) ?? ""
    }
}

@available(iOS 17.0, *)
struct StarLauncherIntent: AppIntent {
    static var title: LocalizedStringResource = "*DOOM CTRL: Launcher"
    static var description = IntentDescription(
        "Opens PayGate for a selected app (other apps pool) when no access window is active.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "App")
    var target: TargetOtherApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let _: AccessWindow = .single
        let selectedTarget: TargetOtherApp = {
            if let saved = userDefaults.string(forKey: "lastCheckedPaygateTarget_other"),
               let resolved = TargetOtherApp(rawValue: saved) {
                return resolved
            }
            return target
        }()

        if isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: selectedTarget.bundleId) ?? -1
            print("🚫 StarLauncherIntent: blocked until window expires for \(selectedTarget.bundleId) (\(remaining)s left)")
            clearPayGateFlags(userDefaults)
            logCrawl(bundleId: selectedTarget.bundleId, userDefaults: userDefaults)
            return .result(value: true)
        }

        if let lastRun = userDefaults.object(forKey: "lastStarLauncherRun") as? Date {
            let elapsed = now.timeIntervalSince(lastRun)
            if elapsed < 5 {
                print("🚫 StarLauncherIntent: last run \(String(format: "%.1f", elapsed))s ago, skipping")
                return .result(value: false)
            }
        }
        userDefaults.set(now, forKey: "lastStarLauncherRun")

        print("🔍 StarLauncherIntent triggered for \(selectedTarget.bundleId) at \(Date())")
        userDefaults.set(selectedTarget.urlScheme, forKey: "selectedAppScheme")

        userDefaults.set(true, forKey: "shouldShowPayGate")
        userDefaults.set(selectedTarget.bundleId, forKey: "payGateTargetBundleId")
        userDefaults.set(true, forKey: "shortcutTriggered")
        userDefaults.set(selectedTarget.rawValue, forKey: "shortcutTarget")
        userDefaults.set(now, forKey: "shortcutTriggerTime")

        let notificationName = CFNotificationName("com.steps.trader.paygate" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            ["target": selectedTarget.rawValue, "bundleId": selectedTarget.bundleId] as CFDictionary,
            true
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(
                name: .init("com.steps.trader.local.paygate"),
                object: nil,
                userInfo: [
                    "target": selectedTarget.rawValue,
                    "bundleId": selectedTarget.bundleId,
                    "action": "paygate"
                ]
            )
        }

        return .result(value: true)
    }
}

@available(iOS 17.0, *)
struct StarEngineCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "*SPCE CTRL: Engine check"
    static var description = IntentDescription(
        "Returns whether PayGate is allowed right now for the selected other app (false when paid window is active).")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "App")
    var target: TargetOtherApp

    func perform() async throws -> some ReturnsValue<Bool> & IntentResult {
        let userDefaults = UserDefaults.stepsTrader()
        let now = Date()
        let isBlocked = isWithinBlockWindow(now: now, userDefaults: userDefaults, bundleId: target.bundleId)
        if isBlocked {
            let remaining = remainingBlockSeconds(now: now, userDefaults: userDefaults, bundleId: target.bundleId) ?? -1
            print("🚫 StarEngineCheckIntent: blocked for \(target.bundleId) (\(remaining)s left)")
            logCrawl(bundleId: target.bundleId, userDefaults: userDefaults)
            return .result(value: true)
        } else {
            userDefaults.set(target.rawValue, forKey: "lastCheckedPaygateTarget_other")
            print("✅ StarEngineCheckIntent: allowed for \(target.bundleId)")
            return .result(value: true)
        }
    }
}

@available(iOS 17.0, *)
enum TargetOtherApp: String, AppEnum, CaseDisplayRepresentable {
    case googleMaps
    case waze
    case appleMaps
    case gmail
    case outlook
    case spark
    case yahooMail
    case protonMail
    case slack
    case microsoftTeams
    case zoom
    case webex
    case skype
    case signal
    case viber
    case line
    case weChat
    case kakaoTalk
    case notion
    case trello
    case evernote
    case todoist
    case dropbox
    case googleDrive
    case oneDrive
    case box
    case onePassword
    case nordVPN
    case appleMusic
    case tidal
    case deezer
    case soundCloud
    case shazam
    case audible
    case kindle
    case twitch
    case uber
    case lyft
    case roblox
    case minecraft
    case pubgMobile
    case callOfDutyMobile
    case genshinImpact
    case fortnite
    case fifaMobile
    case clashOfClans
    case clashRoyale
    case brawlStars
    case pokemonGo
    case candyCrush
    case subwaySurfers
    case asphalt9
    case hearthstone
    case wildRift
    case valorant
    case apexLegendsMobile
    case amongUs
    case stumbleGuys
    case mobileLegends
    case freeFire
    case hayDay

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Other App"

    static var caseDisplayRepresentations: [TargetOtherApp: DisplayRepresentation] = [
        .googleMaps: "Google Maps",
        .waze: "Waze",
        .appleMaps: "Apple Maps",
        .gmail: "Gmail",
        .outlook: "Outlook",
        .spark: "Spark",
        .yahooMail: "Yahoo Mail",
        .protonMail: "Proton Mail",
        .slack: "Slack",
        .microsoftTeams: "Microsoft Teams",
        .zoom: "Zoom",
        .webex: "Webex",
        .skype: "Skype",
        .signal: "Signal",
        .viber: "Viber",
        .line: "Line",
        .weChat: "WeChat",
        .kakaoTalk: "KakaoTalk",
        .notion: "Notion",
        .trello: "Trello",
        .evernote: "Evernote",
        .todoist: "Todoist",
        .dropbox: "Dropbox",
        .googleDrive: "Google Drive",
        .oneDrive: "OneDrive",
        .box: "Box",
        .onePassword: "1Password",
        .nordVPN: "NordVPN",
        .appleMusic: "Apple Music",
        .tidal: "Tidal",
        .deezer: "Deezer",
        .soundCloud: "SoundCloud",
        .shazam: "Shazam",
        .audible: "Audible",
        .kindle: "Kindle",
        .twitch: "Twitch",
        .uber: "Uber",
        .lyft: "Lyft",
        .roblox: "Roblox",
        .minecraft: "Minecraft",
        .pubgMobile: "PUBG Mobile",
        .callOfDutyMobile: "Call of Duty Mobile",
        .genshinImpact: "Genshin Impact",
        .fortnite: "Fortnite",
        .fifaMobile: "FIFA Mobile",
        .clashOfClans: "Clash of Clans",
        .clashRoyale: "Clash Royale",
        .brawlStars: "Brawl Stars",
        .pokemonGo: "Pokémon GO",
        .candyCrush: "Candy Crush",
        .subwaySurfers: "Subway Surfers",
        .asphalt9: "Asphalt 9",
        .hearthstone: "Hearthstone",
        .wildRift: "Wild Rift",
        .valorant: "Valorant",
        .apexLegendsMobile: "Apex Legends Mobile",
        .amongUs: "Among Us",
        .stumbleGuys: "Stumble Guys",
        .mobileLegends: "Mobile Legends",
        .freeFire: "Free Fire",
        .hayDay: "Hay Day",
    ]

    var bundleId: String {
        switch self {
        case .googleMaps: return "com.google.Maps"
        case .waze: return "com.waze.iphone"
        case .appleMaps: return "com.apple.Maps"
        case .gmail: return "com.google.Gmail"
        case .outlook: return "com.microsoft.Office.Outlook"
        case .spark: return "com.readdle.smartemail"
        case .yahooMail: return "com.yahoo.Aerogram"
        case .protonMail: return "ch.protonmail.protonmail"
        case .slack: return "com.tinyspeck.chatlyio"
        case .microsoftTeams: return "com.microsoft.skype.teams"
        case .zoom: return "us.zoom.videomeetings"
        case .webex: return "com.cisco.webex.meetings"
        case .skype: return "com.skype.skype"
        case .signal: return "org.whispersystems.signal"
        case .viber: return "com.viber"
        case .line: return "jp.naver.line"
        case .weChat: return "com.tencent.xin"
        case .kakaoTalk: return "com.iwilab.KakaoTalk"
        case .notion: return "notion.id"
        case .trello: return "com.fogcreek.trello"
        case .evernote: return "com.evernote.iPhone.Evernote"
        case .todoist: return "com.todoist.mac.Todoist"
        case .dropbox: return "com.getdropbox.Dropbox"
        case .googleDrive: return "com.google.Drive"
        case .oneDrive: return "com.microsoft.skydrive"
        case .box: return "net.box.BoxNet"
        case .onePassword: return "com.agilebits.onepassword-ios"
        case .nordVPN: return "com.nordvpn.NordVPN"
        case .appleMusic: return "com.apple.Music"
        case .tidal: return "com.aspiro.TIDAL"
        case .deezer: return "com.deezer.Deezer"
        case .soundCloud: return "com.soundcloud.TouchApp"
        case .shazam: return "com.shazam.Shazam"
        case .audible: return "com.audible.iphone"
        case .kindle: return "com.amazon.Lassen"
        case .twitch: return "tv.twitch"
        case .uber: return "com.ubercab.UberClient"
        case .lyft: return "com.zimride.instant"
        case .roblox: return "com.roblox.robloxmobile"
        case .minecraft: return "com.mojang.minecraftpe"
        case .pubgMobile: return "com.tencent.ig"
        case .callOfDutyMobile: return "com.activision.callofduty.shooter"
        case .genshinImpact: return "com.miHoYo.GenshinImpact"
        case .fortnite: return "com.epicgames.fortnite"
        case .fifaMobile: return "com.ea.ios.fifaultimate"
        case .clashOfClans: return "com.supercell.magic"
        case .clashRoyale: return "com.supercell.scroll"
        case .brawlStars: return "com.supercell.brawlstars"
        case .pokemonGo: return "com.nianticlabs.pokemongo"
        case .candyCrush: return "com.midasplayer.apps.candycrushsaga"
        case .subwaySurfers: return "com.kiloo.subwaysurf"
        case .asphalt9: return "com.gameloft.asphalt9"
        case .hearthstone: return "com.blizzard.wtcg.hearthstone"
        case .wildRift: return "com.riotgames.league.wildrift"
        case .valorant: return "com.riotgames.valorant"
        case .apexLegendsMobile: return "com.ea.gp.apexlegendsmobilefps"
        case .amongUs: return "com.innersloth.amongus"
        case .stumbleGuys: return "com.kitkagames.fallbuddies"
        case .mobileLegends: return "com.mobile.legends"
        case .freeFire: return "com.dts.freefireth"
        case .hayDay: return "com.supercell.hayday"
        }
    }
    
    var urlScheme: String {
        switch self {
        case .googleMaps: return "comgooglemaps://"
        case .waze: return "waze://"
        case .appleMaps: return "maps://"
        case .gmail: return "googlegmail://"
        case .outlook: return "ms-outlook://"
        case .spark: return "readdle-spark://"
        case .yahooMail: return "ymail://"
        case .protonMail: return "protonmail://"
        case .slack: return "slack://"
        case .microsoftTeams: return "msteams://"
        case .zoom: return "zoomus://"
        case .webex: return "wbx://"
        case .skype: return "skype://"
        case .signal: return "sgnl://"
        case .viber: return "viber://"
        case .line: return "line://"
        case .weChat: return "weixin://"
        case .kakaoTalk: return "kakaolink://"
        case .notion: return "notion://"
        case .trello: return "trello://"
        case .evernote: return "evernote://"
        case .todoist: return "todoist://"
        case .dropbox: return "dbapi-1://"
        case .googleDrive: return "googledrive://"
        case .oneDrive: return "ms-onedrive://"
        case .box: return "box://"
        case .onePassword: return "onepassword://"
        case .nordVPN: return "nordvpn://"
        case .appleMusic: return "music://"
        case .tidal: return "tidal://"
        case .deezer: return "deezer://"
        case .soundCloud: return "soundcloud://"
        case .shazam: return "shazam://"
        case .audible: return "audible://"
        case .kindle: return "kindle://"
        case .twitch: return "twitch://"
        case .uber: return "uber://"
        case .lyft: return "lyft://"
        case .roblox: return "roblox://"
        case .minecraft: return "minecraft://"
        case .pubgMobile: return "pubgmobile://"
        case .callOfDutyMobile: return "codm://"
        case .genshinImpact: return "yuanshen://"
        case .fortnite: return "fortnite://"
        case .fifaMobile: return "fifamobile://"
        case .clashOfClans: return "clashofclans://"
        case .clashRoyale: return "clashroyale://"
        case .brawlStars: return "brawlstars://"
        case .pokemonGo: return "com.nianticlabs.pokemongo://"
        case .candyCrush: return "candycrushsaga://"
        case .subwaySurfers: return "subwaysurfers://"
        case .asphalt9: return "asphalt9://"
        case .hearthstone: return "hearthstone://"
        case .wildRift: return "lor://"
        case .valorant: return "valorant://"
        case .apexLegendsMobile: return "apexm://"
        case .amongUs: return "amongus://"
        case .stumbleGuys: return "stumbleguys://"
        case .mobileLegends: return "mobilelegends://"
        case .freeFire: return "freefire://"
        case .hayDay: return "hayday://"
        }
    }
}

// MARK: - Window helpers
@available(iOS 17.0, *)
private func blockKey(for bundleId: String) -> String {
    "shortcutBlockUntil_\(bundleId)"
}

@available(iOS 17.0, *)
private func isWithinBlockWindow(now: Date, userDefaults: UserDefaults, bundleId: String) -> Bool {
    guard let until = userDefaults.object(forKey: blockKey(for: bundleId)) as? Date else {
        return false
    }
    if now >= until {
        userDefaults.removeObject(forKey: blockKey(for: bundleId))
        return false
    }
    return true
}

@available(iOS 17.0, *)
private func remainingBlockSeconds(now: Date, userDefaults: UserDefaults, bundleId: String) -> Int? {
    guard let until = userDefaults.object(forKey: blockKey(for: bundleId)) as? Date else { return nil }
    let remaining = Int(until.timeIntervalSince(now))
    return remaining > 0 ? remaining : nil
}

@available(iOS 17.0, *)
private func logCrawl(bundleId: String, userDefaults: UserDefaults) {
    let now = Date()
    // Update last opened
    if let data = userDefaults.data(forKey: "automationLastOpened_v1"),
       var dict = try? JSONDecoder().decode([String: Date].self, from: data) {
        dict[bundleId] = now
        if let encoded = try? JSONEncoder().encode(dict) {
            userDefaults.set(encoded, forKey: "automationLastOpened_v1")
        }
    } else if let encoded = try? JSONEncoder().encode([bundleId: now]) {
        userDefaults.set(encoded, forKey: "automationLastOpened_v1")
    }

    // Mark configured / clear pending
    var configured = userDefaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
    if !configured.contains(bundleId) {
        configured.append(bundleId)
        userDefaults.set(configured, forKey: "automationConfiguredBundles")
    }
    var pending = userDefaults.array(forKey: "automationPendingBundles") as? [String] ?? []
    pending.removeAll { $0 == bundleId }
    userDefaults.set(pending, forKey: "automationPendingBundles")
    if let data = userDefaults.data(forKey: "automationPendingTimestamps_v1"),
       var ts = try? JSONDecoder().decode([String: Date].self, from: data) {
        ts.removeValue(forKey: bundleId)
        if let encoded = try? JSONEncoder().encode(ts) {
            userDefaults.set(encoded, forKey: "automationPendingTimestamps_v1")
        }
    }

    // Append app open log
    var logs: [AppModel.AppOpenLog] = []
    if let data = userDefaults.data(forKey: "appOpenLogs_v1"),
       let decoded = try? JSONDecoder().decode([AppModel.AppOpenLog].self, from: data) {
        logs = decoded
    }
    logs.append(AppModel.AppOpenLog(bundleId: bundleId, date: now))
    if let encoded = try? JSONEncoder().encode(logs) {
        userDefaults.set(encoded, forKey: "appOpenLogs_v1")
    }
}


@available(iOS 17.0, *)
private func blockUntilDate(from now: Date, window: AccessWindow, userDefaults: UserDefaults, bundleId: String) -> Date? {
    switch window {
    case .single:
        return now.addingTimeInterval(10)
    case .minutes5:
        return now.addingTimeInterval(5 * 60)
    case .hour1:
        return now.addingTimeInterval(60 * 60)
    case .day1:
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        if let endOfDay = cal.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) {
            return endOfDay
        }
        return now.addingTimeInterval(24 * 60 * 60)
    }
}

@available(iOS 17.0, *)
private func clearPayGateFlags(_ userDefaults: UserDefaults) {
    userDefaults.removeObject(forKey: "shouldShowPayGate")
    userDefaults.removeObject(forKey: "payGateTargetBundleId")
    userDefaults.removeObject(forKey: "shortcutTriggered")
    userDefaults.removeObject(forKey: "shortcutTarget")
    userDefaults.removeObject(forKey: "shortcutTriggerTime")
}

// MARK: - AccessWindow AppIntents plumbing
@available(iOS 17.0, *)
extension AccessWindow: AppEnum, CaseDisplayRepresentable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Access window"
    static var caseDisplayRepresentations: [AccessWindow: DisplayRepresentation] = [
        .single: "🔓 Один раз",
        .minutes5: "⏱️ 5 минут",
        .hour1: "🕐 1 час",
        .day1: "🌞 До конца дня"
    ]
}
