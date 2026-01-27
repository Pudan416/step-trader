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
        .init(name: "YouTube", scheme: "youtube://", icon: "▶️", imageName: "youtube", link: nil, bundleId: "com.google.ios.youtube"),
        .init(name: "Instagram", scheme: "instagram://", icon: "📸", imageName: "instagram", link: nil, bundleId: "com.burbn.instagram"),
        .init(name: "TikTok", scheme: "tiktok://", icon: "🎵", imageName: "tiktok", link: nil, bundleId: "com.zhiliaoapp.musically"),
        .init(name: "Telegram", scheme: "tg://", icon: "✈️", imageName: "telegram", link: nil, bundleId: "ph.telegra.Telegraph"),
        .init(name: "WhatsApp", scheme: "whatsapp://", icon: "💬", imageName: "whatsapp", link: nil, bundleId: "net.whatsapp.WhatsApp"),
        .init(name: "Snapchat", scheme: "snapchat://", icon: "👻", imageName: "snapchat", link: nil, bundleId: "com.toyopagroup.picaboo"),
        .init(name: "Facebook", scheme: "fb://", icon: "📘", imageName: "facebook", link: nil, bundleId: "com.facebook.Facebook"),
        .init(name: "LinkedIn", scheme: "linkedin://", icon: "💼", imageName: "linkedin", link: nil, bundleId: "com.linkedin.LinkedIn"),
        .init(name: "X (Twitter)", scheme: "twitter://", icon: "🐦", imageName: "x", link: nil, bundleId: "com.atebits.Tweetie2"),
        .init(name: "Reddit", scheme: "reddit://", icon: "👽", imageName: "reddit", link: nil, bundleId: "com.reddit.Reddit"),
        .init(name: "Pinterest", scheme: "pinterest://", icon: "📌", imageName: "pinterest", link: nil, bundleId: "com.pinterest"),
        
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
            .alert(loc(appLanguage, "Restore from iCloud"), isPresented: $showRestoreAlert) {
                Button(loc(appLanguage, "Cancel"), role: .cancel) { }
                Button(loc(appLanguage, "Restore"), role: .destructive) {
                    Task { await cloudService.restoreFromCloud(model: model) }
                }
            } message: {
                Text(loc(appLanguage, "This will replace your current shields and progress with data from iCloud."))
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
                Text(loc(appLanguage, "Command Center"))
                    .font(.headline)
                Text(loc(appLanguage, "Tweak everything here ⚙️"))
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
            sectionHeaderEdgy(icon: "person.fill", title: loc(appLanguage, "Identity"), subtitle: loc(appLanguage, "Who are you, warrior?"), color: pink)
            
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
                        Text(loc(appLanguage, "Leave"))
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
                            Text(loc(appLanguage, "Join the game"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(loc(appLanguage, "Sign in to sync progress 🔄"))
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
                title: loc(appLanguage, "Cloud Backup"),
                subtitle: loc(appLanguage, "Never lose your progress ☁️"),
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
                    Text(cloudService.isCloudKitAvailable ? loc(appLanguage, "Online") : loc(appLanguage, "Offline"))
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
                            Text(loc(appLanguage, "Sync"))
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
                            Text(loc(appLanguage, "Restore"))
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
                title: loc(appLanguage, "Preferences"),
                subtitle: loc(appLanguage, "Make it yours 🎨"),
                color: .purple
            )
            
            VStack(spacing: 0) {
                // Theme
                NavigationLink {
                    ThemeSettingsView(appLanguage: appLanguage, selectedTheme: $appThemeRaw)
                        .navigationTitle(loc(appLanguage, "Theme"))
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
                        
                        Text(loc(appLanguage, "Theme"))
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
                    .navigationTitle(loc(appLanguage, "Entry Screen"))
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
                        
                        Text(loc(appLanguage, "Entry Screen"))
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
                
                Divider()
                    .padding(.leading, 58)
                
                NavigationLink {
                    EnergySetupView(model: model)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "bolt.heart.fill")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                        
                        Text(loc(appLanguage, "Daily setup"))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
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
            
            Text(loc(appLanguage, "Built with 💜 for bloody meantal health"))
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
                Picker(loc(appLanguage, "Theme"), selection: $selectedTheme) {
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
                    Text(loc(appLanguage, "Choose your entry screen style"))
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
                    loc(appLanguage, "End of day"),
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

