import SwiftUI

// MARK: - Me tab: who you are + your journey
struct MeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService = AuthenticationService.shared
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var selectedDayKey: String? = nil
    @State private var showSettings = false
    @State private var showLogin = false
    @State private var showProfileEditor = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Profile
                    profileSection
                    
                    // Journey / calendar
                    journeySection
                    
                    // Stats
                    statsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemBackground))
            .navigationTitle(loc(appLanguage, "You"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onAppear {
                loadAllSnapshots()
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(model: model, appLanguage: appLanguage) {
                    showSettings = false
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
            .sheet(item: Binding(
                get: { selectedDayKey.map { MeDayKeyWrapper(key: $0) } },
                set: { selectedDayKey = $0?.key }
            )) { wrapper in
                ChoiceDayDetailSheet(
                    model: model,
                    dayKey: wrapper.key,
                    snapshot: pastDays[wrapper.key],
                    appLanguage: appLanguage,
                    onDismiss: { selectedDayKey = nil }
                )
            }
        }
    }
    
    // MARK: - Data Loading
    private func loadAllSnapshots() {
        // Start with local data
        pastDays = model.loadPastDaySnapshots()
        
        // Then load from Supabase and merge
        Task {
            let serverSnapshots = await SupabaseSyncService.shared.loadHistoricalSnapshots()
            await MainActor.run {
                // Merge: server data fills gaps, local data takes priority for same day
                for (dayKey, snapshot) in serverSnapshots {
                    if pastDays[dayKey] == nil {
                        pastDays[dayKey] = snapshot
                    }
                }
            }
        }
    }
    
    // MARK: - Profile
    private var profileSection: some View {
        VStack(spacing: 16) {
            if authService.isAuthenticated, let user = authService.currentUser {
                // Avatar
                Button { showProfileEditor = true } label: {
                    avatarView(user: user)
                }
                .buttonStyle(.plain)
                
                Text(user.displayName)
                    .font(.title3.weight(.semibold))
                
                if let location = user.locationString {
                    Text(location)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(loc(appLanguage, "Living your life"))
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))
            } else {
                // Not signed in
                Button { showLogin = true } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 72, height: 72)
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                        }
                        Text(loc(appLanguage, "Sign in"))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
    
    @ViewBuilder
    private func avatarView(user: AppUser) -> some View {
        if let data = user.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Text(String(user.displayName.prefix(2)).uppercased())
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Journey (calendar)
    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Your days"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            
            MemoriesSection(
                pastDays: pastDays,
                selectedDayKey: $selectedDayKey,
                appLanguage: appLanguage
            )
        }
    }
    
    // MARK: - Stats
    private var statsSection: some View {
        let totalSpent = model.appStepsSpentLifetime.values.reduce(0, +)
        let daysCount = pastDays.count
        
        return VStack(spacing: 16) {
            HStack(spacing: 24) {
                statItem(value: "\(daysCount)", label: loc(appLanguage, "days tracked"))
                statItem(value: "\(totalSpent)", label: loc(appLanguage, "control spent"))
            }
        }
        .padding(.vertical, 16)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

// MARK: - Settings Sheet (minimal, clean)
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    let appLanguage: String
    let onDone: () -> Void
    @ObservedObject var authService = AuthenticationService.shared
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("payGateBackgroundStyle") private var payGateBackgroundStyle: String = "midnight"
    @State private var showLogin = false
    
    var body: some View {
        NavigationStack {
            List {
                // Account
                Section {
                    if authService.isAuthenticated, let user = authService.currentUser {
                        HStack(spacing: 12) {
                            avatarSmall(user: user)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.medium))
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        
                        Button(role: .destructive) {
                            authService.signOut()
                        } label: {
                            Label(loc(appLanguage, "Sign out"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } else {
                        Button { showLogin = true } label: {
                            Label(loc(appLanguage, "Sign in with Apple"), systemImage: "apple.logo")
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Account"))
                }
                
                // Preferences
                Section {
                    NavigationLink {
                        ThemePicker(appLanguage: appLanguage, selected: $appThemeRaw)
                    } label: {
                        HStack {
                            Label(loc(appLanguage, "Appearance"), systemImage: "circle.lefthalf.filled")
                            Spacer()
                            Text(themeLabel)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        EnergySetupView(model: model)
                    } label: {
                        Label(loc(appLanguage, "Daily choices"), systemImage: "sparkles")
                    }
                } header: {
                    Text(loc(appLanguage, "Preferences"))
                }
                
                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(loc(appLanguage, "About"))
                } footer: {
                    Text(loc(appLanguage, "Less scrolling. More living."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc(appLanguage, "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) { onDone() }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
        }
    }
    
    private var themeLabel: String {
        let theme = AppTheme.normalized(rawValue: appThemeRaw)
        return appLanguage == "ru" ? theme.displayNameRu : theme.displayNameEn
    }
    
    @ViewBuilder
    private func avatarSmall(user: AppUser) -> some View {
        if let data = user.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Text(String(user.displayName.prefix(2)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(.accentColor)
            }
        }
    }
}

// MARK: - Theme Picker
private struct ThemePicker: View {
    let appLanguage: String
    @Binding var selected: String
    
    var body: some View {
        List {
            ForEach(AppTheme.selectableThemes, id: \.rawValue) { theme in
                Button {
                    selected = theme.rawValue
                } label: {
                    HStack {
                        Text(appLanguage == "ru" ? theme.displayNameRu : theme.displayNameEn)
                            .foregroundColor(.primary)
                        Spacer()
                        if selected == theme.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(loc(appLanguage, "Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MeView(model: DIContainer.shared.makeAppModel())
}
