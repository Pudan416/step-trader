import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import UIKit

fileprivate func tileAccent(for level: ShieldLevel) -> Color {
    let progress = Double(level.id - 1) / 9.0
    return Color(red: 0.88, green: 0.51, blue: 0.85).opacity(0.5 + progress * 0.5)
}

struct AppsPage: View {
    @ObservedObject var model: AppModel
    let automationApps: [AutomationApp]
    @State private var clockTick: Int = 0
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var guideApp: GuideItem?
    @State private var showDeactivatedPicker: Bool = false
    @State private var costInfoStage: ModuleLevelStage?
    @State private var statusVersion = UUID()
    @State private var openShieldBundleId: String? = nil
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    private struct ModuleLevelStage: Identifiable {
        let level: ShieldLevel
        var id: Int { level.id }
        var label: String { level.label }
        var threshold: Int { level.threshold }
        var nextThreshold: Int? { level.nextThreshold }
        var entryCost: Int { level.entryCost }
        var fiveMinutesCost: Int { level.fiveMinutesCost }
        var hourCost: Int { level.hourCost }
        var dayCost: Int { level.dayCost }
    }
    
    private var automationConfiguredSet: Set<String> {
        let defaults = UserDefaults.stepsTrader()
        let configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        let single = defaults.string(forKey: "automationBundleId")
        return Set(configured + (single.map { [$0] } ?? []))
    }
    
    private var automationLastOpened: [String: Date] {
        loadDateDict(forKey: "automationLastOpened_v1")
    }

    private var automationPendingSet: Set<String> {
        var pending = UserDefaults.stepsTrader().array(forKey: "automationPendingBundles") as? [String] ?? []
        var timestamps = loadDateDict(forKey: "automationPendingTimestamps_v1")
        let now = Date()
        pending = pending.filter { id in
            guard let ts = timestamps[id] else { return false }
            let alive = now.timeIntervalSince(ts) < 86400 // 1 day
            if !alive { timestamps.removeValue(forKey: id) }
            return alive
        }
        UserDefaults.stepsTrader().set(pending, forKey: "automationPendingBundles")
        saveDateDict(timestamps, forKey: "automationPendingTimestamps_v1")
        return Set(pending)
    }
    
    private var popularAppsList: [AutomationApp] {
        automationApps.filter { $0.category == .popular }
    }
    
    private var otherAppsList: [AutomationApp] {
        automationApps.filter { $0.category == .other }
    }

    private var activatedApps: [AutomationApp] {
        automationApps.filter {
            let status = statusFor($0, configured: automationConfiguredSet, pending: automationPendingSet)
            return status != .none
        }
        .sorted { lhs, rhs in
            let lhsRank = levelRank(for: lhs)
            let rhsRank = levelRank(for: rhs)
            if lhsRank != rhsRank { return lhsRank > rhsRank }
            let lhsSpent = spentSteps(for: lhs)
            let rhsSpent = spentSteps(for: rhs)
            if lhsSpent != rhsSpent { return lhsSpent > rhsSpent }
            return lhs.name < rhs.name
        }
    }
    
    private var deactivatedPopular: [AutomationApp] {
        popularAppsList.filter {
            statusFor($0, configured: automationConfiguredSet, pending: automationPendingSet) == .none
        }
        .sorted { $0.name < $1.name }
    }
    
    private var deactivatedOthers: [AutomationApp] {
        otherAppsList.filter {
            statusFor($0, configured: automationConfiguredSet, pending: automationPendingSet) == .none
        }
        .sorted { $0.name < $1.name }
    }
    
    private var deactivatedAll: [AutomationApp] {
        deactivatedPopular + deactivatedOthers
    }
    
    private var deactivatedPreview: [AutomationApp] {
        Array(deactivatedPopular.prefix(11))
    }
    
    private var deactivatedOverflow: [AutomationApp] {
        deactivatedOthers
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    private var moduleLevels: [ModuleLevelStage] {
        ShieldLevel.all.map { ModuleLevelStage(level: $0) }
    }
    
    var body: some View {
        NavigationView {
            let horizontalPadding: CGFloat = 16
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        deactivatedSection(horizontalPadding: horizontalPadding, availableWidth: geometry.size.width)
                        activatedSection
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                    .id(statusVersion)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .sheet(item: $guideApp, onDismiss: { guideApp = nil }) { item in
            AutomationGuideView(
                app: item,
                model: model,
                markPending: markPending(bundleId:),
                deleteModule: deactivate(bundleId:)
            )
        }
        .sheet(isPresented: $showDeactivatedPicker) {
            pickerView(apps: deactivatedOverflow, title: loc(appLanguage, "Other shields", "Остальные щиты"))
        }
        .alert(item: $costInfoStage) { stage in
            Alert(
                title: Text(levelTitle(for: stage)),
                message: Text(costInfoMessage(for: stage)),
                dismissButton: .default(Text(loc(appLanguage, "OK", "Ок")))
            )
        }
        .onReceive(tickTimer) { _ in
            clockTick &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("OpenShieldForBundle"))) { notification in
            print("🔧 Received OpenShieldForBundle notification")
            if let bundleId = notification.userInfo?["bundleId"] as? String {
                print("🔧 Looking for app with bundleId: \(bundleId)")
                // Find the app and open its guide
                if let app = automationApps.first(where: { $0.bundleId == bundleId }) {
                    print("🔧 Found app: \(app.name), opening guide")
                    let status = statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet)
                    guideApp = GuideItem(
                        name: app.name,
                        icon: app.icon,
                        imageName: app.imageName,
                        scheme: app.scheme,
                        link: app.link,
                        status: status,
                        bundleId: app.bundleId
                    )
                } else {
                    print("🔧 App not found in automationApps list")
                }
            }
        }
    }
    
