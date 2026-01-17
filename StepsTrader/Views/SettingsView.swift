import SwiftUI
import UIKit

// MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService = AuthenticationService.shared
    @ObservedObject var cloudService = CloudKitService.shared
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var showLoginSheet: Bool = false
    @State private var showRestoreAlert: Bool = false
    @State private var showProfileEditor: Bool = false
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
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    settingsHeader
                    
                    // Account Section
                    accountSection
                    
                    // iCloud Sync Section - hidden from user (syncs automatically via Supabase)
                    // if authService.isAuthenticated {
                    //     cloudSyncSection
                    // }
                    
                    // App Settings Section
                    appSettingsSection
                    
                    // App Info
                    appInfoSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .scrollIndicators(.hidden)
            .onAppear {
                // Language selection was removed; keep the UI in English if an old value was persisted.
                if appLanguage == "ru" { appLanguage = "en" }
                
                // Refresh user data from server
                Task {
                    await authService.checkAuthenticationState()
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
            .alert(loc(appLanguage, "Restore from iCloud", "Восстановить из iCloud"), isPresented: $showRestoreAlert) {
                Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) { }
                Button(loc(appLanguage, "Restore", "Восстановить"), role: .destructive) {
                    Task { await cloudService.restoreFromCloud(model: model) }
                }
            } message: {
                Text(loc(appLanguage, "This will replace your current shields and progress with data from iCloud.", "Это заменит ваши текущие щиты и прогресс данными из iCloud."))
            }
            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
    
    // Glass card style
    private var settingsGlassCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Header
    private var settingsHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "gearshape.2.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.gray, .gray.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc(appLanguage, "Command Center", "Командный центр"))
                    .font(.headline)
                Text(loc(appLanguage, "Tweak everything here ⚙️", "Настрой всё под себя ⚙️"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Section header - edgy
            sectionHeaderEdgy(icon: "person.fill", title: loc(appLanguage, "Identity", "Личность"), subtitle: loc(appLanguage, "Who are you, warrior?", "Кто ты, воин?"), color: pink)
            
            if authService.isAuthenticated, let user = authService.currentUser {
                // User profile
                Button {
                    showProfileEditor = true
                } label: {
                    HStack(spacing: 12) {
                        // Avatar
                        if let data = user.avatarData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(pink.opacity(0.3), lineWidth: 2))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [pink, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 48, height: 48)
                                Text(String(user.displayName.prefix(2)).uppercased())
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            
                            if let location = user.locationString {
                                Text(location)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if let email = user.email {
                                Text(email)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(6)
                            .background(Circle().fill(Color(.tertiarySystemBackground)))
                    }
                    .padding(14)
                }
                
                // Sign out button
                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "door.left.hand.open")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 24)
                        Text(loc(appLanguage, "Leave", "Выйти"))
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            } else {
                // Sign in button - edgy
                Button {
                    showLoginSheet = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 40, height: 40)
                            Image(systemName: "apple.logo")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc(appLanguage, "Join the game", "Вступай в игру"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(loc(appLanguage, "Sign in to sync progress 🔄", "Войди чтобы сохранять прогресс 🔄"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(6)
                            .background(Circle().fill(Color(.tertiarySystemBackground)))
                    }
                    .padding(14)
                }
            }
        }
        .background(settingsGlassCard)
    }
    
    // MARK: - Cloud Sync Section
    private var cloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderEdgy(
                icon: "icloud.fill",
                title: loc(appLanguage, "Cloud Backup", "Бэкап в облаке"),
                subtitle: loc(appLanguage, "Never lose your progress ☁️", "Не теряй прогресс ☁️"),
                color: .cyan
            )
            
            // Status row
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(cloudService.isCloudKitAvailable ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: cloudService.isCloudKitAvailable ? "checkmark" : "xmark")
                        .font(.caption.bold())
                        .foregroundColor(cloudService.isCloudKitAvailable ? .green : .red)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("iCloud")
                        .font(.caption.weight(.medium))
                    Text(cloudService.isCloudKitAvailable ? loc(appLanguage, "Online", "Онлайн") : loc(appLanguage, "Offline", "Офлайн"))
                        .font(.caption2)
                        .foregroundColor(cloudService.isCloudKitAvailable ? .green : .red)
                }
                
                Spacer()
                
                if let lastSync = cloudService.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            
            if cloudService.isCloudKitAvailable {
                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        Task { await cloudService.syncAll(model: model) }
                    } label: {
                        HStack(spacing: 6) {
                            if cloudService.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            Text(loc(appLanguage, "Sync", "Синк"))
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.15))
                        .foregroundColor(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(cloudService.isSyncing)
                    
                    Button {
                        showRestoreAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption)
                            Text(loc(appLanguage, "Restore", "Восстановить"))
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(cloudService.isSyncing)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(settingsGlassCard)
    }
    
    // MARK: - App Settings Section
    @AppStorage("payGateBackgroundStyle") private var payGateBackgroundStyle: String = "midnight"
    
    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderEdgy(
                icon: "slider.horizontal.3",
                title: loc(appLanguage, "Preferences", "Настройки"),
                subtitle: loc(appLanguage, "Make it yours 🎨", "Сделай под себя 🎨"),
                color: .purple
            )
            
            VStack(spacing: 0) {
                // Theme
                NavigationLink {
                    ThemeSettingsView(appLanguage: appLanguage, selectedTheme: $appThemeRaw)
                        .navigationTitle(loc(appLanguage, "Theme", "Тема"))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "paintbrush.fill")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                        }
                        
                        Text(loc(appLanguage, "Theme", "Тема"))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(themeDisplayName(AppTheme(rawValue: appThemeRaw) ?? .system))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                
                Divider()
                    .padding(.leading, 58)
                
                // PayGate Background
                NavigationLink {
                    PayGateBackgroundSettingsView(
                        appLanguage: appLanguage,
                        selectedStyle: $payGateBackgroundStyle
                    )
                    .navigationTitle(loc(appLanguage, "Entry Screen", "Экран входа"))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.pink.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.subheadline)
                                .foregroundColor(.pink)
                        }
                        
                        Text(loc(appLanguage, "Entry Screen", "Экран входа"))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(payGateStyleDisplayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
            }
            .padding(.bottom, 4)
        }
        .background(settingsGlassCard)
    }
    
    private var payGateStyleDisplayName: String {
        let style = PayGateBackgroundStyle(rawValue: payGateBackgroundStyle) ?? .midnight
        return appLanguage == "ru" ? style.displayNameRU : style.displayName
    }
    
    // MARK: - App Info Section
    private var appInfoSection: some View {
        VStack(spacing: 8) {
            Text("DOOM CTRL")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(loc(appLanguage, "Built with 💜 for bloody meantal health", "Создано c 💜 к сраному ментальному здоровью"))
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    // MARK: - Helper Views
    @ViewBuilder
    private func sectionHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.headline)
            
            Spacer()
        }
        .padding(16)
    }
    
    @ViewBuilder
    private func sectionHeaderEdgy(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(14)
    }
    
    @ViewBuilder
    private func settingsRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(16)
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
    
    private struct PayGateBackgroundSettingsView: View {
        let appLanguage: String
        @Binding var selectedStyle: String
        
        var body: some View {
            ScrollView {
                VStack(spacing: 16) {
                    Text(loc(appLanguage, "Choose your entry screen style", "Выбери стиль экрана входа"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(PayGateBackgroundStyle.allCases) { style in
                            PayGateStyleCard(
                                style: style,
                                isSelected: selectedStyle == style.rawValue,
                                appLanguage: appLanguage
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedStyle = style.rawValue
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private struct PayGateStyleCard: View {
        let style: PayGateBackgroundStyle
        let isSelected: Bool
        let appLanguage: String
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                VStack(spacing: 0) {
                    // Preview
                    ZStack {
                        // Gradient preview
                        LinearGradient(
                            gradient: Gradient(colors: style.colors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Soft accent circles (RadialGradient instead of blur for GPU stability)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [style.accentColor.opacity(0.4), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 30
                                )
                            )
                            .frame(width: 60)
                            .offset(x: -20, y: -15)
                        
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [style.colors[1].opacity(0.5), Color.clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 25
                                )
                            )
                            .frame(width: 50)
                            .offset(x: 20, y: 20)
                        
                        // Icon
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                        
                        // Selected checkmark
                        if isSelected {
                            VStack {
                                HStack {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 2)
                                        .padding(8)
                                }
                                Spacer()
                            }
                        }
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    // Label
                    Text(appLanguage == "ru" ? style.displayNameRU : style.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)
                        .padding(.vertical, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? style.accentColor : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
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
    // Debug bonus removed (no minting energy outside HealthKit / Outer World)
    
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
                            if let spent = entry.spentSteps {
                                Text(loc(appLanguage, "Steps spent", "Потрачено шагов") + ": \(spent)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if isTodaySelected, model.hasDayPass(for: entry.bundleId) {
                                Text(loc(appLanguage, "Day pass active today", "Дневной проход активен"))
                                    .font(.caption2)
                                    .foregroundColor(.green)
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

// MARK: - Profile Editor View

struct ProfileEditorView: View {
    @ObservedObject var authService: AuthenticationService
    @StateObject private var locationManager = ProfileLocationManager()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    @State private var nickname: String = ""
    @State private var selectedCountryCode: String = ""
    @State private var showCountryPicker: Bool = false
    @State private var avatarImage: UIImage?
    @State private var showImagePicker: Bool = false
    @State private var showImageSourcePicker: Bool = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    
    // All countries sorted by localized name
    private var countries: [(code: String, name: String)] {
        let codes = Locale.Region.isoRegions.map { $0.identifier }
        let locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return codes.compactMap { code -> (String, String)? in
            guard let name = locale.localizedString(forRegionCode: code), !name.isEmpty else { return nil }
            return (code, name)
        }.sorted { $0.name < $1.name }
    }
    
    private var selectedCountryName: String {
        if selectedCountryCode.isEmpty { return "" }
        let locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return locale.localizedString(forRegionCode: selectedCountryCode) ?? selectedCountryCode
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Photo section
                Section {
                    HStack {
                        Spacer()
                        Button {
                            showImageSourcePicker = true
                        } label: {
                            ZStack {
                                if let image = avatarImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 96, height: 96)
                                    
                                    Text(String((authService.currentUser?.displayName ?? "U").prefix(2)).uppercased())
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(.white)
                                }
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 34, y: 34)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    
                    if avatarImage != nil {
                        Button(role: .destructive) {
                            avatarImage = nil
                        } label: {
                            HStack {
                                Spacer()
                                Text(loc(appLanguage, "Remove Photo", "Удалить фото"))
                                Spacer()
                            }
                        }
                    }
                }
                
                // Nickname section
                Section {
                    HStack {
                        Image(systemName: "at")
                            .foregroundColor(.secondary)
                            .frame(width: 24)
                        TextField(loc(appLanguage, "Nickname", "Никнейм"), text: $nickname)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text(loc(appLanguage, "Nickname", "Никнейм"))
                } footer: {
                    Text(loc(appLanguage, "This name will be displayed instead of your real name", "Это имя будет отображаться вместо настоящего"))
                }
                
                // Location section
                Section {
                    // Use my location button
                    Button {
                        locationManager.requestCountryCode { detectedCountryCode in
                            if let cc = detectedCountryCode { selectedCountryCode = cc }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text(loc(appLanguage, "Detect my country", "Определить страну"))
                                .foregroundColor(.blue)
                            Spacer()
                            if locationManager.isLoading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(locationManager.isLoading)
                    
                    // Country picker
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(loc(appLanguage, "Country", "Страна"))
                                .foregroundColor(.primary)
                            Spacer()
                            if !selectedCountryCode.isEmpty {
                                Text(selectedCountryName)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(loc(appLanguage, "Select", "Выбрать"))
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Location", "Локация"))
                } footer: {
                    if let error = locationManager.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
                
                // Email (read-only)
                if let email = authService.currentUser?.email {
                    Section {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(email)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Email")
                    } footer: {
                        Text(loc(appLanguage, "Email is managed by Apple ID", "Email управляется через Apple ID"))
                    }
                }
            }
            .navigationTitle(loc(appLanguage, "Edit Profile", "Редактировать профиль"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel", "Отмена")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(loc(appLanguage, "Save", "Сохранить")) {
                            Task {
                                await saveProfileAsync()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                loadCurrentProfile()
            }
            .alert(loc(appLanguage, "Error", "Ошибка"), isPresented: .init(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button(loc(appLanguage, "OK", "Ок")) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            .confirmationDialog(
                loc(appLanguage, "Choose Photo", "Выбрать фото"),
                isPresented: $showImageSourcePicker,
                titleVisibility: .visible
            ) {
                Button(loc(appLanguage, "Camera", "Камера")) {
                    imageSourceType = .camera
                    showImagePicker = true
                }
                Button(loc(appLanguage, "Photo Library", "Галерея")) {
                    imageSourceType = .photoLibrary
                    showImagePicker = true
                }
                Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) { }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $avatarImage, sourceType: imageSourceType)
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerView(
                    selectedCountryCode: $selectedCountryCode,
                    countries: countries,
                    appLanguage: appLanguage
                )
            }
        }
    }
    
    private func countryFlag(_ countryCode: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(String(unicode))
            }
        }
        return flag
    }
    
    private func loadCurrentProfile() {
        if let user = authService.currentUser {
            nickname = user.nickname ?? ""
            if let storedCountry = user.country, countries.contains(where: { $0.code == storedCountry }) {
                selectedCountryCode = storedCountry
            } else {
                selectedCountryCode = user.country ?? ""
            }
            if let data = user.avatarData, let image = UIImage(data: data) {
                avatarImage = image
            } else {
                avatarImage = nil
            }
        }
    }
    
    private func saveProfile() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.75)
        
        authService.updateProfile(
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            country: selectedCountryCode.isEmpty ? nil : selectedCountryCode,
            avatarData: avatarData
        )
    }
    
    @MainActor
    private func saveProfileAsync() async {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.75)
        
        isSaving = true
        saveError = nil
        
        do {
            try await authService.updateProfileAsync(
                nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
                country: selectedCountryCode.isEmpty ? nil : selectedCountryCode,
                avatarData: avatarData
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        
        isSaving = false
    }
}

// MARK: - Country Picker View

struct CountryPickerView: View {
    @Binding var selectedCountryCode: String
    let countries: [(code: String, name: String)]
    let appLanguage: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    
    private var filteredCountries: [(code: String, name: String)] {
        if searchText.isEmpty {
            return countries
        }
        return countries.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredCountries, id: \.code) { country in
                    Button {
                        selectedCountryCode = country.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedCountryCode == country.code {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: loc(appLanguage, "Search country", "Поиск страны"))
            .navigationTitle(loc(appLanguage, "Select Country", "Выбор страны"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel", "Отмена")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func countryFlag(_ countryCode: String) -> String {
        let base: UInt32 = 127397
        var flag = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            if let unicode = UnicodeScalar(base + scalar.value) {
                flag.append(String(unicode))
            }
        }
        return flag
    }
}

// MARK: - Profile Location Manager

import CoreLocation

class ProfileLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var completion: ((String?) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    func requestCountryCode(completion: @escaping (String?) -> Void) {
        self.completion = completion
        self.errorMessage = nil
        self.isLoading = true
        
        let status = manager.authorizationStatus
        
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Location access denied. Enable in Settings."
            completion(nil)
        @unknown default:
            isLoading = false
            completion(nil)
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied {
            isLoading = false
            errorMessage = "Location access denied"
            completion?(nil)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isLoading = false
            completion?(nil)
            return
        }
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    self?.completion?(nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    self?.completion?(nil)
                    return
                }
                
                let countryCode = placemark.isoCountryCode
                
                self?.completion?(countryCode)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            
            // Provide user-friendly error messages
            let nsError = error as NSError
            if nsError.domain == kCLErrorDomain {
                switch CLError.Code(rawValue: nsError.code) {
                case .locationUnknown:
                    self.errorMessage = "Could not determine location. Try again or select manually."
                case .denied:
                    self.errorMessage = "Location access denied. Enable in Settings."
                case .network:
                    self.errorMessage = "Network error. Check your connection."
                default:
                    self.errorMessage = "Location error. Please select country manually."
                }
            } else {
                self.errorMessage = error.localizedDescription
            }
            
            self.completion?(nil)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let edited = info[.editedImage] as? UIImage {
                parent.image = edited
            } else if let original = info[.originalImage] as? UIImage {
                parent.image = original
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
