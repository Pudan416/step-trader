import SwiftUI
import UIKit

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    private var tariffs: [Tariff] { Tariff.allCases }
    
    // Popular apps list reused across the app
    static let automationAppsStatic: [AutomationApp] = [
        .init(name: "YouTube", scheme: "youtube://", icon: "▶️", imageName: "youtube", link: "https://www.icloud.com/shortcuts/f880905ebcb244e2a4dcc43aee73a9fd", bundleId: "com.google.ios.youtube"),
        .init(name: "Instagram", scheme: "instagram://", icon: "📸", imageName: "instagram", link: "https://www.icloud.com/shortcuts/34ba0e1e5a2a441f9a2a2d31358a92a4", bundleId: "com.burbn.instagram"),
        .init(name: "TikTok", scheme: "tiktok://", icon: "🎵", imageName: "tiktok", link: "https://www.icloud.com/shortcuts/6f2b49ec00ec4660b633b807decaa753", bundleId: "com.zhiliaoapp.musically"),
        .init(name: "Telegram", scheme: "tg://", icon: "✈️", imageName: "telegram", link: "https://www.icloud.com/shortcuts/b2b1b248690042f49698184fe47988c5", bundleId: "ph.telegra.Telegraph"),
        .init(name: "WhatsApp", scheme: "whatsapp://", icon: "💬", imageName: "whatsapp", link: "https://www.icloud.com/shortcuts/6e1bb2f78d6f47db8b63572aac924960", bundleId: "net.whatsapp.WhatsApp"),
        .init(name: "Snapchat", scheme: "snapchat://", icon: "👻", imageName: "snapchat", link: "https://www.icloud.com/shortcuts/4961a35971a54071b696182ee43ed042", bundleId: "com.toyopagroup.picaboo"),
        .init(name: "Facebook", scheme: "fb://", icon: "📘", imageName: "facebook", link: "https://www.icloud.com/shortcuts/72f05f04bb0c4eecaa52b23828045485", bundleId: "com.facebook.Facebook"),
        .init(name: "LinkedIn", scheme: "linkedin://", icon: "💼", imageName: "linkedin", link: "https://www.icloud.com/shortcuts/4f2e5216cbac49db9f0d13bd0bddb64c", bundleId: "com.linkedin.LinkedIn"),
        .init(name: "X (Twitter)", scheme: "twitter://", icon: "🐦", imageName: "x", link: "https://www.icloud.com/shortcuts/21db280a91764770a2e555bd5948a61e", bundleId: "com.atebits.Tweetie2"),
        .init(name: "Reddit", scheme: "reddit://", icon: "👽", imageName: "reddit", link: "https://www.icloud.com/shortcuts/a5b3b9db2c7946aba5f2b9da46e17c6d", bundleId: "com.reddit.Reddit"),
        .init(name: "Pinterest", scheme: "pinterest://", icon: "📌", imageName: "pinterest", link: "https://www.icloud.com/shortcuts/699580a8cf714e87a6d329bbe2192eea", bundleId: "com.pinterest"),
        .init(name: "Duolingo", scheme: "duolingo://", icon: "🦉", imageName: "duolingo", link: nil, bundleId: "com.duolingo.DuolingoMobile", category: .other),
        
        // Other apps pool
        .init(name: "Google Maps", scheme: "comgooglemaps://", icon: "🗺️", imageName: nil, link: nil, bundleId: "com.google.Maps", category: .other),
        .init(name: "Waze", scheme: "waze://", icon: "🚗", imageName: nil, link: nil, bundleId: "com.waze.iphone", category: .other),
        .init(name: "Apple Maps", scheme: "maps://", icon: "🧭", imageName: nil, link: nil, bundleId: "com.apple.Maps", category: .other),
        .init(name: "Gmail", scheme: "googlegmail://", icon: "✉️", imageName: nil, link: nil, bundleId: "com.google.Gmail", category: .other),
        .init(name: "Outlook", scheme: "ms-outlook://", icon: "📧", imageName: nil, link: nil, bundleId: "com.microsoft.Office.Outlook", category: .other),
        .init(name: "Spark", scheme: "readdle-spark://", icon: "⚡️", imageName: nil, link: nil, bundleId: "com.readdle.smartemail", category: .other),
        .init(name: "Yahoo Mail", scheme: "ymail://", icon: "💌", imageName: nil, link: nil, bundleId: "com.yahoo.Aerogram", category: .other),
        .init(name: "Proton Mail", scheme: "protonmail://", icon: "🔐", imageName: nil, link: nil, bundleId: "ch.protonmail.protonmail", category: .other),
        .init(name: "Slack", scheme: "slack://", icon: "💬", imageName: nil, link: nil, bundleId: "com.tinyspeck.chatlyio", category: .other),
        .init(name: "Microsoft Teams", scheme: "msteams://", icon: "👥", imageName: nil, link: nil, bundleId: "com.microsoft.skype.teams", category: .other),
        .init(name: "Zoom", scheme: "zoomus://", icon: "🎥", imageName: nil, link: nil, bundleId: "us.zoom.videomeetings", category: .other),
        .init(name: "Webex", scheme: "wbx://", icon: "🌀", imageName: nil, link: nil, bundleId: "com.cisco.webex.meetings", category: .other),
        .init(name: "Skype", scheme: "skype://", icon: "📞", imageName: nil, link: nil, bundleId: "com.skype.skype", category: .other),
        .init(name: "Signal", scheme: "sgnl://", icon: "🔵", imageName: nil, link: nil, bundleId: "org.whispersystems.signal", category: .other),
        .init(name: "Viber", scheme: "viber://", icon: "📱", imageName: nil, link: nil, bundleId: "com.viber", category: .other),
        .init(name: "Line", scheme: "line://", icon: "💬", imageName: nil, link: nil, bundleId: "jp.naver.line", category: .other),
        .init(name: "WeChat", scheme: "weixin://", icon: "🟩", imageName: nil, link: nil, bundleId: "com.tencent.xin", category: .other),
        .init(name: "KakaoTalk", scheme: "kakaolink://", icon: "🟡", imageName: nil, link: nil, bundleId: "com.iwilab.KakaoTalk", category: .other),
        .init(name: "Notion", scheme: "notion://", icon: "📓", imageName: nil, link: nil, bundleId: "notion.id", category: .other),
        .init(name: "Trello", scheme: "trello://", icon: "🗂️", imageName: nil, link: nil, bundleId: "com.fogcreek.trello", category: .other),
        .init(name: "Evernote", scheme: "evernote://", icon: "🟢", imageName: nil, link: nil, bundleId: "com.evernote.iPhone.Evernote", category: .other),
        .init(name: "Todoist", scheme: "todoist://", icon: "✅", imageName: nil, link: nil, bundleId: "com.todoist.mac.Todoist", category: .other),
        .init(name: "Dropbox", scheme: "dbapi-1://", icon: "📦", imageName: nil, link: nil, bundleId: "com.getdropbox.Dropbox", category: .other),
        .init(name: "Google Drive", scheme: "googledrive://", icon: "🟢", imageName: nil, link: nil, bundleId: "com.google.Drive", category: .other),
        .init(name: "OneDrive", scheme: "ms-onedrive://", icon: "☁️", imageName: nil, link: nil, bundleId: "com.microsoft.skydrive", category: .other),
        .init(name: "Box", scheme: "box://", icon: "📁", imageName: nil, link: nil, bundleId: "net.box.BoxNet", category: .other),
        .init(name: "1Password", scheme: "onepassword://", icon: "🛡️", imageName: nil, link: nil, bundleId: "com.agilebits.onepassword-ios", category: .other),
        .init(name: "NordVPN", scheme: "nordvpn://", icon: "🧭", imageName: nil, link: nil, bundleId: "com.nordvpn.NordVPN", category: .other),
        .init(name: "Apple Music", scheme: "music://", icon: "🎵", imageName: nil, link: nil, bundleId: "com.apple.Music", category: .other),
        .init(name: "Tidal", scheme: "tidal://", icon: "🌊", imageName: nil, link: nil, bundleId: "com.aspiro.TIDAL", category: .other),
        .init(name: "Deezer", scheme: "deezer://", icon: "🎶", imageName: nil, link: nil, bundleId: "com.deezer.Deezer", category: .other),
        .init(name: "SoundCloud", scheme: "soundcloud://", icon: "☁️", imageName: nil, link: nil, bundleId: "com.soundcloud.TouchApp", category: .other),
        .init(name: "Shazam", scheme: "shazam://", icon: "🔎", imageName: nil, link: nil, bundleId: "com.shazam.Shazam", category: .other),
        .init(name: "Audible", scheme: "audible://", icon: "🎧", imageName: nil, link: nil, bundleId: "com.audible.iphone", category: .other),
        .init(name: "Kindle", scheme: "kindle://", icon: "📚", imageName: nil, link: nil, bundleId: "com.amazon.Lassen", category: .other),
        .init(name: "Twitch", scheme: "twitch://", icon: "🟣", imageName: nil, link: nil, bundleId: "tv.twitch", category: .other),
        .init(name: "Uber", scheme: "uber://", icon: "🚕", imageName: nil, link: nil, bundleId: "com.ubercab.UberClient", category: .other),
        .init(name: "Lyft", scheme: "lyft://", icon: "🚙", imageName: nil, link: nil, bundleId: "com.zimride.instant", category: .other),
        .init(name: "Roblox", scheme: "roblox://", icon: "🎮", imageName: nil, link: nil, bundleId: "com.roblox.robloxmobile", category: .other),
        .init(name: "Minecraft", scheme: "minecraft://", icon: "⛏️", imageName: nil, link: nil, bundleId: "com.mojang.minecraftpe", category: .other),
        .init(name: "PUBG Mobile", scheme: "pubgmobile://", icon: "⚔️", imageName: nil, link: nil, bundleId: "com.tencent.ig", category: .other),
        .init(name: "Call of Duty Mobile", scheme: "codm://", icon: "🎯", imageName: nil, link: nil, bundleId: "com.activision.callofduty.shooter", category: .other),
        .init(name: "Genshin Impact", scheme: "yuanshen://", icon: "🌌", imageName: nil, link: nil, bundleId: "com.miHoYo.GenshinImpact", category: .other),
        .init(name: "Fortnite", scheme: "fortnite://", icon: "🛡️", imageName: nil, link: nil, bundleId: "com.epicgames.fortnite", category: .other),
        .init(name: "FIFA Mobile", scheme: "fifamobile://", icon: "⚽️", imageName: nil, link: nil, bundleId: "com.ea.ios.fifaultimate", category: .other),
        .init(name: "Clash of Clans", scheme: "clashofclans://", icon: "🛡️", imageName: nil, link: nil, bundleId: "com.supercell.magic", category: .other),
        .init(name: "Clash Royale", scheme: "clashroyale://", icon: "👑", imageName: nil, link: nil, bundleId: "com.supercell.scroll", category: .other),
        .init(name: "Brawl Stars", scheme: "brawlstars://", icon: "⭐️", imageName: nil, link: nil, bundleId: "com.supercell.brawlstars", category: .other),
        .init(name: "Pokémon GO", scheme: "com.nianticlabs.pokemongo://", icon: "🐾", imageName: nil, link: nil, bundleId: "com.nianticlabs.pokemongo", category: .other),
        .init(name: "Candy Crush", scheme: "candycrushsaga://", icon: "🍭", imageName: nil, link: nil, bundleId: "com.midasplayer.apps.candycrushsaga", category: .other),
        .init(name: "Subway Surfers", scheme: "subwaysurfers://", icon: "🏃‍♂️", imageName: nil, link: nil, bundleId: "com.kiloo.subwaysurf", category: .other),
        .init(name: "Asphalt 9", scheme: "asphalt9://", icon: "🏎️", imageName: nil, link: nil, bundleId: "com.gameloft.asphalt9", category: .other),
        .init(name: "Hearthstone", scheme: "hearthstone://", icon: "🃏", imageName: nil, link: nil, bundleId: "com.blizzard.wtcg.hearthstone", category: .other),
        .init(name: "Wild Rift", scheme: "lor://", icon: "🗡️", imageName: nil, link: nil, bundleId: "com.riotgames.league.wildrift", category: .other),
        .init(name: "Valorant", scheme: "valorant://", icon: "🎯", imageName: nil, link: nil, bundleId: "com.riotgames.valorant", category: .other),
        .init(name: "Apex Legends Mobile", scheme: "apexm://", icon: "🪂", imageName: nil, link: nil, bundleId: "com.ea.gp.apexlegendsmobilefps", category: .other),
        .init(name: "Among Us", scheme: "amongus://", icon: "👩‍🚀", imageName: nil, link: nil, bundleId: "com.innersloth.amongus", category: .other),
        .init(name: "Stumble Guys", scheme: "stumbleguys://", icon: "🤸‍♂️", imageName: nil, link: nil, bundleId: "com.kitkagames.fallbuddies", category: .other),
        .init(name: "Mobile Legends", scheme: "mobilelegends://", icon: "🛡️", imageName: nil, link: nil, bundleId: "com.mobile.legends", category: .other),
        .init(name: "Free Fire", scheme: "freefire://", icon: "🔥", imageName: nil, link: nil, bundleId: "com.dts.freefireth", category: .other),
        .init(name: "Hay Day", scheme: "hayday://", icon: "🌾", imageName: nil, link: nil, bundleId: "com.supercell.hayday", category: .other),
    ]

    var body: some View {
        NavigationView {
            Form {
                languageSection
                journalSection
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Language
    private var languageSection: some View {
        Section(loc(appLanguage, "Language", "Язык")) {
            Picker(loc(appLanguage, "Language", "Язык"), selection: $appLanguage) {
                Text(loc(appLanguage, "English", "Английский")).tag("en")
                Text(loc(appLanguage, "Русский", "Русский")).tag("ru")
            }
            .pickerStyle(.segmented)
        }
    }
    
    // MARK: - Journal
    private var journalSection: some View {
        Section(loc(appLanguage, "Journal", "Журнал")) {
            NavigationLink {
                JournalView(model: model, automationApps: SettingsView.automationAppsStatic, appLanguage: appLanguage)
            } label: {
                Text(loc(appLanguage, "Open journal", "Открыть журнал"))
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
    @State private var selectedDate: Date = Date()
    
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
        let today = cal.startOfDay(for: Date())
        guard let monthRange = cal.range(of: .day, in: .month, for: today),
              let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))
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
                calendarGrid
                Divider()
                dayLogView
            }
            .padding()
        }
        .navigationTitle(loc(appLanguage, "Journal", "Журнал"))
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var calendarGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle(for: selectedDate))
                .font(.headline)
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
                ForEach(dayEntries.indices, id: \.self) { idx in
                    let entry = dayEntries[idx]
                    let previous = idx > 0 ? dayEntries[idx - 1] : nil
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(colorForBundle(entry.bundleId))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appName(entry.bundleId))
                                .font(.subheadline).bold()
                            Text(richDescription(for: entry, previous: previous))
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
        let stepsMade = isTodaySelected ? Int(model.stepsToday) : nil
        let stepsSpent = isTodaySelected ? model.appStepsSpentToday.values.reduce(0, +) : nil
        let remaining = isTodaySelected ? max(0, Int(model.stepsToday) - model.spentStepsToday) : nil
        let opensCount = entries(for: selectedDate).count
        
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc(appLanguage, "Steps made", "Сделано шагов"))
                Spacer()
                Text(stepsMade != nil ? "\(stepsMade!)" : "—")
            }.font(.caption)
            HStack {
                Text(loc(appLanguage, "Modules used", "Модулей использовано"))
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
}
