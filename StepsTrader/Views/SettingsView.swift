import SwiftUI
import UIKit

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    private var tariffs: [Tariff] { Tariff.allCases }
    
    // Popular apps list reused across the app
    static let automationAppsStatic: [AutomationApp] = [
        .init(name: "YouTube", scheme: "youtube://", icon: "▶️", imageName: "youtube", link: "https://www.icloud.com/shortcuts/38c0a69461e544aea9b09fbe370f0023", bundleId: "com.google.ios.youtube"),
        .init(name: "Instagram", scheme: "instagram://", icon: "📸", imageName: "instagram", link: "https://www.icloud.com/shortcuts/fe70c69ad493452c80fb68e06d0f6f80", bundleId: "com.burbn.instagram"),
        .init(name: "TikTok", scheme: "tiktok://", icon: "🎵", imageName: "tiktok", link: "https://www.icloud.com/shortcuts/d4de1bb8470b46c9b2892451c6780638", bundleId: "com.zhiliaoapp.musically"),
        .init(name: "Telegram", scheme: "tg://", icon: "✈️", imageName: "telegram", link: "https://www.icloud.com/shortcuts/d6a413d544c44823aa4833a0d7660a1b", bundleId: "ph.telegra.Telegraph"),
        .init(name: "WhatsApp", scheme: "whatsapp://", icon: "💬", imageName: "whatsapp", link: "https://www.icloud.com/shortcuts/5da3f8a981994af4bfda1f56bc617ed3", bundleId: "net.whatsapp.WhatsApp"),
        .init(name: "Snapchat", scheme: "snapchat://", icon: "👻", imageName: "snapchat", link: "https://www.icloud.com/shortcuts/d1b2814d94124c58a02eccee8e414f1e", bundleId: "com.toyopagroup.picaboo"),
        .init(name: "Facebook", scheme: "fb://", icon: "📘", imageName: "facebook", link: "https://www.icloud.com/shortcuts/592b0f5deec04338a878f59f7ac2c196", bundleId: "com.facebook.Facebook"),
        .init(name: "LinkedIn", scheme: "linkedin://", icon: "💼", imageName: "linkedin", link: "https://www.icloud.com/shortcuts/18a05ebbf8c2476ebd71501c3a3df5f1", bundleId: "com.linkedin.LinkedIn"),
        .init(name: "X (Twitter)", scheme: "twitter://", icon: "🐦", imageName: "x", link: "https://www.icloud.com/shortcuts/541a0884df234c33877465c96ac16724", bundleId: "com.atebits.Tweetie2"),
        .init(name: "Reddit", scheme: "reddit://", icon: "👽", imageName: "reddit", link: "https://www.icloud.com/shortcuts/a42f97e52f4341d887ef83dc87b1a154", bundleId: "com.reddit.Reddit"),
        .init(name: "Pinterest", scheme: "pinterest://", icon: "📌", imageName: "pinterest", link: "https://www.icloud.com/shortcuts/bf2079f1a4bc40c7a81199e632fbc7f3", bundleId: "com.pinterest"),
        
        // Other apps pool
        .init(name: "Google Maps", scheme: "comgooglemaps://", icon: "🗺️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.google.Maps", category: .other),
        .init(name: "Waze", scheme: "waze://", icon: "🚗", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.waze.iphone", category: .other),
        .init(name: "Apple Maps", scheme: "maps://", icon: "🧭", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.apple.Maps", category: .other),
        .init(name: "Gmail", scheme: "googlegmail://", icon: "✉️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.google.Gmail", category: .other),
        .init(name: "Outlook", scheme: "ms-outlook://", icon: "📧", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.microsoft.Office.Outlook", category: .other),
        .init(name: "Spark", scheme: "readdle-spark://", icon: "⚡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.readdle.smartemail", category: .other),
        .init(name: "Yahoo Mail", scheme: "ymail://", icon: "💌", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.yahoo.Aerogram", category: .other),
        .init(name: "Proton Mail", scheme: "protonmail://", icon: "🔐", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "ch.protonmail.protonmail", category: .other),
        .init(name: "Slack", scheme: "slack://", icon: "💬", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.tinyspeck.chatlyio", category: .other),
        .init(name: "Microsoft Teams", scheme: "msteams://", icon: "👥", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.microsoft.skype.teams", category: .other),
        .init(name: "Zoom", scheme: "zoomus://", icon: "🎥", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "us.zoom.videomeetings", category: .other),
        .init(name: "Webex", scheme: "wbx://", icon: "🌀", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.cisco.webex.meetings", category: .other),
        .init(name: "Skype", scheme: "skype://", icon: "📞", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.skype.skype", category: .other),
        .init(name: "Signal", scheme: "sgnl://", icon: "🔵", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "org.whispersystems.signal", category: .other),
        .init(name: "Viber", scheme: "viber://", icon: "📱", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.viber", category: .other),
        .init(name: "Line", scheme: "line://", icon: "💬", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "jp.naver.line", category: .other),
        .init(name: "WeChat", scheme: "weixin://", icon: "🟩", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.tencent.xin", category: .other),
        .init(name: "KakaoTalk", scheme: "kakaolink://", icon: "🟡", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.iwilab.KakaoTalk", category: .other),
        .init(name: "Notion", scheme: "notion://", icon: "📓", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "notion.id", category: .other),
        .init(name: "Trello", scheme: "trello://", icon: "🗂️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.fogcreek.trello", category: .other),
        .init(name: "Evernote", scheme: "evernote://", icon: "🟢", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.evernote.iPhone.Evernote", category: .other),
        .init(name: "Todoist", scheme: "todoist://", icon: "✅", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.todoist.mac.Todoist", category: .other),
        .init(name: "Dropbox", scheme: "dbapi-1://", icon: "📦", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.getdropbox.Dropbox", category: .other),
        .init(name: "Google Drive", scheme: "googledrive://", icon: "🟢", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.google.Drive", category: .other),
        .init(name: "OneDrive", scheme: "ms-onedrive://", icon: "☁️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.microsoft.skydrive", category: .other),
        .init(name: "Box", scheme: "box://", icon: "📁", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "net.box.BoxNet", category: .other),
        .init(name: "1Password", scheme: "onepassword://", icon: "🛡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.agilebits.onepassword-ios", category: .other),
        .init(name: "NordVPN", scheme: "nordvpn://", icon: "🧭", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.nordvpn.NordVPN", category: .other),
        .init(name: "Apple Music", scheme: "music://", icon: "🎵", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.apple.Music", category: .other),
        .init(name: "Tidal", scheme: "tidal://", icon: "🌊", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.aspiro.TIDAL", category: .other),
        .init(name: "Deezer", scheme: "deezer://", icon: "🎶", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.deezer.Deezer", category: .other),
        .init(name: "SoundCloud", scheme: "soundcloud://", icon: "☁️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.soundcloud.TouchApp", category: .other),
        .init(name: "Shazam", scheme: "shazam://", icon: "🔎", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.shazam.Shazam", category: .other),
        .init(name: "Audible", scheme: "audible://", icon: "🎧", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.audible.iphone", category: .other),
        .init(name: "Kindle", scheme: "kindle://", icon: "📚", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.amazon.Lassen", category: .other),
        .init(name: "Twitch", scheme: "twitch://", icon: "🟣", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "tv.twitch", category: .other),
        .init(name: "Uber", scheme: "uber://", icon: "🚕", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.ubercab.UberClient", category: .other),
        .init(name: "Lyft", scheme: "lyft://", icon: "🚙", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.zimride.instant", category: .other),
        .init(name: "Roblox", scheme: "roblox://", icon: "🎮", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.roblox.robloxmobile", category: .other),
        .init(name: "Minecraft", scheme: "minecraft://", icon: "⛏️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.mojang.minecraftpe", category: .other),
        .init(name: "PUBG Mobile", scheme: "pubgmobile://", icon: "⚔️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.tencent.ig", category: .other),
        .init(name: "Call of Duty Mobile", scheme: "codm://", icon: "🎯", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.activision.callofduty.shooter", category: .other),
        .init(name: "Genshin Impact", scheme: "yuanshen://", icon: "🌌", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.miHoYo.GenshinImpact", category: .other),
        .init(name: "Fortnite", scheme: "fortnite://", icon: "🛡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.epicgames.fortnite", category: .other),
        .init(name: "FIFA Mobile", scheme: "fifamobile://", icon: "⚽️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.ea.ios.fifaultimate", category: .other),
        .init(name: "Clash of Clans", scheme: "clashofclans://", icon: "🛡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.supercell.magic", category: .other),
        .init(name: "Clash Royale", scheme: "clashroyale://", icon: "👑", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.supercell.scroll", category: .other),
        .init(name: "Brawl Stars", scheme: "brawlstars://", icon: "⭐️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.supercell.brawlstars", category: .other),
        .init(name: "Pokémon GO", scheme: "com.nianticlabs.pokemongo://", icon: "🐾", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.nianticlabs.pokemongo", category: .other),
        .init(name: "Candy Crush", scheme: "candycrushsaga://", icon: "🍭", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.midasplayer.apps.candycrushsaga", category: .other),
        .init(name: "Subway Surfers", scheme: "subwaysurfers://", icon: "🏃‍♂️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.kiloo.subwaysurf", category: .other),
        .init(name: "Asphalt 9", scheme: "asphalt9://", icon: "🏎️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.gameloft.asphalt9", category: .other),
        .init(name: "Hearthstone", scheme: "hearthstone://", icon: "🃏", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.blizzard.wtcg.hearthstone", category: .other),
        .init(name: "Wild Rift", scheme: "lor://", icon: "🗡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.riotgames.league.wildrift", category: .other),
        .init(name: "Valorant", scheme: "valorant://", icon: "🎯", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.riotgames.valorant", category: .other),
        .init(name: "Apex Legends Mobile", scheme: "apexm://", icon: "🪂", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.ea.gp.apexlegendsmobilefps", category: .other),
        .init(name: "Among Us", scheme: "amongus://", icon: "👩‍🚀", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.innersloth.amongus", category: .other),
        .init(name: "Stumble Guys", scheme: "stumbleguys://", icon: "🤸‍♂️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.kitkagames.fallbuddies", category: .other),
        .init(name: "Mobile Legends", scheme: "mobilelegends://", icon: "🛡️", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.mobile.legends", category: .other),
        .init(name: "Free Fire", scheme: "freefire://", icon: "🔥", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.dts.freefireth", category: .other),
        .init(name: "Hay Day", scheme: "hayday://", icon: "🌾", imageName: nil, link: "https://www.icloud.com/shortcuts/8d1cd21e18eb41d3ae6d7f049977dee8", bundleId: "com.supercell.hayday", category: .other),
    ]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        LanguageSettingsView(appLanguage: $appLanguage)
                            .navigationTitle(loc(appLanguage, "Language", "Язык"))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Text(loc(appLanguage, "Language", "Язык"))
                            Spacer()
                            Text(appLanguage == "ru" ? "Русский" : "English")
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        ThemeSettingsView(appLanguage: appLanguage, selectedTheme: $appThemeRaw)
                            .navigationTitle(loc(appLanguage, "Theme", "Тема"))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            Text(loc(appLanguage, "Theme", "Тема"))
                            Spacer()
                            Text(themeDisplayName(AppTheme(rawValue: appThemeRaw) ?? .system))
                                .foregroundColor(.secondary)
                        }
                    }
                }

            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }
    
    private var dayEndDateBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let cal = Calendar.current
                let now = Date()
                return cal.date(
                    bySettingHour: dayEndHourSetting,
                    minute: dayEndMinuteSetting,
                    second: 0,
                    of: now
                ) ?? now
            },
            set: { newValue in
                let cal = Calendar.current
                dayEndHourSetting = cal.component(.hour, from: newValue)
                dayEndMinuteSetting = cal.component(.minute, from: newValue)
                model.updateDayEnd(hour: dayEndHourSetting, minute: dayEndMinuteSetting)
            }
        )
    }

    private func formattedDayEnd() -> String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
    
    private func themeDisplayName(_ theme: AppTheme) -> String {
        appLanguage == "ru" ? theme.displayNameRu : theme.displayNameEn
    }

    // MARK: - Nested detail views
    private struct LanguageSettingsView: View {
        @Binding var appLanguage: String
        
        var body: some View {
            Form {
                Picker(loc(appLanguage, "Language", "Язык"), selection: $appLanguage) {
                    Text(loc(appLanguage, "English", "Английский")).tag("en")
                    Text(loc(appLanguage, "Русский", "Русский")).tag("ru")
                }
                .pickerStyle(.inline)
            }
        }
    }
    
    private struct ThemeSettingsView: View {
        let appLanguage: String
        @Binding var selectedTheme: String
        
        var body: some View {
            Form {
                Picker(loc(appLanguage, "Theme", "Тема"), selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(appLanguage == "ru" ? theme.displayNameRu : theme.displayNameEn)
                            .tag(theme.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
    
    private struct DayEndSettingsView: View {
        let appLanguage: String
        let dayEndDateBinding: Binding<Date>
        
        var body: some View {
            Form {
                DatePicker(
                    loc(appLanguage, "End of day", "Конец дня"),
                    selection: dayEndDateBinding,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
            }
        }
    }

    // MARK: - Debug helper
    private func testHandoffToken() {
        print("🧪 Testing handoff token creation...")

        let testToken = HandoffToken(
            targetBundleId: "com.burbn.instagram",
            targetAppName: "Instagram",
            createdAt: Date(),
            tokenId: UUID().uuidString
        )

        let userDefaults = UserDefaults.stepsTrader()

        if let tokenData = try? JSONEncoder().encode(testToken) {
            userDefaults.set(tokenData, forKey: "handoffToken")
            print("🧪 Test token created and saved: \(testToken.tokenId)")
            model.message =
                "🧪 Test handoff token created! Relaunch the app to verify."
        } else {
            print("❌ Failed to create test token")
            model.message = "❌ Failed to create test token"
        }
    }
}

// MARK: - Journal View
struct JournalView: View {
    @ObservedObject var model: AppModel
    let automationApps: [AutomationApp]
    let appLanguage: String
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @State private var monthOffset: Int = 0
    @State private var selectedDate: Date = Date()
    @State private var isGeneratingStory: Bool = false
    @State private var generatedEnglish: String?
    @State private var generatedRussian: String?
    @State private var storyError: String?
    @State private var showDetails: Bool = false
    @State private var secretTapCount = 0
    @State private var showDebugAlert = false
    
    private var storedStory: AppModel.DailyStory? {
        model.story(for: selectedDate)
    }
    
    private var storyToShow: String? {
        if appLanguage == "ru" {
            return generatedRussian ?? storedStory?.russian ?? generatedEnglish ?? storedStory?.english
        } else {
            return generatedEnglish ?? storedStory?.english ?? generatedRussian ?? storedStory?.russian
        }
    }
    
    private var isTodaySelected: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }
    
    private var automationBundleIds: Set<String> {
        Set(automationApps.map { $0.bundleId })
    }
    
    private var groupedLogs: [(date: Date, entries: [AppModel.AppOpenLog])] {
        let cal = Calendar.current
        let filtered = model.appOpenLogs.filter { automationBundleIds.contains($0.bundleId) }
        let grouped = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.date) }
        return grouped
            .map { (date: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
    
    private var currentMonthDays: [Date] {
        let cal = Calendar.current
        guard let baseMonth = cal.date(byAdding: .month, value: monthOffset, to: cal.startOfDay(for: Date())),
              let monthRange = cal.range(of: .day, in: .month, for: baseMonth),
              let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: baseMonth))
        else { return [] }
        return monthRange.compactMap { day -> Date? in
            cal.date(byAdding: .day, value: day - 1, to: startOfMonth)
        }
    }
    
    private func hasEntries(on date: Date) -> Bool {
        let cal = Calendar.current
        return groupedLogs.contains { cal.isDate($0.date, inSameDayAs: date) }
    }
    
    private func entries(for date: Date) -> [AppModel.AppOpenLog] {
        let cal = Calendar.current
        return model.appOpenLogs
            .filter { automationBundleIds.contains($0.bundleId) && cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date } // chronological for storytelling
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("DOOM CTRL")
                        .font(.caption2)
                        .foregroundColor(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            secretTapCount += 1
                            if secretTapCount >= 7 {
                                secretTapCount = 0
                                model.addDebugSteps(1000)
                                showDebugAlert = true
                            }
                        }
                    Spacer()
                }
                calendarGrid
                Divider()
                storyBlock
                if showDetails {
                    dayLogView
                } else {
                    Button {
                        showDetails = true
                    } label: {
                        HStack {
                            Image(systemName: "chevron.down.circle")
                            Text(loc(appLanguage, "Show detailed log", "Показать детальный лог"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                    }
                }
            }
            .padding()
        }
        .alert("Bonus fuel", isPresented: $showDebugAlert) {
            Button("Thanks", role: .cancel) {}
        } message: {
            Text("Added 1,000 debug steps to the balance.")
        }
        .background(Color.clear)
        .navigationTitle(loc(appLanguage, "Journal", "Журнал"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { preloadStory() }
        .onChange(of: selectedDate) { _, _ in preloadStory() }
    }
    
    private var calendarGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    monthOffset -= 1
                    adjustSelectionToDisplayedMonth()
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(monthTitle(for: displayedMonth))
                    .font(.headline)
                Spacer()
                Button {
                    guard monthOffset < 0 else { return }
                    monthOffset += 1
                    adjustSelectionToDisplayedMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(monthOffset < 0 ? .blue : .gray.opacity(0.4))
                }
                .disabled(monthOffset >= 0)
            }
            
            let columns = Array(repeating: GridItem(.flexible()), count: 7)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(currentMonthDays, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                    let hasLog = hasEntries(on: day)
                    VStack(spacing: 6) {
                        Text(dayNumberFormatter.string(from: day))
                            .font(.subheadline)
                            .fontWeight(hasLog ? .bold : .regular)
                            .foregroundColor(isSelected ? .white : .primary)
                        if hasLog {
                            Circle()
                                .fill(isSelected ? Color.white : Color.blue)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
                    )
                    .onTapGesture { selectedDate = day }
                }
            }
        }
    }
    
    private var displayedMonth: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    
    private func adjustSelectionToDisplayedMonth() {
        let cal = Calendar.current
        if !cal.isDate(selectedDate, equalTo: displayedMonth, toGranularity: .month) {
            if let start = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)) {
                selectedDate = start
            }
        }
    }
    
    @ViewBuilder
    private var storyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc(appLanguage, "Journal of craws", "Журнал вылазок"))
                .font(.headline)
            if isTodaySelected && storyToShow == nil {
                Text(
                    loc(
                        appLanguage,
                        "Journal will be updated at \(formattedDayEnd())",
                        "Журнал будет обновлен в \(formattedDayEnd())"
                    )
                )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            } else if let story = storyToShow {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appLanguage == "ru" ? "Русский" : "English")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    markupText(story)
                        .font(.subheadline)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
            } else if let error = storyError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text(loc(appLanguage, "No story yet.", "История пока не создана."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var dayLogView: some View {
        let dayEntries = entries(for: selectedDate)
        return VStack(alignment: .leading, spacing: 10) {
            Text(dateFormatter.string(from: selectedDate))
                .font(.headline)
            daySummaryView
            if dayEntries.isEmpty {
                Text(loc(appLanguage, "No opens this day.", "В этот день открытий не было."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Button {
                    showDetails = false
                } label: {
                    HStack {
                        Image(systemName: "chevron.up.circle")
                        Text(loc(appLanguage, "Hide detailed log", "Скрыть детальный лог"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                }
                
                ForEach(dayEntries.indices, id: \.self) { idx in
                    let entry = dayEntries[idx]
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(colorForBundle(entry.bundleId))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appName(entry.bundleId))
                                .font(.subheadline).bold()
                            Text(timeFormatter.string(from: entry.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if isTodaySelected {
                                let spent = model.appStepsSpentToday[entry.bundleId, default: 0]
                                if spent > 0 {
                                    Text(loc(appLanguage, "Steps spent", "Потрачено шагов") + ": \(spent)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                if model.hasDayPass(for: entry.bundleId) {
                                    Text(loc(appLanguage, "Day pass active today", "Дневной проход активен"))
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
                }
            }
        }
    }
    
    private var daySummaryView: some View {
        let stepsMade = isTodaySelected ? Int(model.effectiveStepsToday) : nil
        let stepsSpent = isTodaySelected ? model.appStepsSpentToday.values.reduce(0, +) : nil
        let remaining = isTodaySelected ? max(0, Int(model.effectiveStepsToday) - model.spentStepsToday) : nil
        let opensCount = entries(for: selectedDate).count
        let dayPassActiveCount = automationApps.filter { model.hasDayPass(for: $0.bundleId) }.count
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc(appLanguage, "Steps made", "Сделано шагов"))
                Spacer()
                Text(stepsMade != nil ? "\(stepsMade!)" : "—")
            }.font(.caption)
            HStack {
                Text(loc(appLanguage, "Shields used", "Щитов использовано"))
                Spacer()
                Text("\(opensCount)")
            }.font(.caption)
            HStack {
                Text(loc(appLanguage, "Steps spent", "Шагов потрачено"))
                Spacer()
                Text(stepsSpent != nil ? "\(stepsSpent!)" : "—")
            }.font(.caption)
            HStack {
                Text(loc(appLanguage, "Steps left", "Шагов осталось"))
                Spacer()
                Text(remaining != nil ? "\(remaining!)" : "—")
            }.font(.caption)
            .foregroundColor(.secondary)
            
            if isTodaySelected, dayPassActiveCount > 0 {
                Text(loc(appLanguage, "Day pass active for \(dayPassActiveCount) shields", "Дневной проход активен для \(dayPassActiveCount) щитов"))
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
    }
    
    private func richDescription(for entry: AppModel.AppOpenLog, previous: AppModel.AppOpenLog?) -> String {
        let timeString = timeFormatter.string(from: entry.date)
        guard let previous else {
            return "Открыто в \(timeString). День только начинается."
        }
        let delta = entry.date.timeIntervalSince(previous.date)
        let minutes = Int(delta / 60)
        switch minutes {
        case 0..<5:
            return "Открыто в \(timeString). Почти подряд — кажется, что-то забыли проверить."
        case 5..<30:
            return "Открыто в \(timeString). Короткая пауза, быстрый возврат."
        case 30..<180:
            return "Открыто в \(timeString). Перерыв \(minutes) мин — похоже, переключались."
        case 180..<720:
            return "Открыто в \(timeString). Долгая пауза (\(minutes/60) ч) — возможно, было не до приложений."
        default:
            return "Открыто в \(timeString). Большой перерыв — тут я явно отдыхал от экранов."
        }
    }
    
    // MARK: - LLM prompt and call
    private func buildPromptEnglish(dayEntries: [AppModel.AppOpenLog]) -> String {
        let stepsMade = isTodaySelected ? Int(model.effectiveStepsToday) : nil
        let stepsSpent = isTodaySelected ? model.appStepsSpentToday.values.reduce(0, +) : nil
        let remaining = isTodaySelected ? max(0, Int(model.effectiveStepsToday) - model.spentStepsToday) : nil
        let dayPassActive = isTodaySelected ? automationApps.filter { model.hasDayPass(for: $0.bundleId) }.map { $0.name } : []
        
        var lines: [String] = []
        lines.append("Дата: \(dateFormatter.string(from: selectedDate))")
        if let made = stepsMade { lines.append("Шагов сделано: \(made)") }
        if let spent = stepsSpent { lines.append("Шагов потрачено: \(spent)") }
        if let rem = remaining { lines.append("Топлива осталось: \(rem)") }
        if !dayPassActive.isEmpty {
            let joined = dayPassActive.joined(separator: ", ")
            lines.append("Дневные пропуски активны: \(joined)")
        }
        lines.append("Путешествия:")
        
        for (idx, entry) in dayEntries.enumerated() {
            let time = timeFormatter.string(from: entry.date)
            let name = appName(entry.bundleId)
            var gapText = ""
            if idx > 0 {
                let delta = entry.date.timeIntervalSince(dayEntries[idx-1].date)
                let minutes = Int(delta / 60)
                gapText = " | пауза \(minutes) мин"
            }
            lines.append("- \(time): jumped to universe \(name)\(gapText)")
        }
        
        lines.append("Write a short captain's log of a spaceship pilot, warm and imaginative (4-6 sentences). Use metaphors of fuel and jumps between universes. Language: English.")
        return lines.joined(separator: "\n")
    }
    
    private func generateStory(dayEntries: [AppModel.AppOpenLog]) async {
        storyError = nil
        generatedEnglish = nil
        generatedRussian = nil
        guard !dayEntries.isEmpty else { return }
        let promptEN = buildPromptEnglish(dayEntries: dayEntries)
        isGeneratingStory = true
        do {
            let english = try await LLMService.shared.generateCosmicJournal(prompt: promptEN)
            let translatePrompt = "Translate the following captain's log into Russian, keep the cosmic pilot vibe and warmth, keep 4-6 sentences:\n\(english)"
            let russian = try await LLMService.shared.generateCosmicJournal(prompt: translatePrompt)
            await MainActor.run {
                generatedEnglish = english
                generatedRussian = russian
                isGeneratingStory = false
            }
            await MainActor.run {
                model.saveStory(for: selectedDate, english: english, russian: russian)
            }
        } catch {
            await MainActor.run {
                storyError = loc(appLanguage, "Story generation failed. Add DEEPSEEK_API_KEY in Info.plist or set deepseek_api_key in UserDefaults.", "Ошибка генерации. Добавьте DEEPSEEK_API_KEY в Info.plist или установите deepseek_api_key в UserDefaults.")
                isGeneratingStory = false
            }
        }
    }
    
    private func appName(_ bundleId: String) -> String {
        automationApps.first(where: { $0.bundleId == bundleId })?.name ?? bundleId
    }
    
    private func appIcon(_ bundleId: String) -> some View {
        if let imageName = automationApps.first(where: { $0.bundleId == bundleId })?.imageName,
           let uiImage = UIImage(named: imageName) {
            return AnyView(Image(uiImage: uiImage).resizable().scaledToFit())
        }
        return AnyView(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .overlay(Image(systemName: "app").foregroundColor(.secondary))
        )
    }
    
    private func colorForBundle(_ bundleId: String) -> Color {
        switch bundleId {
        case "com.burbn.instagram": return .pink
        case "com.zhiliaoapp.musically": return .red
        case "com.google.ios.youtube": return .red.opacity(0.8)
        case "com.facebook.Facebook": return .blue
        case "com.linkedin.LinkedIn": return .blue.opacity(0.6)
        case "com.atebits.Tweetie2": return .gray
        case "com.toyopagroup.picaboo": return .yellow
        case "net.whatsapp.WhatsApp": return .green
        case "ph.telegra.Telegraph": return .cyan
        case "com.duolingo.DuolingoMobile": return .green.opacity(0.7)
        case "com.pinterest": return .red
        case "com.reddit.Reddit": return .orange
        default: return .purple
        }
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df
    }
    
    private var dayNumberFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "d"
        return df
    }
    
    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }
    
    private var timeFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }
    
    private func preloadStory() {
        if let stored = storedStory {
            generatedEnglish = stored.english
            generatedRussian = stored.russian
        } else {
            generatedEnglish = nil
            generatedRussian = nil
        }
    }
    
    @ViewBuilder
    private func markupText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
    
    private func formattedDayEnd() -> String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let cal = Calendar.current
        let date = cal.date(from: comps) ?? Date()
        let df = DateFormatter()
        df.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}
