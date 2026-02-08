import SwiftUI

// MARK: - Me tab: who I am + my journey
struct MeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService = AuthenticationService.shared
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.appTheme) private var theme
    @State private var pastDays: [String: PastDaySnapshot] = [:]
    @State private var selectedDayKey: String? = nil
    @State private var showLogin = false
    @State private var showProfileEditor = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Profile header - centered, large avatar
                profileHeaderSection
                    .padding(.top, 12)
                
                Divider()
                    .padding(.vertical, 10)
                
                // Main content (no scroll)
                VStack(spacing: 16) {
                    // Last 7 days horizontal with yellow fill
                    compactJourneySection
                    
                    // Top gallery - large like on gallery screen
                    largeTopGallerySection
                    
                    Spacer()
                    
                    // Stats grid - small at bottom
                    smallStatsSection
                        .padding(.bottom, 80)
                }
                .padding(.horizontal, 16)
            }
            .background(theme.backgroundColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadAllSnapshots()
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
                GalleryDayDetailSheet(
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
    
    // MARK: - Profile Header (centered, large)
    private var profileHeaderSection: some View {
        Button {
            if authService.isAuthenticated {
                showProfileEditor = true
            } else {
                showLogin = true
            }
        } label: {
            VStack(spacing: 8) {
                if authService.isAuthenticated, let user = authService.currentUser {
                    largeAvatarView(user: user)
                    
                    let countryName = countryNameFromLocation(user.locationString)
                    if let country = countryName {
                        (Text("I am ")
                            .font(.subheadline.weight(.regular))
                            .foregroundColor(.secondary) +
                         Text(user.displayName)
                            .font(.reenie(30, relativeTo: .subheadline))
                            .foregroundColor(.primary) +
                         Text(" from ")
                            .font(.subheadline.weight(.regular))
                            .foregroundColor(.secondary) +
                         Text(country)
                            .font(.reenie(30, relativeTo: .subheadline))
                            .foregroundColor(.primary))
                    } else {
                        (Text("I am ")
                            .font(.subheadline.weight(.regular))
                            .foregroundColor(.secondary) +
                         Text(user.displayName)
                            .font(.reenie(16, relativeTo: .subheadline))
                            .foregroundColor(.primary))
                    }
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                    }
                    Text(loc(appLanguage, "Sign in"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func countryNameFromLocation(_ locationString: String?) -> String? {
        guard let location = locationString else { return nil }
        // Extract country from "City, Country" format
        let components = location.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return components.count > 1 ? components.last : location
    }
    
    @ViewBuilder
    private func largeAvatarView(user: AppUser) -> some View {
        ZStack {
            if let data = user.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .grayscale(1.0)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 64, height: 64)
                    Text(String(user.displayName.prefix(2)).uppercased())
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                }
            }
            
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .frame(width: 64, height: 64)
        }
    }
    
    // MARK: - Compact Journey (last 7 days horizontal)
    private var compactJourneySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc(appLanguage, "Last 7 days"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(last7DayKeys, id: \.self) { dayKey in
                    compactDayCircle(dayKey: dayKey)
                }
                if last7DayKeys.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func compactDayCircle(dayKey: String) -> some View {
        Button {
            selectedDayKey = dayKey
        } label: {
            let snapshot = pastDays[dayKey]
            
            VStack(spacing: 3) {
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.primary, lineWidth: 1)
                        .frame(width: 36, height: 36)
                    
                    // Yellow fill based on experience balance
                    if let snap = snapshot {
                        let gained = snap.controlGained
                        let spent = snap.controlSpent
                        let remaining = max(0, gained - spent)
                        
                        // Assume max energy = 100 for percentage
                        let maxEnergy = 100.0
                        let remainingProgress = min(1.0, Double(remaining) / maxEnergy)
                        let gainedProgress = min(1.0, Double(gained) / maxEnergy)
                        let spentProgress = max(0, gainedProgress - remainingProgress)
                        
                        GeometryReader { proxy in
                            let size = proxy.size.width
                            
                            ZStack {
                                // Yellow fill (remaining)
                                if remainingProgress > 0 {
                                    Circle()
                                        .trim(from: 0, to: remainingProgress)
                                        .stroke(Color.yellow, lineWidth: 3)
                                        .frame(width: size - 3, height: size - 3)
                                        .rotationEffect(.degrees(-90))
                                }
                                
                                // Yellow outline only (spent)
                                if spentProgress > 0 {
                                    Circle()
                                        .trim(from: remainingProgress, to: gainedProgress)
                                        .stroke(Color.yellow.opacity(0.3), lineWidth: 3)
                                        .frame(width: size - 3, height: size - 3)
                                        .rotationEffect(.degrees(-90))
                                }
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                }
                
                Text(dayLabel(from: dayKey))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func dayLabel(from dayKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return "" }
        
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: appLanguage == "ru" ? "ru" : "en")
        return String(formatter.string(from: date).prefix(3))
    }

    // MARK: - Top activity/rest/joy (last 7 days)
    private var last7DayKeys: [String] {
        let keys = pastDays.keys.sorted(by: <)
        return Array(keys.suffix(7))
    }

    private func topOptionId(for category: EnergyCategory, from snapshots: [PastDaySnapshot]) -> String? {
        var counts: [String: Int] = [:]
        for s in snapshots {
            let ids: [String] = switch category {
            case .activity: s.activityIds
            case .creativity: s.creativityIds
            case .joys: s.joysIds
            }
            for id in ids {
                counts[id, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func optionTitle(for optionId: String) -> String {
        if optionId.hasPrefix("custom_") {
            if let custom = model.customEnergyOptions.first(where: { $0.id == optionId }) {
                return appLanguage == "ru" ? custom.titleRu : custom.titleEn
            }
            return optionId
        }
        if let opt = EnergyDefaults.options.first(where: { $0.id == optionId }) {
            return opt.title(for: appLanguage)
        }
        return optionId
    }

    private func optionIcon(for optionId: String) -> String {
        if optionId.hasPrefix("custom_"),
           let custom = model.customEnergyOptions.first(where: { $0.id == optionId }) {
            return custom.icon
        }
        return EnergyDefaults.options.first(where: { $0.id == optionId })?.icon ?? "circle.fill"
    }

    /// Asset name for gallery images: option id is the image set name (e.g. activity_favourite_sport).
    private func assetImageName(for optionId: String) -> String {
        optionId
    }

    // MARK: - Large Top Gallery (like on gallery screen)
    private var largeTopGallerySection: some View {
        let snapshots = last7DayKeys.compactMap { pastDays[$0] }
        let topActivity = topOptionId(for: .activity, from: snapshots)
        let topCreativity = topOptionId(for: .creativity, from: snapshots)
        let topJoy = topOptionId(for: .joys, from: snapshots)

        return VStack(alignment: .leading, spacing: 8) {
            Text(loc(appLanguage, "Frequent activities"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                largeTopGalleryCard(
                    category: loc(appLanguage, "Activity"),
                    optionId: topActivity,
                    icon: "figure.run"
                )
                largeTopGalleryCard(
                    category: loc(appLanguage, "Creativity"),
                    optionId: topCreativity,
                    icon: "sparkles"
                )
                largeTopGalleryCard(
                    category: loc(appLanguage, "Joy"),
                    optionId: topJoy,
                    icon: "heart.fill"
                )
            }
        }
    }

    private func largeTopGalleryCard(category: String, optionId: String?, icon: String) -> some View {
        VStack(spacing: 6) {
            // Show image for option
            if let id = optionId {
                if id.hasPrefix("custom_") {
                    Image(systemName: optionIcon(for: id))
                        .font(.system(size: 40))
                        .foregroundColor(.primary)
                        .frame(width: 56, height: 56)
                } else {
                    Image(assetImageName(for: id))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                    .frame(width: 56, height: 56)
            }
            
            VStack(spacing: 2) {
                Text(category)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                if let id = optionId {
                    Text(optionTitle(for: id))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                } else {
                    Text("—")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Small Stats (at bottom)
    private var smallStatsSection: some View {
        let totalGained = pastDays.values.reduce(0) { $0 + $1.controlGained }
        let totalLost = pastDays.values.reduce(0) { $0 + $1.controlSpent }
        let daysCount = pastDays.count

        return HStack(spacing: 12) {
            smallStatItem(
                value: "\(daysCount)",
                label: loc(appLanguage, "Days")
            )
            
            Divider()
                .frame(height: 20)
            
            smallStatItem(
                value: "\(totalGained)",
                label: loc(appLanguage, "Gained")
            )
            
            Divider()
                .frame(height: 20)
            
            smallStatItem(
                value: "\(totalLost)",
                label: loc(appLanguage, "Spent")
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func smallStatItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MeDayKeyWrapper: Identifiable {
    let key: String
    var id: String { key }
}

// MARK: - Settings Sheet (minimal, clean; can be embedded in tab or presented as sheet)
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    let appLanguage: String
    var onDone: (() -> Void)? = nil
    /// When true, shown as a tab root — no Done button.
    var embeddedInTab: Bool = false
    @ObservedObject var authService = AuthenticationService.shared
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("payGateBackgroundStyle") private var payGateBackgroundStyle: String = "midnight"
    @Environment(\.appTheme) private var theme
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
                        Label(loc(appLanguage, "Daily gallery"), systemImage: "sparkles")
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
            .scrollContentBackground(.hidden)
            .background(theme.backgroundColor)
            .navigationTitle(loc(appLanguage, "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !embeddedInTab, let onDone = onDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(loc(appLanguage, "Done")) { onDone() }
                    }
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