    // Glass card style
    private var glassCard: some View {
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
    
    @ViewBuilder
    private func deactivatedSection(horizontalPadding: CGFloat, availableWidth: CGFloat) -> some View {
        let spacing: CGFloat = 10
        let minTile: CGFloat = 48
        let maxColumns = 6
        let cardPadding: CGFloat = 16
        let calculatedWidth = availableWidth - horizontalPadding * 2 - cardPadding * 2
        let computedColumns = Int((calculatedWidth + spacing) / (minTile + spacing))
        let columns = max(3, min(maxColumns, computedColumns))
        let tileSize = max(minTile, (calculatedWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        
        VStack(alignment: .leading, spacing: 14) {
            // Section header - edgy
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 36, height: 36)
                Image(systemName: "shield.slash")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Unprotected", "Без защиты"))
                        .font(.subheadline.weight(.semibold))
                    Text(loc(appLanguage, "These apps roam free. Fix that.", "Эти приложения гуляют свободно. Исправь."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if !deactivatedAll.isEmpty {
                    Text("\(deactivatedAll.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.gray.opacity(0.12)))
                }
            }
            
            if deactivatedAll.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text(loc(appLanguage, "All locked down 🔒", "Всё под контролем 🔒"))
                        .font(.caption)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(tileSize), spacing: spacing), count: columns),
                    alignment: .leading,
                    spacing: spacing
                ) {
                    ForEach(deactivatedPreview) { app in
                        automationButton(
                            app,
                            status: statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet),
                            width: tileSize
                        )
                    }
                    if !deactivatedOverflow.isEmpty {
                        overflowTile(size: tileSize)
                    }
                }
            }
        }
        .padding(cardPadding)
        .background(glassCard)
    }
    
    @ViewBuilder
    private var activatedSection: some View {
        let cardPadding: CGFloat = 16
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        
        VStack(alignment: .leading, spacing: 14) {
            // Section header - edgy
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                        LinearGradient(
                                colors: [pink.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 36, height: 36)
                    Image(systemName: "shield.checkered")
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [pink, .purple],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Your Arsenal", "Твой арсенал"))
                        .font(.subheadline.weight(.semibold))
                    Text(loc(appLanguage, "Shields keeping you focused", "Щиты на страже твоего фокуса"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if !activatedApps.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    Text("\(activatedApps.count)")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(pink.opacity(0.12)))
                }
            }
            
            if activatedApps.isEmpty {
                // Empty state - edgy
                VStack(spacing: 10) {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text(loc(appLanguage, "No shields active", "Щитов нет"))
                        .font(.caption.weight(.semibold))
                    Text(loc(appLanguage, "Pick an app above and take control 💪", "Выбери приложение выше и возьми контроль 💪"))
                        .font(.caption2)
                    .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundColor(.gray.opacity(0.25))
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(activatedApps) { app in
                        moduleLevelCard(for: app)
                    }
                }
            }
        }
        .padding(cardPadding)
        .background(glassCard)
    }
    
    private func overflowTile(size: CGFloat) -> some View {
        Button {
            showDeactivatedPicker = true
        } label: {
            ZStack {
            RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                
                VStack(spacing: 2) {
                    Text("+\(deactivatedOverflow.count)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func moduleLevelCard(for app: AutomationApp) -> some View {
        let status = statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet)
        let spent = spentSteps(for: app)
        let current = currentLevel(forSpent: spent)
        let progress = levelProgress(spent: spent, level: current)
        let stepsToNext = stepsToNextLevel(forSpent: spent)
        let accent = tileAccent(for: current.level)
        let isMinuteMode = model.isFamilyControlsModeEnabled(for: app.bundleId)
        let hasActiveAccess = model.remainingAccessSeconds(for: app.bundleId).map { $0 > 0 } ?? false
        
        return Button {
            openGuide(for: app, status: status)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Header row
                HStack(alignment: .center, spacing: 14) {
                    // App icon with status indicator
                    ZStack(alignment: .bottomTrailing) {
                        appIconView(app)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: accent.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        // Status dot
                        Circle()
                            .fill(hasActiveAccess ? Color.green : accent)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            )
                            .offset(x: 4, y: 4)
                    }
                    .id(clockTick)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        // App name and mode badge
                        HStack(spacing: 8) {
                        Text(app.name)
                            .font(.headline)
                                .foregroundColor(.primary)
                            
                            // Mode badge
                            HStack(spacing: 4) {
                                Image(systemName: isMinuteMode ? "clock.fill" : "door.left.hand.open")
                                    .font(.system(size: 10))
                                Text(loc(appLanguage, isMinuteMode ? "Minute" : "Open", isMinuteMode ? "Минуты" : "Открытый"))
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundColor(isMinuteMode ? .blue : .orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isMinuteMode ? Color.blue.opacity(0.12) : Color.orange.opacity(0.12))
                            )
                        }
                        
                        // Timer or level info
                        if let remaining = model.remainingAccessSeconds(for: app.bundleId), remaining > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "timer")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(loc(appLanguage, "Access: ", "Доступ: ") + formatRemaining(remaining))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("\(formatSteps(spent)) " + loc(appLanguage, "invested", "вложено"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                        }
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                // Level progress section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        // Level badge
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text(loc(appLanguage, "Level \(current.label)", "Уровень \(current.label)"))
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(accent.opacity(0.15))
                        )
                        
                        Spacer()
                        
                        // Progress info
                        if let toNext = stepsToNext {
                            Text("\(formatSteps(toNext)) " + loc(appLanguage, "to next", "до след."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.caption2)
                                Text(loc(appLanguage, "MAX", "МАКС"))
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundColor(accent)
                        }
                    }
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [accent, accent.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * CGFloat(progress)), height: 8)
                                .shadow(color: accent.opacity(0.4), radius: 3, x: 0, y: 1)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            switch status {
            case .configured, .pending:
                Button(role: .destructive) {
                    deactivate(app)
                } label: {
                    Label(loc(appLanguage, "Deactivate shield", "Отключить щит"), systemImage: "trash")
                }
            case .none:
                Button {
                    activate(app)
                } label: {
                    Label(loc(appLanguage, "Activate", "Активировать"), systemImage: "checkmark.circle")
                }
            }
        }
    }
    
    private func levelProgress(spent: Int, level: ModuleLevelStage) -> Double {
        guard let nextThreshold = level.nextThreshold else { return 1.0 }
        let levelStart = level.threshold
        let levelSpan = nextThreshold - levelStart
        guard levelSpan > 0 else { return 1.0 }
        let localSpent = spent - levelStart
        return min(max(Double(localSpent) / Double(levelSpan), 0), 1)
    }
    
    private func moduleLevelRow(for stage: ModuleLevelStage, spent: Int, current: ModuleLevelStage) -> some View {
        let stageLength = stage.nextThreshold.map { $0 - stage.threshold }
        let isCurrent = stage.id == current.id
        let isPast = stage.threshold < current.threshold
        let active = isPast || isCurrent

        let progress: Double = {
            if isPast { return 1 }
            if isCurrent, let len = stageLength {
                let localSpent = max(0, spent - stage.threshold)
                return min(max(Double(localSpent) / Double(max(1, len)), 0), 1)
            }
            return 0
        }()

        let remaining: Int? = {
            if isPast { return 0 }
            if isCurrent {
                if let next = stage.nextThreshold {
                    return max(0, next - spent)
                } else {
                    return nil
                }
            }
            if let len = stageLength {
                return len
            }
            return nil
        }()
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loc(appLanguage, "Level \(stage.label)", "Уровень \(stage.label)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let remaining {
                    Text(remaining == 0 ? loc(appLanguage, "Unlocked", "Открыт") : "\(formatSteps(remaining)) " + loc(appLanguage, "steps", "шагов"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(loc(appLanguage, "Max", "Макс"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    showCostInfo(for: stage)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            ProgressView(value: progress)
                .tint(tileAccent(for: stage.level))
                .progressViewStyle(.linear)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tileAccent(for: stage.level).opacity(active ? 0.16 : 0.08))
        )
    }
    
    private func moduleCardSubtitle(for level: ModuleLevelStage) -> String {
        return loc(appLanguage, "Level \(level.label)", "Уровень \(level.label)")
    }
    
    private func currentLevel(forSpent spent: Int) -> ModuleLevelStage {
        moduleLevels.last { spent >= $0.threshold } ?? moduleLevels.first!
    }
    
    private func stepsToNextLevel(forSpent spent: Int) -> Int? {
        let level = currentLevel(forSpent: spent)
        guard let next = level.nextThreshold else { return nil }
        return max(0, next - spent)
    }
    
    private func levelRank(for app: AutomationApp) -> Int {
        let spent = spentSteps(for: app)
        let level = currentLevel(forSpent: spent)
        if let idx = moduleLevels.firstIndex(where: { $0.id == level.id }) {
            return idx
        }
        return 0
    }
    
    private func spentSteps(for app: AutomationApp) -> Int {
        model.totalStepsSpent(for: app.bundleId)
    }
    
    private func formatSteps(_ value: Int) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        
        func trimTrailingZero(_ s: String) -> String {
            s.hasSuffix(".0") ? String(s.dropLast(2)) : s
        }
        
        if absValue < 1000 { return "\(value)" }
        
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "K"
        }
        
        if absValue < 1_000_000 {
            let v = Int((Double(absValue) / 1000.0).rounded())
            return sign + "\(v)K"
        }
        
        if absValue < 10_000_000 {
            let v = (Double(absValue) / 1_000_000.0 * 10).rounded() / 10
            return sign + trimTrailingZero(String(format: "%.1f", v)) + "M"
        }
        
        let v = Int((Double(absValue) / 1_000_000.0).rounded())
        return sign + "\(v)M"
    }
    
    private func openGuide(for app: AutomationApp, status: AutomationStatus) {
        guard guideApp == nil else { return }
        UserDefaults.stepsTrader().set(app.scheme, forKey: "selectedAppScheme")
        let item = GuideItem(
            name: app.name,
            icon: app.icon,
            imageName: app.imageName,
            scheme: app.scheme,
            link: app.link,
            status: status,
            bundleId: app.bundleId
        )
        DispatchQueue.main.async {
            guideApp = item
        }
    }
    
    private func showCostInfo(for stage: ModuleLevelStage) {
        costInfoStage = stage
    }
    
    private func levelTitle(for stage: ModuleLevelStage) -> String {
        loc(appLanguage, "Level \(stage.label)", "Уровень \(stage.label)")
    }
    
    private func costInfoMessage(for stage: ModuleLevelStage) -> String {
        let entryLine = loc(appLanguage, "1 min: 1 energy", "1 мин: 1 энергия")
        let fiveLine = loc(appLanguage, "5 min: 2 energy", "5 мин: 2 энергии")
        let halfHourLine = loc(appLanguage, "30 min: 10 energy", "30 мин: 10 энергии")
        let hourLine = loc(appLanguage, "1 hour: 20 energy", "1 час: 20 энергии")
        return [entryLine, fiveLine, halfHourLine, hourLine].joined(separator: "\n")
    }

    private func statusFor(_ app: AutomationApp,
                           configured: Set<String>,
                           pending: Set<String>) -> AutomationStatus {
        if automationLastOpened[app.bundleId] != nil || configured.contains(app.bundleId) {
            return .configured
        }
        if pending.contains(app.bundleId) { return .pending }
        return .none
    }

    @ViewBuilder
    private func statusIcon(for status: AutomationStatus) -> some View {
        switch status {
        case .configured:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .pending:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.yellow)
        case .none:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func appIconView(_ app: AutomationApp) -> some View {
        if let imageName = app.imageName, let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Text(app.icon)
                .font(.system(size: 44))
        }
    }
    
    private func automationButton(_ app: AutomationApp, status: AutomationStatus, width: CGFloat, tariff: Tariff? = nil) -> some View {
        Button {
            openGuide(for: app, status: status)
        } label: {
                            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: width, height: width)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                // App icon
                                appIconView(app)
                    .frame(width: width * 0.58, height: width * 0.58)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Timer badge (if active)
                                if let remaining = model.remainingAccessSeconds(for: app.bundleId), remaining > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 2) {
                                        Image(systemName: "timer")
                                        Text(formatRemaining(remaining))
                                    }
                            .font(.system(size: 8, weight: .semibold))
                                    .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green)
                                    .clipShape(Capsule())
                            .padding(3)
                        }
                        Spacer()
                    }
                }
                
                // Status indicator
                if status != .none {
                    VStack {
                        HStack {
                            Spacer()
                    statusIcon(for: status)
                                .font(.caption2)
                                .padding(4)
                }
                        Spacer()
            }
        }
            }
            .frame(width: width, height: width)
            .id(clockTick)
        }
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            switch status {
            case .configured, .pending:
                Button(role: .destructive) {
                    deactivate(app)
                } label: {
                    Label(loc(appLanguage, "Deactivate shield", "Отключить щит"), systemImage: "trash")
                }
            case .none:
                Button {
                    activate(app)
                } label: {
                    Label(loc(appLanguage, "Activate", "Активировать"), systemImage: "checkmark.circle")
                }
            }
        }
        .opacity(status == .none ? 0.7 : 1.0)
    }
    
    private func tileColor(for tariff: Tariff?, status: AutomationStatus) -> Color {
        if status == .none { return Color.gray.opacity(0.08) }
        let base: Color
        switch tariff ?? .easy {
        case .free: base = Color.cyan.opacity(status == .none ? 0.18 : 0.4)
        case .easy: base = Color.green.opacity(status == .none ? 0.18 : 0.35)
        case .medium: base = Color.orange.opacity(status == .none ? 0.2 : 0.4)
        case .hard: base = Color.red.opacity(status == .none ? 0.2 : 0.35)
        }
        return base
    }
    
