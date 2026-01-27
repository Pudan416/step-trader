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
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background with subtle gradient
                backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Shields Section
                        shieldsSection
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPicker) {
                #if canImport(FamilyControls)
                AppSelectionSheet(
                    selection: $selection,
                    appLanguage: appLanguage,
                    onDone: {
                        if let groupId = selectedGroupId {
                            model.addAppsToGroup(groupId.id, selection: selection)
                        } else {
                            model.syncFamilyControlsCards(from: selection)
                        }
                        showPicker = false
                        selectedGroupId = nil
                    }
                )
                #else
                Text("Family Controls not available")
                    .padding()
                #endif
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
    
    // MARK: - Shields Section
    @ViewBuilder
    private var shieldsSection: some View {
        let groupsCount = model.shieldGroups.count
        
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc(appLanguage, "Shields"))
                        .font(.title3.weight(.bold))
                    Text(loc(appLanguage, "\(groupsCount) shields protecting your apps"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                addShieldButtonCompact
            }
            .padding(.horizontal, 4)
            
            // Shields list
            if model.shieldGroups.isEmpty {
                emptyShieldsPlaceholder
            } else {
                shieldsList
            }
        }
    }
    
    private var addShieldButtonCompact: some View {
        Button {
            let group = model.createShieldGroup(name: loc(appLanguage, "New Shield"))
            selectedGroupId = ShieldGroupId(id: group.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text(loc(appLanguage, "Add"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyShieldsPlaceholder: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.05)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 50
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 6) {
                Text(loc(appLanguage, "No shields yet"))
                    .font(.headline)
                Text(loc(appLanguage, "Add your first shield to protect apps"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(glassCard)
    }
    
    @ViewBuilder
    private var shieldsList: some View {
        VStack(spacing: 12) {
            ForEach(model.shieldGroups) { group in
                ShieldRowView(
                    model: model,
                    group: group,
                    appLanguage: appLanguage,
                    onEdit: {
                        selectedGroupId = ShieldGroupId(id: group.id)
                    }
                )
            }
        }
    }
    
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            Color(.systemGroupedBackground)
            
            // Subtle gradient orbs
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.pink.opacity(0.08), Color.clear],
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
}

// MARK: - Shield Group Card View (Legacy - kept for compatibility)
struct ShieldGroupCardView: View {
    @ObservedObject var model: AppModel
    let group: AppModel.ShieldGroup
    let appLanguage: String
    let span: Int // 1 or 2
    let onEdit: () -> Void
    
    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            VStack(spacing: 0) {
                // Иконки приложений - главный элемент
                if span == 1 {
                    // 1x1 - одна большая иконка с информацией
                    VStack(spacing: 8) {
                        singleAppIcon
                            .frame(width: 64, height: 64)
                        
                        // Название группы или количество приложений
                        if appsCount > 1 {
                            Text("\(appsCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    // 2x1 - несколько иконок с информацией
                    VStack(spacing: 10) {
                        // Иконки приложений
                        multipleAppIcons
                            .frame(height: 50)
                        
                        // Информация о щите
                        HStack(spacing: 8) {
                            // Уровень сложности
                            HStack(spacing: 3) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(difficultyColor(for: group.difficultyLevel))
                                Text("\(group.difficultyLevel)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.primary)
                            }
                            
                            // Количество приложений
                            if appsCount > 4 {
                                Text("+\(appsCount - 4)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Индикатор активности
                            if group.settings.familyControlsModeEnabled || group.settings.minuteTariffEnabled {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: span == 2 ? 120 : 110)
            .padding(span == 2 ? 16 : 14)
            .background(glassCard)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        group.settings.familyControlsModeEnabled || group.settings.minuteTariffEnabled
                        ? Color.blue.opacity(0.3)
                        : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
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
    
    // MARK: - Single App Icon (1x1)
    @ViewBuilder
    private var singleAppIcon: some View {
        #if canImport(FamilyControls)
        if appsCount == 1, let firstToken = group.selection.applicationTokens.first {
            // Одно приложение - большая иконка
            AppIconView(token: firstToken)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        } else if appsCount > 1 {
            // Несколько приложений - показываем первые 2-3 в компактном виде
            HStack(spacing: -8) {
                ForEach(Array(group.selection.applicationTokens.prefix(3).enumerated()), id: \.element) { index, token in
                    AppIconView(token: token)
                        .frame(width: index == 0 ? 48 : 40, height: index == 0 ? 48 : 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                        .zIndex(Double(3 - index))
                }
                
                if appsCount > 3 {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            )
                        
                        Text("+\(appsCount - 3)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.primary)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    .zIndex(0)
                }
            }
        } else if !group.selection.categoryTokens.isEmpty {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.15), Color.blue.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                )
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        #else
        Image(systemName: "app.fill")
            .font(.system(size: 36, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: 64, height: 64)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        #endif
    }
    
    // MARK: - Multiple App Icons (2x1)
    private var multipleAppIcons: some View {
        HStack(spacing: 6) {
            #if canImport(FamilyControls)
            // Показываем до 4 иконок с эффектом наложения
            ForEach(Array(group.selection.applicationTokens.prefix(4).enumerated()), id: \.element) { index, token in
                AppIconView(token: token)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                    .zIndex(Double(4 - index))
            }
            
            // Если есть категории, показываем их тоже
            ForEach(Array(group.selection.categoryTokens.prefix(max(0, 4 - group.selection.applicationTokens.count)).enumerated()), id: \.element) { index, _ in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            
            // Показываем количество, если больше 4
            if appsCount > 4 {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .frame(width: 46, height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    
                    Text("+\(appsCount - 4)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                }
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            #else
            ForEach(0..<min(appsCount, 4), id: \.self) { _ in
                Image(systemName: "app.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 46, height: 46)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            #endif
        }
    }
    
    private var modeDescription: String {
        switch (group.settings.familyControlsModeEnabled, group.settings.minuteTariffEnabled) {
        case (true, true):
            return loc(appLanguage, "Shield + minute mode")
        case (true, false):
            return loc(appLanguage, "Shield enabled")
        case (false, true):
            return loc(appLanguage, "Minute mode only")
        default:
            return ""
        }
    }
    
    private var modeIcon: String {
        switch (group.settings.familyControlsModeEnabled, group.settings.minuteTariffEnabled) {
        case (true, true): return "shield.checkered"
        case (true, false): return "shield.fill"
        case (false, true): return "clock.fill"
        default: return ""
        }
    }
    
    private var modeColor: Color {
        switch (group.settings.familyControlsModeEnabled, group.settings.minuteTariffEnabled) {
        case (true, true): return .purple
        case (true, false): return .blue
        case (false, true): return .orange
        default: return .secondary
        }
    }
    
    private var groupIconGrid: some View {
        let totalItems = group.selection.applicationTokens.count + group.selection.categoryTokens.count
        let maxIcons = 4
        let count = min(maxIcons, max(totalItems, 1))

        return ZStack {
            #if canImport(FamilyControls)
            ForEach(Array(group.selection.applicationTokens.prefix(count).enumerated()), id: \.element) { index, token in
                let offsets = iconOffset(for: index, totalCount: min(count, group.selection.applicationTokens.count))
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        AppIconView(token: token)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: offsets.x, y: offsets.y)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            if group.selection.applicationTokens.count < count {
                let categoryStartIndex = group.selection.applicationTokens.count
                ForEach(Array(group.selection.categoryTokens.prefix(count - group.selection.applicationTokens.count).enumerated()), id: \.element) { offset, _ in
                    let index = categoryStartIndex + offset
                    let offsets = iconOffset(for: index, totalCount: count)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .offset(x: offsets.x, y: offsets.y)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            #else
            ForEach(0..<count, id: \.self) { index in
                let offsets = iconOffset(for: index, totalCount: count)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: offsets.x, y: offsets.y)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            #endif
        }
    }
    
    private func iconOffset(for index: Int, totalCount: Int) -> (x: CGFloat, y: CGFloat) {
        switch totalCount {
        case 1:
            return (0, 0)
        case 2:
            return (index == 0 ? -10 : 10, 0)
        case 3, 4:
            let row = index / 2
            let col = index % 2
            return (col == 0 ? -10 : 10, row == 0 ? -10 : 10)
        default:
            return (0, 0)
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
}

// MARK: - Shield Card View (Legacy)
struct ShieldCardView: View {
    @ObservedObject var model: AppModel
    let cardId: String
    let settings: AppModel.AppUnlockSettings
    let appLanguage: String

    private var selection: FamilyActivitySelection {
        model.timeAccessSelection(for: cardId)
    }

    private var isGroup: Bool {
        !selection.categoryTokens.isEmpty
    }

    private var title: String {
        let name = model.appDisplayName(for: cardId)
        if name == "Selected app", isGroup {
            return loc(appLanguage, "App group shield")
        } else {
            return name
        }
    }

    private var subtitle: String {
        let appsCount = selection.applicationTokens.count
        let catsCount = selection.categoryTokens.count

        if isGroup {
            if appsCount > 0 && catsCount > 0 {
                return loc(
                    appLanguage,
                    "\(appsCount) apps, \(catsCount) categories"
                )
            } else if catsCount > 0 {
                return loc(
                    appLanguage,
                    "\(catsCount) categories"
                )
            }
        }
        
        return loc(
            appLanguage,
            "Single app shield"
        )
    }

    private var modeDescription: String {
        switch (settings.familyControlsModeEnabled, settings.minuteTariffEnabled) {
        case (true, true):
            return loc(appLanguage, "Shield + minute mode")
        case (true, false):
            return loc(appLanguage, "Shield enabled")
        case (false, true):
            return loc(appLanguage, "Minute mode only")
        default:
            return ""
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Cover with app icons - improved design
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.9), .pink.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)

                iconGrid
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !modeDescription.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: modeIcon)
                            .font(.caption2)
                            .foregroundColor(modeColor)
                        Text(modeDescription)
                            .font(.caption.weight(.medium))
                            .foregroundColor(modeColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(modeColor.opacity(0.12))
                    )
                }
            }

            Spacer()
            
            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(16)
        .background(glassCard)
    }
    
    private var modeIcon: String {
        switch (settings.familyControlsModeEnabled, settings.minuteTariffEnabled) {
        case (true, true): return "shield.checkered"
        case (true, false): return "shield.fill"
        case (false, true): return "clock.fill"
        default: return ""
        }
    }
    
    private var modeColor: Color {
        switch (settings.familyControlsModeEnabled, settings.minuteTariffEnabled) {
        case (true, true): return .purple
        case (true, false): return .blue
        case (false, true): return .orange
        default: return .secondary
        }
    }
    
    // MARK: - Glass Card Style
    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
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

    // Простая "плитка" из иконок, максимум 4
    private var iconGrid: some View {
        let totalItems = selection.applicationTokens.count + selection.categoryTokens.count
        let maxIcons = 4
        let count = min(maxIcons, max(totalItems, 1))

        return ZStack {
            #if canImport(FamilyControls)
            ForEach(Array(selection.applicationTokens.prefix(count).enumerated()), id: \.element) { index, token in
                let offsets = iconOffset(for: index, totalCount: min(count, selection.applicationTokens.count))
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        AppIconView(token: token)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: offsets.x, y: offsets.y)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            // Если есть категории, показываем их иконки
            if selection.applicationTokens.count < count {
                let categoryStartIndex = selection.applicationTokens.count
                ForEach(Array(selection.categoryTokens.prefix(count - selection.applicationTokens.count).enumerated()), id: \.element) { offset, _ in
                    let index = categoryStartIndex + offset
                    let offsets = iconOffset(for: index, totalCount: count)
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .offset(x: offsets.x, y: offsets.y)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            #else
            // Fallback для случаев без FamilyControls
            ForEach(0..<count, id: \.self) { index in
                let offsets = iconOffset(for: index, totalCount: count)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "app.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .offset(x: offsets.x, y: offsets.y)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            #endif
        }
    }
    
    
    private func iconOffset(for index: Int, totalCount: Int) -> (x: CGFloat, y: CGFloat) {
        switch totalCount {
        case 1:
            return (0, 0)
        case 2:
            return (index == 0 ? -10 : 10, 0)
        case 3, 4:
            let row = index / 2
            let col = index % 2
            return (col == 0 ? -10 : 10, row == 0 ? -10 : 10)
        default:
            return (0, 0)
        }
    }
}

