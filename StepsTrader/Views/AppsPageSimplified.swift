import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import Foundation

struct ShieldGroupId: Identifiable {
    let id: String
}

struct AppsPageSimplified: View {
    @ObservedObject var model: AppModel
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: ShieldGroupId? = nil
    @State private var showTemplatePicker = false
    @State private var showDifficultyPicker = false
    @State private var pendingGroupIdForDifficulty: String? = nil
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerSection
                        shieldsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPicker, onDismiss: {
                // If picker was dismissed without adding apps, remove empty group
                if let groupId = selectedGroupId {
                    if let group = model.shieldGroups.first(where: { $0.id == groupId.id }) {
                        let hasApps = !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
                        if !hasApps {
                            model.deleteShieldGroup(groupId.id)
                        }
                    }
                    selectedGroupId = nil
                }
            }) {
                #if canImport(FamilyControls)
                AppSelectionSheet(
                    selection: $selection,
                    appLanguage: appLanguage,
                    templateApp: selectedGroupId.flatMap { groupId in
                        model.shieldGroups.first(where: { $0.id == groupId.id })?.templateApp
                    },
                    onDone: {
                        if let groupId = selectedGroupId {
                            let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                            if hasApps {
                                model.addAppsToGroup(groupId.id, selection: selection)
                                // Check if this is a template shield and show difficulty picker
                                if let group = model.shieldGroups.first(where: { $0.id == groupId.id }),
                                   group.templateApp != nil {
                                    pendingGroupIdForDifficulty = groupId.id
                                    showPicker = false
                                    showDifficultyPicker = true
                                } else {
                                    showPicker = false
                                    selectedGroupId = nil
                                }
                            } else {
                                // Remove group if no apps were added
                                model.deleteShieldGroup(groupId.id)
                                showPicker = false
                                selectedGroupId = nil
                            }
                        } else {
                            model.syncFamilyControlsCards(from: selection)
                            showPicker = false
                            selectedGroupId = nil
                        }
                    }
                )
                #else
                Text("Family Controls not available")
                    .padding()
                #endif
            }
            .sheet(isPresented: $showDifficultyPicker) {
                if let groupId = pendingGroupIdForDifficulty,
                   let group = model.shieldGroups.first(where: { $0.id == groupId }) {
                    DifficultyPickerView(
                        model: model,
                        group: group,
                        appLanguage: appLanguage,
                        onDone: {
                            showDifficultyPicker = false
                            pendingGroupIdForDifficulty = nil
                            selectedGroupId = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                ShieldTemplatePickerView(
                    model: model,
                    appLanguage: appLanguage,
                    onTemplateSelected: { templateApp in
                        showTemplatePicker = false
                        // Create group with template, then open app picker
                        let displayName = TargetResolver.displayName(for: templateApp)
                        let group = model.createShieldGroup(name: displayName, templateApp: templateApp)
                        // Set selection to current selection and open picker
                        selection = FamilyActivitySelection()
                        selectedGroupId = ShieldGroupId(id: group.id)
                        showPicker = true
                    },
                    onCustomSelected: {
                        showTemplatePicker = false
                        // Create group without template, then open app picker
                        let group = model.createShieldGroup(name: loc(appLanguage, "New Shield"))
                        selection = FamilyActivitySelection()
                        selectedGroupId = ShieldGroupId(id: group.id)
                        showPicker = true
                    }
                )
            }
            .sheet(item: $selectedGroupId) { groupIdWrapper in
                if let group = model.shieldGroups.first(where: { $0.id == groupIdWrapper.id }) {
                    ShieldGroupSettingsView(
                        model: model,
                        group: group,
                        appLanguage: appLanguage
                    )
                } else {
                    Text("Error: Shield group not found")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .onAppear {
                selection = model.appSelection
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(loc(appLanguage, "Shields"))
                .font(.title.weight(.bold))
            
            Text(loc(appLanguage, "Manage your app protection"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
    
    // MARK: - Shields Section
    @ViewBuilder
    private var shieldsSection: some View {
        if model.shieldGroups.isEmpty {
            emptyShieldsPlaceholder
        } else {
            shieldsGrid
        }
    }
    
    private var emptyShieldsPlaceholder: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.brandPink.opacity(0.2), AppColors.brandPink.opacity(0.05)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.brandPink, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text(loc(appLanguage, "No shields yet"))
                    .font(.title3.weight(.semibold))
                
                Text(loc(appLanguage, "Create your first shield to protect apps from yourself"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            // Create button
            Button {
                showTemplatePicker = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.headline)
                    Text(loc(appLanguage, "Create Shield"))
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AppColors.brandPink, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: AppColors.brandPink.opacity(0.4), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
        .background(glassCard)
    }
    
    @ViewBuilder
    private var shieldsGrid: some View {
        VStack(spacing: 10) {
            ForEach(model.shieldGroups.filter { group in
                // Only show groups that have apps added
                group.selection.applicationTokens.count > 0 || group.selection.categoryTokens.count > 0
            }) { group in
                ShieldCardView(
                    model: model,
                    group: group,
                    appLanguage: appLanguage,
                    onEdit: {
                        selectedGroupId = ShieldGroupId(id: group.id)
                    }
                )
            }
            
            // Add new shield card
            addShieldCard
        }
    }
    
    private var addShieldCard: some View {
        Button {
            showTemplatePicker = true
        } label: {
            HStack(spacing: 12) {
                // Plus icon in circle
                ZStack {
                    Circle()
                        .fill(AppColors.brandPink.opacity(0.12))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.brandPink)
                }
                
                Text(loc(appLanguage, "New Shield"))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .foregroundColor(AppColors.brandPink.opacity(0.3))
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            Color(.systemGroupedBackground)
            
            // Accent gradient orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColors.brandPink.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(x: -100, y: -200)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.purple.opacity(0.06), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: 150, y: 100)
        }
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Shield Template Picker
struct ShieldTemplatePickerView: View {
    @ObservedObject var model: AppModel
    let appLanguage: String
    let onTemplateSelected: (String) -> Void
    let onCustomSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private struct Template {
        let bundleId: String
        let name: String
        let imageName: String
    }
    
    private let allTemplates: [Template] = [
        Template(bundleId: "com.burbn.instagram", name: "Instagram", imageName: "instagram"),
        Template(bundleId: "com.zhiliaoapp.musically", name: "TikTok", imageName: "tiktok"),
        Template(bundleId: "com.google.ios.youtube", name: "YouTube", imageName: "youtube"),
        Template(bundleId: "com.toyopagroup.picaboo", name: "Snapchat", imageName: "snapchat"),
        Template(bundleId: "com.reddit.Reddit", name: "Reddit", imageName: "reddit"),
        Template(bundleId: "com.atebits.Tweetie2", name: "X", imageName: "x"),
        Template(bundleId: "com.duolingo.DuolingoMobile", name: "Duolingo", imageName: "duolingo"),
        Template(bundleId: "com.facebook.Facebook", name: "Facebook", imageName: "facebook"),
        Template(bundleId: "com.linkedin.LinkedIn", name: "LinkedIn", imageName: "linkedin"),
        Template(bundleId: "com.pinterest", name: "Pinterest", imageName: "pinterest"),
        Template(bundleId: "ph.telegra.Telegraph", name: "Telegram", imageName: "telegram"),
        Template(bundleId: "net.whatsapp.WhatsApp", name: "WhatsApp", imageName: "whatsapp")
    ]
    
    // Filter out templates that are already used
    private var availableTemplates: [Template] {
        let usedTemplateApps = Set(model.shieldGroups.compactMap { $0.templateApp })
        return allTemplates.filter { !usedTemplateApps.contains($0.bundleId) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Custom shield option
                    Button {
                        onCustomSelected()
                    } label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [AppColors.brandPink.opacity(0.15), AppColors.brandPink.opacity(0.08)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(AppColors.brandPink)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc(appLanguage, "Custom Shield"))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text(loc(appLanguage, "Choose your own apps"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(AppColors.brandPink.opacity(0.3), lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Templates section
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loc(appLanguage, "Templates"))
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                        
                        if availableTemplates.isEmpty {
                            Text(loc(appLanguage, "All templates are already in use"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(availableTemplates, id: \.bundleId) { template in
                                    templateCard(template: template)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc(appLanguage, "New Shield"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func templateCard(template: Template) -> some View {
        Button {
            onTemplateSelected(template.bundleId)
        } label: {
            VStack(spacing: 8) {
                // Large app icon
                if let uiImage = UIImage(named: template.imageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "app.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary)
                        )
                }
                
                Text(template.name)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shield Card View
struct ShieldCardView: View {
    @ObservedObject var model: AppModel
    let group: AppModel.ShieldGroup
    let appLanguage: String
    let onEdit: () -> Void
    @State private var remainingTime: TimeInterval? = nil
    @State private var timer: Timer? = nil
    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    private var isActive: Bool {
        group.settings.familyControlsModeEnabled || group.settings.minuteTariffEnabled
    }
    
    private var isUnlocked: Bool {
        model.isGroupUnlocked(group.id)
    }
    
    private var dynamicCardColor: Color {
        // If unlocked, calculate color based on remaining time
        if isUnlocked, let remaining = remainingTime {
            // Use remaining time in seconds to determine color
            // Green for > 30 min, yellow for 5-30 min, red for < 5 min
            let remainingMinutes = remaining / 60.0
            
            if remainingMinutes > 30 {
                // Green - plenty of time
                return .green
            } else if remainingMinutes > 5 {
                // Yellow to orange - moderate time
                let factor = (remainingMinutes - 5) / 25.0 // 0 to 1
                return Color(
                    red: 1.0,
                    green: 0.5 + (factor * 0.5),
                    blue: 0
                )
            } else {
                // Orange to red - low time
                let factor = remainingMinutes / 5.0 // 0 to 1
                return Color(
                    red: 1.0,
                    green: factor * 0.5,
                    blue: 0
                )
            }
        }
        
        // If active but not unlocked, use neutral gray
        if isActive { return .gray }
        return .gray
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: 12) {
                // Left: App icon
                appIconsStack
                    .frame(width: 52, height: 52)
                
                // Center: Title + Status
                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(shieldTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // Apps count (only if > 1)
                    if appsCount > 1 {
                        HStack(spacing: 3) {
                            Image(systemName: "app.fill")
                                .font(.caption2)
                            Text("\(appsCount) apps")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // Status: "under control" or "open for ##:##"
                    statusLabel
                }
                
                Spacer()
                
                // Right: Difficulty + Chevron
                VStack(alignment: .trailing, spacing: 8) {
                    difficultyBadge
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(12)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .onAppear {
            updateRemainingTime()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                updateRemainingTime()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
    
    private var statusLabel: some View {
        Group {
            if isUnlocked, let remaining = remainingTime {
                // Open state with timer
                HStack(spacing: 4) {
                    Circle()
                        .fill(dynamicCardColor)
                        .frame(width: 6, height: 6)
                    Text("open for \(formatRemainingTimeShort(remaining))")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundColor(dynamicCardColor)
            } else {
                // Locked state
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("under control")
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(.green)
            }
        }
    }
    
    private func formatRemainingTimeShort(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var shieldTitle: String {
        // If template app is set, use its display name
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        
        #if canImport(FamilyControls)
        let defaults = UserDefaults(suiteName: "group.personal-project.StepsTrader") ?? .standard
        
        if appsCount == 1 {
            if let firstToken = group.selection.applicationTokens.first,
               let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: firstToken, requiringSecureCoding: true) {
                let tokenKey = "fc_appName_" + tokenData.base64EncodedString()
                if let name = defaults.string(forKey: tokenKey) {
                    return name
                }
            }
            if !group.selection.categoryTokens.isEmpty {
                return "Category"
            }
        }
        #endif
        
        if appsCount == 0 {
            return loc(appLanguage, "Empty Shield")
        }
        return "\(appsCount) \(appsCount == 1 ? "app" : "apps")"
    }
    
    private var difficultyBadge: some View {
        let color = difficultyColor(for: group.difficultyLevel)
        let label = difficultyLabelShort(for: group.difficultyLevel)
        
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
    
    private var appIconsStack: some View {
        ZStack {
            // Template app - show icon from assets
            if let templateApp = group.templateApp {
                if let imageName = templateImageName(for: templateApp),
                   let uiImage = UIImage(named: imageName) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "app.fill")
                                .foregroundColor(.secondary)
                        )
                }
            } else {
                #if canImport(FamilyControls)
                let appTokens = Array(group.selection.applicationTokens.prefix(1))
                let categoryTokens = Array(group.selection.categoryTokens.prefix(appTokens.isEmpty ? 1 : 0))
                
                if appTokens.isEmpty && categoryTokens.isEmpty {
                    // Empty state
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemBackground))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "app.dashed")
                                .font(.system(size: 20))
                                .foregroundColor(.secondary.opacity(0.5))
                        )
                } else if let firstToken = appTokens.first {
                    // Single app icon
                    AppIconView(token: firstToken)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                } else if let firstCategory = categoryTokens.first {
                    // Category icon
                    CategoryIconView(token: firstCategory)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                #endif
            }
        }
    }
    
    private func templateImageName(for bundleId: String) -> String? {
        switch bundleId {
        case "com.burbn.instagram": return "instagram"
        case "com.zhiliaoapp.musically": return "tiktok"
        case "com.google.ios.youtube": return "youtube"
        case "com.toyopagroup.picaboo": return "snapchat"
        case "com.reddit.Reddit": return "reddit"
        case "com.atebits.Tweetie2": return "x"
        case "com.duolingo.DuolingoMobile": return "duolingo"
        case "com.facebook.Facebook": return "facebook"
        case "com.linkedin.LinkedIn": return "linkedin"
        case "com.pinterest": return "pinterest"
        case "ph.telegra.Telegraph": return "telegram"
        case "net.whatsapp.WhatsApp": return "whatsapp"
        default: return nil
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isUnlocked ? dynamicCardColor.opacity(0.5) : Color.primary.opacity(0.08),
                        lineWidth: isUnlocked ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
    
    private func updateRemainingTime() {
        remainingTime = model.remainingUnlockTime(for: group.id)
    }
    
    private func formatRemainingTime(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = Int(timeInterval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func difficultyLabelShort(for level: Int) -> String {
        switch level {
        case 1: return "Rookie"
        case 2: return "Rebel"
        case 3: return "Fighter"
        case 4: return "Warrior"
        case 5: return "Legend"
        default: return "Fighter"
        }
    }
}

// MARK: - Difficulty Picker View
struct DifficultyPickerView: View {
    @ObservedObject var model: AppModel
    @State var group: AppModel.ShieldGroup
    let appLanguage: String
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text(loc(appLanguage, "Choose Difficulty Level"))
                            .font(.title2.weight(.bold))
                        Text(loc(appLanguage, "Higher difficulty means higher energy cost"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Difficulty options
                    VStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { level in
                            difficultyOption(level: level)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Cost preview
                    if group.difficultyLevel > 0 {
                        costPreviewSection
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) {
                        model.updateShieldGroup(group)
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func difficultyOption(level: Int) -> some View {
        let isSelected = group.difficultyLevel == level
        let color = difficultyColor(for: level)
        let label = difficultyLabel(for: level)
        
        return Button {
            withAnimation {
                group.difficultyLevel = level
            }
        } label: {
            HStack(spacing: 16) {
                // Level indicator
                ZStack {
                    Circle()
                        .fill(isSelected ? color : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(level)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Label and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(difficultyDescription(for: level))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? color.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var costPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Energy Cost Preview"))
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach([AccessWindow.minutes5, .minutes30, .hour1], id: \.self) { interval in
                    VStack(spacing: 4) {
                        Text(interval.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                            Text("\(group.cost(for: interval))")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(difficultyColor(for: group.difficultyLevel))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(difficultyColor(for: group.difficultyLevel).opacity(0.1))
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }
    
    private func difficultyColor(for level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return .blue
        case 3: return .orange
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
    
    private func difficultyLabel(for level: Int) -> String {
        switch level {
        case 1: return loc(appLanguage, "Rookie")
        case 2: return loc(appLanguage, "Rebel")
        case 3: return loc(appLanguage, "Fighter")
        case 4: return loc(appLanguage, "Warrior")
        case 5: return loc(appLanguage, "Legend")
        default: return loc(appLanguage, "Fighter")
        }
    }
    
    private func difficultyDescription(for level: Int) -> String {
        switch level {
        case 1: return loc(appLanguage, "Lowest energy cost")
        case 2: return loc(appLanguage, "Low energy cost")
        case 3: return loc(appLanguage, "Moderate energy cost")
        case 4: return loc(appLanguage, "High energy cost")
        case 5: return loc(appLanguage, "Highest energy cost")
        default: return ""
        }
    }
}

// MARK: - Legacy Views (kept for compatibility)

struct ShieldGroupCardView: View {
    @ObservedObject var model: AppModel
    let group: AppModel.ShieldGroup
    let appLanguage: String
    let span: Int
    let onEdit: () -> Void
    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            VStack(spacing: 8) {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(appsCount) apps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct LegacyShieldCardView: View {
    @ObservedObject var model: AppModel
    let cardId: String
    let settings: AppModel.AppUnlockSettings
    let appLanguage: String

    private var selection: FamilyActivitySelection {
        model.timeAccessSelection(for: cardId)
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "shield.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.appDisplayName(for: cardId))
                    .font(.headline)
                Text("Shield")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}