private func tileAccent(for level: ShieldLevel) -> Color {
    let progress = Double(level.id - 1) / 9.0
    return Color(red: 0.88, green: 0.51, blue: 0.85).opacity(0.5 + progress * 0.5)
}

fileprivate struct TimeAccessPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: FamilyActivitySelection
    let appName: String
    let appLanguage: String

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(loc(appLanguage, "Choose app for \(appName)", "Выберите приложение: \(appName)"))
                    .font(.headline)
                    .padding(.horizontal)

                #if canImport(FamilyControls)
                FamilyActivityPicker(selection: $selection)
                    .ignoresSafeArea(edges: .bottom)
                #else
                Text("Family Controls not available on this build.")
                    .padding()
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done", "Готово")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
    
    private func markPending(bundleId: String) {
        var pending = UserDefaults.stepsTrader().array(forKey: "automationPendingBundles") as? [String] ?? []
        if !pending.contains(bundleId) {
            pending.append(bundleId)
            UserDefaults.stepsTrader().set(pending, forKey: "automationPendingBundles")
        }
        var timestamps = loadDateDict(forKey: "automationPendingTimestamps_v1")
        timestamps[bundleId] = Date()
        saveDateDict(timestamps, forKey: "automationPendingTimestamps_v1")
    }
    
    private func loadDateDict(forKey key: String) -> [String: Date] {
        let defaults = UserDefaults.stepsTrader()
        guard let data = defaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return [:] }
        return dict
    }
    
    private func saveDateDict(_ dict: [String: Date], forKey key: String) {
        let defaults = UserDefaults.stepsTrader()
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: key)
        }
    }
    
    private func deactivate(_ app: AutomationApp) {
        deactivate(bundleId: app.bundleId)
    }
    
    private func deactivate(bundleId: String) {
        let defaults = UserDefaults.stepsTrader()
        var configured = defaults.array(forKey: "automationConfiguredBundles") as? [String] ?? []
        configured.removeAll { $0 == bundleId }
        defaults.set(configured, forKey: "automationConfiguredBundles")
        
        var pending = defaults.array(forKey: "automationPendingBundles") as? [String] ?? []
        pending.removeAll { $0 == bundleId }
        defaults.set(pending, forKey: "automationPendingBundles")
        
        var pendingTs = loadDateDict(forKey: "automationPendingTimestamps_v1")
        pendingTs.removeValue(forKey: bundleId)
        saveDateDict(pendingTs, forKey: "automationPendingTimestamps_v1")

        var lastOpened = loadDateDict(forKey: "automationLastOpened_v1")
        lastOpened.removeValue(forKey: bundleId)
        saveDateDict(lastOpened, forKey: "automationLastOpened_v1")
        statusVersion = UUID()

        // Remove local shield config + delete server-side shield row
        model.deactivateShield(bundleId: bundleId)
    }
    
    private func activate(_ app: AutomationApp) {
        markPending(bundleId: app.bundleId)
        let level = ShieldLevel.all.first!
        model.updateUnlockSettings(for: app.bundleId, entryCost: level.entryCost, dayPassCost: level.dayCost)
        statusVersion = UUID()
    }
    
    // Sheet with full list
    private func pickerView(apps: [AutomationApp], title: String) -> some View {
        NavigationView {
            List {
                ForEach(apps) { app in
                    Button {
                        let status = statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet)
                        openGuide(for: app, status: status)
                        showDeactivatedPicker = false
                    } label: {
                        HStack {
                            appIconView(app)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(app.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarItems(trailing: Button(loc(appLanguage, "Close", "Закрыть")) {
                showDeactivatedPicker = false
            })
        }
    }
    
}

struct AutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let app: GuideItem
    @ObservedObject var model: AppModel
    let markPending: (String) -> Void
    let deleteModule: (String) -> Void
    @State private var showDeactivateAlert = false
    @State private var showTimeAccessPicker = false
    @State private var timeAccessSelection = FamilyActivitySelection()
    @State private var showLevels = false
    @State private var showEntrySettings = false
    @State private var showConnectionRequired = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    
    private var currentLevel: ShieldLevel { model.currentShieldLevel(for: app.bundleId) }
    private var spent: Int { model.totalStepsSpent(for: app.bundleId) }
    private var stepsToNext: Int? { model.stepsToNextShieldLevel(for: app.bundleId) }
    private var accent: Color { tileAccent(for: currentLevel) }
    private var timeAccessEnabled: Bool { model.isTimeAccessEnabled(for: app.bundleId) }
    private var minuteModeEnabled: Bool { model.isFamilyControlsModeEnabled(for: app.bundleId) }

    var body: some View {
        NavigationView {
                ScrollView {
                VStack(spacing: 16) {
                    // Compact header
                    compactHeader

                if app.status == .configured || app.status == .pending {
                        // Connection status (moved to top)
                        connectionCard
                        
                        // Level card with expandable levels
                        levelCard
                        
                        // Mode selector
                        modeCard
                        
                        // Entry settings (expandable, only for entry mode)
                        if !minuteModeEnabled {
                            entrySettingsCard
                        }
                        
                        // Setup instructions for pending
                        if app.status == .pending {
                            setupCard
                        }
                } else {
                        // Setup instructions for new shields
                        setupCard
                    }
                    
                    // Shortcut button
                    shortcutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                if app.status != .none {
                    deactivateButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                timeAccessSelection = model.timeAccessSelection(for: app.bundleId)
            }
            .sheet(isPresented: $showTimeAccessPicker, onDismiss: {
                model.saveTimeAccessSelection(timeAccessSelection, for: app.bundleId)
                if model.isFamilyControlsModeEnabled(for: app.bundleId) {
                    model.applyFamilyControlsSelection(for: app.bundleId)
                } else {
                    model.rebuildFamilyControlsShield()
                }
            }) {
                AppsPage.TimeAccessPickerSheet(
                    selection: $timeAccessSelection,
                    appName: app.name,
                    appLanguage: appLanguage
                )
            }
            .alert(loc(appLanguage, "Deactivate shield", "Отключить щит"), isPresented: $showDeactivateAlert) {
                Button(loc(appLanguage, "Open Shortcuts", "Открыть Команды")) {
                    if let url = URL(string: "shortcuts://automation") ?? URL(string: "shortcuts://") {
                        openURL(url)
                    }
                    deleteModule(app.bundleId)
                    dismiss()
                }
                Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) { showDeactivateAlert = false }
            } message: {
                Text(loc(appLanguage, "Remove the automation from Shortcuts app to fully deactivate.", "Удалите автоматизацию из приложения Команды."))
            }
            .alert(loc(appLanguage, "Connection required", "Требуется подключение"), isPresented: $showConnectionRequired) {
                Button(loc(appLanguage, "Connect", "Подключить")) {
                    Task {
                        try? await model.family.requestAuthorization()
                        showTimeAccessPicker = true
                    }
                }
                Button(loc(appLanguage, "Cancel", "Отмена"), role: .cancel) { }
            } message: {
                Text(loc(appLanguage, "To use minute mode, connect the app via Family Controls. This allows tracking real usage time.", "Для режима минут подключите приложение через Family Controls. Это позволит отслеживать реальное время использования."))
            }
        }
    }
    
    // MARK: - Compact Header
    private var compactHeader: some View {
        HStack(spacing: 14) {
            // App icon
                guideIconView()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                    .font(.headline)
                
                // Status badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(app.status == .configured ? Color.green : (app.status == .pending ? Color.orange : Color.gray))
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            
                Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var statusText: String {
        switch app.status {
        case .configured: return loc(appLanguage, "Active", "Активен")
        case .pending: return loc(appLanguage, "Pending", "Ожидает")
        case .none: return loc(appLanguage, "Not connected", "Не подключен")
        }
    }
    
    @ViewBuilder
    private func guideIconView() -> some View {
        if let imageName = app.imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Text(app.icon)
                .font(.system(size: 28))
        }
    }
    
    // MARK: - Connection Card (moved to top)
    private var connectionCard: some View {
        Button {
            Task {
                try? await model.family.requestAuthorization()
                showTimeAccessPicker = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(timeAccessEnabled ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    #if canImport(FamilyControls)
                    if let token = timeAccessSelection.applicationTokens.first {
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                } else {
                        Image(systemName: "plus")
                            .font(.body.bold())
                            .foregroundColor(.orange)
                    }
                    #else
                    Image(systemName: timeAccessEnabled ? "checkmark" : "plus")
                        .font(.body.bold())
                        .foregroundColor(timeAccessEnabled ? .green : .orange)
                    #endif
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "App Connection", "Подключение"))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(timeAccessEnabled ? loc(appLanguage, "Connected", "Подключено") : loc(appLanguage, "Tap to connect", "Нажмите для подключения"))
                        .font(.caption)
                        .foregroundColor(timeAccessEnabled ? .green : .secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Level Card with Expandable Levels
    private var levelCard: some View {
        VStack(spacing: 0) {
            // Main level row (tappable to expand)
                Button {
                withAnimation(.spring(response: 0.3)) {
                    showLevels.toggle()
                    }
                } label: {
                HStack(spacing: 14) {
                    // Level badge
                    Text(currentLevel.label)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(accent)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc(appLanguage, "Level", "Уровень") + " \(currentLevel.label)")
                            .font(.subheadline.weight(.medium))
                        
                        // Mini progress
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color(.systemGray5))
                                Capsule()
                                    .fill(accent)
                                    .frame(width: max(4, geo.size.width * levelProgress))
                            }
                        }
                        .frame(height: 4)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(currentLevel.entryCost)")
                            .font(.subheadline.bold())
                        Text(minuteModeEnabled ? loc(appLanguage, "/min", "/мин") : loc(appLanguage, "/entry", "/вход"))
                            .font(.caption2)
                .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: showLevels ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
                .padding(14)
        }
        .buttonStyle(.plain)
            
            // Expandable levels list
            if showLevels {
                Divider()
                    .padding(.horizontal, 14)
                
                VStack(spacing: 0) {
                    ForEach(ShieldLevel.all) { level in
                        levelRow(level: level)
                        if level.id < ShieldLevel.all.count {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func levelRow(level: ShieldLevel) -> some View {
        let isCurrent = level.id == currentLevel.id
        let isAchieved = level.threshold < currentLevel.threshold
        let levelAccent = tileAccent(for: level)
        
        return HStack(spacing: 12) {
            // Status icon
            ZStack {
            if isAchieved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isCurrent {
                    Image(systemName: "circle.fill")
                    .foregroundColor(levelAccent)
            } else {
                Image(systemName: "circle")
                        .foregroundColor(.gray.opacity(0.3))
            }
            }
            .font(.body)
            .frame(width: 24)
            
            Text(level.label)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? levelAccent : .primary)
            
                            Spacer()
            
            // Threshold
            if !isAchieved && !isCurrent {
                Text("\(formatSteps(level.threshold))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Cost
            Text("\(level.entryCost)")
                .font(.caption.weight(.medium))
                .foregroundColor(isCurrent ? levelAccent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isCurrent ? levelAccent.opacity(0.15) : Color.gray.opacity(0.1))
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isCurrent ? levelAccent.opacity(0.05) : Color.clear)
    }
    
    private var levelProgress: Double {
        guard let nextThreshold = currentLevel.nextThreshold else { return 1.0 }
        let levelStart = currentLevel.threshold
        let levelSpan = nextThreshold - levelStart
        guard levelSpan > 0 else { return 1.0 }
        let localSpent = spent - levelStart
        return min(max(Double(localSpent) / Double(levelSpan), 0), 1)
    }
    
    // MARK: - Mode Card
    private var modeCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Entry mode
                modeButton(
                    icon: "door.left.hand.open",
                    title: loc(appLanguage, "Entry", "Вход"),
                    subtitle: loc(appLanguage, "Pay once per session", "Плата за сессию"),
                    isSelected: !minuteModeEnabled,
                    isEnabled: true
                ) {
                    setMinuteModeEnabled(false)
                }
                
                // Minute mode
                modeButton(
                    icon: "clock.fill",
                    title: loc(appLanguage, "Minute", "Минуты"),
                    subtitle: loc(appLanguage, "Pay per minute used", "Плата за минуты"),
                    isSelected: minuteModeEnabled,
                    isEnabled: timeAccessEnabled
                ) {
                    if timeAccessEnabled {
                        setMinuteModeEnabled(true)
                    } else {
                        showConnectionRequired = true
                    }
                }
            }
            
            // Mode description
                HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(minuteModeEnabled 
                    ? loc(appLanguage, "Energy is deducted for each minute you spend in the app", "Энергия списывается за каждую минуту в приложении")
                    : loc(appLanguage, "Choose a time window (5min, 1h, day) and pay once for unlimited access", "Выберите окно времени (5мин, 1ч, день) и платите один раз"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func modeButton(icon: String, title: String, subtitle: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.body)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isSelected ? accent.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? accent.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
                    )
            )
            .foregroundColor(isSelected ? accent : (isEnabled ? .primary : .secondary))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func windowCost(for level: ShieldLevel, window: AccessWindow) -> Int {
        switch window {
        case .single: return 1
        case .minutes5: return 2
        case .minutes15: return 5
        case .minutes30: return 10
        case .hour1: return 20
        case .hour2: return 40
        case .day1: return 20
        }
    }

    private func setMinuteModeEnabled(_ enabled: Bool) {
        model.setFamilyControlsModeEnabled(enabled, for: app.bundleId)
        model.setMinuteTariffEnabled(enabled, for: app.bundleId)
        if enabled && timeAccessEnabled {
            model.applyFamilyControlsSelection(for: app.bundleId)
                        } else {
            model.rebuildFamilyControlsShield()
        }
    }
    
    // MARK: - Entry Settings Card (Expandable)
    private var entrySettingsCard: some View {
        VStack(spacing: 0) {
            // Header (tappable)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showEntrySettings.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(loc(appLanguage, "Entry settings", "Настройки входа"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: showEntrySettings ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expandable content
            if showEntrySettings {
                Divider()
                    .padding(.horizontal, 14)
                
                VStack(spacing: 0) {
                    windowRow(title: loc(appLanguage, "1 hour", "1 час"), window: .hour1, cost: windowCost(for: currentLevel, window: .hour1), isLast: false)
                    windowRow(title: loc(appLanguage, "30 min", "30 мин"), window: .minutes30, cost: windowCost(for: currentLevel, window: .minutes30), isLast: false)
                    windowRow(title: loc(appLanguage, "5 min", "5 мин"), window: .minutes5, cost: windowCost(for: currentLevel, window: .minutes5), isLast: false)
                    windowRow(title: loc(appLanguage, "1 min", "1 мин"), window: .single, cost: windowCost(for: currentLevel, window: .single), isLast: true)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func windowRow(title: String, window: AccessWindow, cost: Int, isLast: Bool) -> some View {
        let isEnabled = model.allowedAccessWindows(for: app.bundleId).contains(window)
        
        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    
                    Spacer()
                    
                Text("\(cost)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { model.updateAccessWindow(window, enabled: $0, for: app.bundleId) }
                ))
                .labelsHidden()
                .tint(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            if !isLast {
                Divider()
                    .padding(.leading, 14)
            }
        }
    }
    
    // MARK: - Setup Card
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.body)
                    .foregroundColor(.blue)
                Text(app.status == .pending ? loc(appLanguage, "Finish setup", "Завершите настройку") : loc(appLanguage, "How to set up", "Как настроить"))
                    .font(.subheadline.weight(.medium))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                if app.status == .pending {
                    setupStep(num: 1, text: loc(appLanguage, "Shortcuts → Automation → +", "Команды → Автоматизация → +"))
                    setupStep(num: 2, text: loc(appLanguage, "App → \(app.name) → Is Opened", "Приложение → \(app.name) → Открыто"))
                    setupStep(num: 3, text: loc(appLanguage, "Run Immediately → select shortcut", "Выполнять сразу → выберите команду"))
                } else {
                    setupStep(num: 1, text: loc(appLanguage, "Tap \"Get shield\" below", "Нажмите «Взять щит»"))
                    setupStep(num: 2, text: loc(appLanguage, "Add shortcut to library", "Добавьте в библиотеку"))
                    setupStep(num: 3, text: loc(appLanguage, "Create automation", "Создайте автоматизацию"))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func setupStep(num: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(num)")
                .font(.caption2.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Shortcut Button
    @ViewBuilder
    private var shortcutButton: some View {
        if let link = app.link, let url = URL(string: link) {
            Button {
                markPending(app.bundleId)
                openURL(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: app.status == .configured ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                        .font(.body)
                    Text(app.status == .configured ? loc(appLanguage, "Update", "Обновить") : loc(appLanguage, "Get shield", "Взять щит"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .padding(14)
        .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Deactivate Button
    private var deactivateButton: some View {
        Button {
            if app.status == .configured {
                showDeactivateAlert = true
            } else {
                deleteModule(app.bundleId)
                dismiss()
            }
        } label: {
            Text(loc(appLanguage, "Deactivate", "Отключить"))
                .font(.caption.weight(.medium))
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 70)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Helpers
    private func formatSteps(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue < 1000 { return "\(value)" }
        if absValue < 10_000 {
            let v = (Double(absValue) / 1000.0 * 10).rounded() / 10
            return String(format: "%.1fK", v).replacingOccurrences(of: ".0K", with: "K")
        }
        if absValue < 1_000_000 {
            return "\(Int((Double(absValue) / 1000.0).rounded()))K"
        }
        return "\(Int((Double(absValue) / 1_000_000.0).rounded()))M"
    }
}

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var isExpanded: Bool = false
    @State private var isLevelsExpanded: Bool = false
    @State private var isEntryExpanded: Bool = false
    @State private var showGallery: Bool = false
    @State private var galleryImages: [String] = []
    @State private var galleryIndex: Int = 0
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header section
                        headerSection
                        
                        // Setup guide card
                        setupGuideCard
                        
                        // Levels explanation card
                        expandableCard(
                            title: appLanguage == "ru" ? "Как прокачивать уровни" : "How levels work",
                            icon: "chart.line.uptrend.xyaxis",
                            iconColor: .green,
                            expanded: $isLevelsExpanded,
                            content: levelsContent
                        )
                        
                        // Entry options card
                        expandableCard(
                            title: appLanguage == "ru" ? "Варианты входа" : "Entry options",
                            icon: "door.left.hand.open",
                            iconColor: .orange,
                            expanded: $isEntryExpanded,
                            content: entryOptionsContent
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
                .background(Color(.systemGroupedBackground))
                
                // Gallery overlay
                if showGallery {
                    galleryOverlay
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .onDisappear {
            showGallery = false
            galleryImages = []
            isExpanded = false
            isLevelsExpanded = false
            isEntryExpanded = false
        }
    }
    
    // Glass card style for ManualsPage
    private var manualsGlassCard: some View {
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
    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc(appLanguage, "Field Manual", "Боевой мануал"))
                    .font(.headline)
                Text(loc(appLanguage, "Level up your shield game 🎮", "Прокачай свой контроль 🎮"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Setup Guide Card
    private var setupGuideCard: some View {
        let pink = Color(red: 224/255, green: 130/255, blue: 217/255)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Card header
                            Button {
                withAnimation(.spring(response: 0.3)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(pink.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.subheadline)
                            .foregroundColor(pink)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appLanguage == "ru" ? "Как врубить щит" : "How to arm your shield")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Text(appLanguage == "ru" ? "4 шага до контроля 💪" : "4 steps to take control 💪")
                            .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .padding(14)
                            }
                            
                            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Image carousel
                                    let manualImages = (1...11).map { "manual_1_\($0)" }
                                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                                            ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                                                Image(name)
                                                    .resizable()
                                                    .scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                                                    .onTapGesture {
                                                        openGallery(images: manualImages, startAt: index)
                                                    }
                                            }
                                        }
                        .padding(.horizontal, 14)
                    }
                    
                    // Steps - edgy
                    VStack(alignment: .leading, spacing: 8) {
                        stepRow(number: 1, text: appLanguage == "ru" ? "Открой ссылку → добавь в Команды" : "Open link → Add to Shortcuts")
                        stepRow(number: 2, text: appLanguage == "ru" ? "Команды → Автоматизация → + → Приложение → включи 'Открыто' + 'Выполнять сразу'" : "Shortcuts → Automation → + → App → enable 'Is Opened' + 'Run Immediately'")
                        stepRow(number: 3, text: appLanguage == "ru" ? "Выбери [app] CTRL щит → Сохрани" : "Pick [app] CTRL shield → Save")
                        stepRow(number: 4, text: appLanguage == "ru" ? "Открой приложение один раз — щит активирован 🔥" : "Open the app once — shield is live 🔥")
                    }
                    .padding(.horizontal, 14)
                    
                    // Tip - edgy
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                                .font(.subheadline)
                        
                        Text(appLanguage == "ru" ? "Не работает? Проверь уведомления и доступ к Командам" : "Not working? Check notifications & Shortcuts access")
                            .font(.caption)
                                        .foregroundColor(.secondary)
                        }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
        .background(manualsGlassCard)
    }
    
    @ViewBuilder
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Gallery Overlay
    private var galleryOverlay: some View {
                    ZStack {
            Color.black.opacity(0.9)
                            .ignoresSafeArea()
                            .onTapGesture { closeGallery() }
                        
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        closeGallery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                }
                
                // Image viewer
                        TabView(selection: $galleryIndex) {
                            ForEach(Array(galleryImages.enumerated()), id: \.offset) { index, name in
                                if let uiImage = UIImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .tag(index)
                                .padding(.horizontal, 20)
                                } else {
                                    Color.clear.tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                
                // Image counter
                Text("\(galleryIndex + 1) / \(galleryImages.count)")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 20)
            }
        }
        .zIndex(2)
        .transition(.opacity)
                        .gesture(
            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                    if abs(value.translation.height) > 80 {
                                        closeGallery()
                                    }
                                }
                        )
    }

    @ViewBuilder
    private func levelsContent() -> some View {
        let items: [(icon: String, color: Color, ru: String, en: String)] = [
            ("flame.fill", .orange, "Чем больше тратишь — тем сильнее щит. Топливо = опыт 🔥", "More fuel burned = stronger shield. Fuel = XP 🔥"),
            ("star.fill", .yellow, "10 уровней: II на 10K, до X на 500K шагов", "10 levels: II at 10K, up to X at 500K steps"),
            ("bolt.fill", .green, "Выше уровень → дешевле вход: I=100, X=10 шагов", "Higher level → cheaper entry: I=100, X=10 steps"),
            ("chart.bar.fill", .blue, "Смотри прогресс на карточке щита", "Check progress on the shield card")
        ]
        
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.ru) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.icon)
                        .foregroundColor(item.color)
                        .font(.caption)
                        .frame(width: 20)
                    Text(appLanguage == "ru" ? item.ru : item.en)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private func entryOptionsContent() -> some View {
        let manualImages = ["manual_2_1", "manual_2_2", "manual_2_3"]
        let items: [(icon: String, color: Color, ru: String, en: String)] = [
            ("clock.fill", .purple, "Разным приложениям — разное время ⏰", "Different apps need different fuel ⏰"),
            ("door.left.hand.open", .orange, "Где-то хватит входа, где-то надо зависнуть", "Sometimes quick peek, sometimes deep dive"),
            ("square.grid.2x2.fill", .blue, "Выбирай: разовый, 5 мин, час или день", "Pick: single, 5 min, hour, or day pass"),
            ("bolt.fill", .green, "Цена зависит от уровня (10–100 за вход)", "Cost scales with level (10–100 per entry)"),
            ("slider.horizontal.3", .gray, "Лишнее отключи в настройках щита", "Turn off unused modes in shield settings")
        ]

        VStack(alignment: .leading, spacing: 14) {
            // Image carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            .onTapGesture {
                                openGallery(images: manualImages, startAt: index)
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.ru) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .font(.caption)
                            .frame(width: 20)
                        Text(appLanguage == "ru" ? item.ru : item.en)
                            .font(.caption)
                        .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        }
        .padding(14)
    }

    private func openGallery(images: [String], startAt index: Int) {
        galleryImages = images
        galleryIndex = index
        withAnimation(.spring(response: 0.3)) {
            showGallery = true
        }
    }
    
    private func closeGallery() {
        withAnimation(.spring(response: 0.3)) {
            showGallery = false
        }
    }

    private func expandableCard(title: String, icon: String, iconColor: Color, expanded: Binding<Bool>, content: @escaping () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 38, height: 38)
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundColor(iconColor)
                    }
                    
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .padding(14)
            }

            if expanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(manualsGlassCard)
    }
}
