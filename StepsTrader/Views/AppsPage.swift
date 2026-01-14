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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    deactivatedSection(horizontalPadding: horizontalPadding)
                    activatedSection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 100)
                .id(statusVersion)
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
    }
    
    @ViewBuilder
    private func deactivatedSection(horizontalPadding: CGFloat) -> some View {
        let spacing: CGFloat = 10
        let minTile: CGFloat = 48
        let maxColumns = 6
        let cardPadding: CGFloat = 16
        let availableWidth = UIScreen.main.bounds.width - horizontalPadding * 2 - cardPadding * 2
        let computedColumns = Int((availableWidth + spacing) / (minTile + spacing))
        let columns = max(3, min(maxColumns, computedColumns))
        let tileSize = max(minTile, (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "shield.slash")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.gray, .gray.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Available Shields", "Доступные щиты"))
                .font(.headline)
                    Text(loc(appLanguage, "Tap to activate", "Нажмите для активации"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Count badge
                if !deactivatedAll.isEmpty {
                    Text("\(deactivatedAll.count)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.gray.opacity(0.15)))
                }
            }
            
            if deactivatedAll.isEmpty {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                Text(loc(appLanguage, "All shields are connected", "Все щиты подключены"))
                        .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green.opacity(0.1))
                )
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
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    @ViewBuilder
    private var activatedSection: some View {
        let cardPadding: CGFloat = 16
        
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc(appLanguage, "Active Shields", "Активные щиты"))
                .font(.headline)
                    Text(loc(appLanguage, "Your protected apps", "Ваши защищённые приложения"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Count badge
                if !activatedApps.isEmpty {
                    Text("\(activatedApps.count)")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                }
            }
            
            if activatedApps.isEmpty {
                // Empty state card
                VStack(spacing: 12) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.gray.opacity(0.4), .gray.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    Text(loc(appLanguage, "No shields yet", "Пока нет щитов"))
                        .font(.subheadline.weight(.medium))
                    Text(loc(appLanguage, "Activate a shield above to start protecting yourself from distractions", "Активируйте щит выше, чтобы защититься от отвлечений"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.tertiarySystemBackground))
                        .stroke(Color.gray.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(activatedApps) { app in
                        moduleLevelCard(for: app)
                    }
                }
            }
        }
        .padding(cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
        let entryLine = loc(appLanguage, "Entry: \(formatSteps(stage.entryCost)) steps", "Вход: \(formatSteps(stage.entryCost)) шагов")
        let fiveLine = loc(appLanguage, "5 minutes: \(formatSteps(stage.fiveMinutesCost)) steps", "5 минут: \(formatSteps(stage.fiveMinutesCost)) шагов")
        let hourLine = loc(appLanguage, "1 hour: \(formatSteps(stage.hourCost)) steps", "1 час: \(formatSteps(stage.hourCost)) шагов")
        let dayLine = loc(appLanguage, "Day: \(formatSteps(stage.dayCost)) steps", "День: \(formatSteps(stage.dayCost)) шагов")
        return [entryLine, fiveLine, hourLine, dayLine].joined(separator: "\n")
    }

    private func windowCost(for level: ShieldLevel, window: AccessWindow) -> Int {
        switch window {
        case .single: return level.entryCost
        case .minutes5: return level.fiveMinutesCost
        case .hour1: return level.hourCost
        case .day1: return level.dayCost
        }
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
    @State private var showLevelsTable = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Scrollable content area
                ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if app.status == .configured {
                    unlockSettings
                }

                content

                if let link = app.link, let url = URL(string: link) {
                    Button {
                        markPending(app.bundleId)
                        openURL(url)
                    } label: {
                        HStack {
                            Image(systemName: "link")
                            Text(app.status == .configured ? "Update the shield" : "Get the shield")
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.1)))
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text("Shortcut link will be added soon.")
                            .fontWeight(.semibold)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
                        }
                    }
                    .padding()
                }

                // Fixed bottom button
                if app.status != .none {
                    Button {
                        if app.status == .configured {
                            showDeactivateAlert = true
                        } else {
                            deleteModule(app.bundleId)
                            dismiss()
                        }
                    } label: {
                        Text("Deactivate shield")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.85))
                            )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
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
            .alert("Deactivate shield", isPresented: $showDeactivateAlert) {
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://automation") ?? URL(string: "shortcuts://") {
                        openURL(url)
                    }
                    deleteModule(app.bundleId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { showDeactivateAlert = false }
            } message: {
                Text("To fully deactivate this shield, remove the automation from the Shortcuts app.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                guideIconView()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    switch app.status {
                    case .configured:
                        Text("Shield for \(app.name) is working")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    case .pending:
                        Text("Shield is not connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    case .none:
                        Text("The shield for \(app.name) is not taken")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if app.status == .configured || app.status == .pending {
                    Image(systemName: "checkmark.seal.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundColor(app.status == .configured ? .green : .yellow)
                        .padding(.top, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    private func guideIconView() -> some View {
        if let imageName = app.imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Text(app.icon)
                .font(.system(size: 36))
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch app.status {
        case .configured:
            EmptyView()
        case .pending:
            VStack(alignment: .leading, spacing: 10) {
                Text("Finish setup:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("1) Open Shortcuts → Automation → + → \"App\".")
                Text("2) Choose \(app.name), set \"Is Opened\" + \"Run Immediately\".")
                Text("3) Select the imported shortcut for \(app.name).")
                Text("4) Launch \(app.name) once to activate the automation.")
            }
            .font(.callout)
        case .none:
            VStack(alignment: .leading, spacing: 10) {
                Text("How to set up:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if app.link != nil {
                    Text("1) Tap \"Open shortcut\" below and add it.")
                    Text("2) Open Shortcuts → Automation → + → \"App\".")
                    Text("3) Choose \(app.name), set \"Is Opened\" + \"Run Immediately\".")
                    Text("4) Select the imported shortcut for \(app.name).")
                    Text("5) Launch \(app.name) once to activate the automation.")
                } else {
                    Text("1) Open Shortcuts → Automation → + → \"App\".")
                    Text("2) Choose \(app.name), set \"Is Opened\" + \"Run Immediately\".")
                    Text("3) Pick the universal DOOM CTRL shortcut or your own action.")
                    Text("4) Launch \(app.name) once to activate the automation.")
                }
            }
            .font(.callout)
        }
    }
    
    private var unlockSettings: some View {
        let currentLevel = model.currentShieldLevel(for: app.bundleId)
        let spent = model.totalStepsSpent(for: app.bundleId)
        let stepsToNext = model.stepsToNextShieldLevel(for: app.bundleId)
        let accent = tileAccent(for: currentLevel)
        let timeAccessEnabled = model.isTimeAccessEnabled(for: app.bundleId)
        let minuteModeEnabled = model.isFamilyControlsModeEnabled(for: app.bundleId)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Access level")
                .font(.headline)
            
            levelHeaderButton(currentLevel: currentLevel, accent: accent)

            if showLevelsTable {
                levelsTableView(currentLevel: currentLevel, spent: spent, stepsToNext: stepsToNext, isMinuteMode: minuteModeEnabled)
            }
            
            accessModeSection(minuteModeEnabled: minuteModeEnabled, timeAccessEnabled: timeAccessEnabled)

            if minuteModeEnabled {
                minuteModeSection(timeAccessEnabled: timeAccessEnabled, selection: timeAccessSelection)
            } else {
                openModeSection(currentLevel: currentLevel, accent: accent)
            }
        
            Text("Levels change automatically based on steps spent on this shield.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
    
    @ViewBuilder
    private func levelHeaderButton(currentLevel: ShieldLevel, accent: Color) -> some View {
            Button {
                withAnimation(.easeInOut) {
                    showLevelsTable.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Level")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(currentLevel.label)
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.2)))
                    Spacer()
                    Image(systemName: showLevelsTable ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func levelsTableView(currentLevel: ShieldLevel, spent: Int, stepsToNext: Int?, isMinuteMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                    ForEach(ShieldLevel.all) { level in
                levelRow(level: level, currentLevel: currentLevel, spent: spent, stepsToNext: stepsToNext, isMinuteMode: isMinuteMode)
            }
        }
    }
    
    @ViewBuilder
    private func levelRow(level: ShieldLevel, currentLevel: ShieldLevel, spent: Int, stepsToNext: Int?, isMinuteMode: Bool) -> some View {
                        let isCurrent = level.id == currentLevel.id
        let isAchieved = level.threshold < currentLevel.threshold
        let levelAccent = tileAccent(for: level)
        
        VStack(alignment: .leading, spacing: 8) {
            levelRowHeader(level: level, isCurrent: isCurrent, isAchieved: isAchieved, levelAccent: levelAccent, isMinuteMode: isMinuteMode)
            
            if isCurrent {
                levelProgressSection(level: level, spent: spent, stepsToNext: stepsToNext, levelAccent: levelAccent)
            }
            
            levelPricesRow(level: level, isCurrent: isCurrent, levelAccent: levelAccent, isMinuteMode: isMinuteMode)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? levelAccent.opacity(0.12) : (isAchieved ? Color.green.opacity(0.06) : Color.gray.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isCurrent ? levelAccent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func levelRowHeader(level: ShieldLevel, isCurrent: Bool, isAchieved: Bool, levelAccent: Color, isMinuteMode: Bool) -> some View {
        HStack(spacing: 8) {
            if isAchieved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.body)
            } else if isCurrent {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(levelAccent)
                    .font(.body)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray.opacity(0.4))
                    .font(.body)
            }
            
                            Text("Level \(level.label)")
                                .font(.subheadline.weight(isCurrent ? .bold : .regular))
            
                            Spacer()
            
            let costLabel = isMinuteMode
                ? "\(level.entryCost) " + loc(appLanguage, "per min", "за мин")
                : "\(level.entryCost) " + loc(appLanguage, "per entry", "за вход")
            Text(costLabel)
                .font(.caption2.weight(.medium))
                .foregroundColor(isCurrent ? levelAccent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(isCurrent ? levelAccent.opacity(0.15) : Color.gray.opacity(0.1)))
        }
    }
    
    @ViewBuilder
    private func levelProgressSection(level: ShieldLevel, spent: Int, stepsToNext: Int?, levelAccent: Color) -> some View {
        let progress = levelProgressForGuide(spent: spent, level: level)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    Capsule()
                        .fill(levelAccent)
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                }
            }
            .frame(height: 6)
            
            HStack {
                Text("\(formatSteps(spent)) " + loc(appLanguage, "invested", "вложено"))
                    .font(.caption2)
                                        .foregroundColor(.secondary)
                Spacer()
                if let toNext = stepsToNext {
                    Text("\(formatSteps(toNext)) " + loc(appLanguage, "to next", "до след."))
                        .font(.caption2)
                                        .foregroundColor(.secondary)
                } else {
                    Text(loc(appLanguage, "MAX", "МАКС"))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(levelAccent)
                }
            }
        }
    }
    
    @ViewBuilder
    private func levelPricesRow(level: ShieldLevel, isCurrent: Bool, levelAccent: Color, isMinuteMode: Bool) -> some View {
        if isMinuteMode {
            // Minute mode: just show cost per minute
            Text("\(level.entryCost) " + loc(appLanguage, "per min", "за мин"))
                .font(.caption2.weight(.medium))
                .foregroundColor(isCurrent ? levelAccent : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isCurrent ? levelAccent.opacity(0.15) : Color.gray.opacity(0.1)))
        } else {
            // Open mode: show entry-based costs
            HStack(spacing: 12) {
                priceTag(loc(appLanguage, "5m", "5м"), cost: level.fiveMinutesCost, isCurrent: isCurrent, accent: levelAccent)
                priceTag(loc(appLanguage, "1h", "1ч"), cost: level.hourCost, isCurrent: isCurrent, accent: levelAccent)
                priceTag(loc(appLanguage, "Day", "День"), cost: level.dayCost, isCurrent: isCurrent, accent: levelAccent)
            }
                        .font(.caption2)
                }
            }
            
    @ViewBuilder
    private func accessModeSection(minuteModeEnabled: Bool, timeAccessEnabled: Bool) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc(appLanguage, "Access mode", "Режим доступа"))
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: Binding(get: {
                    minuteModeEnabled ? 1 : 0
                }, set: { newValue in
                    let enableMinuteMode = newValue == 1
                    model.setFamilyControlsModeEnabled(enableMinuteMode, for: app.bundleId)
                    model.setMinuteTariffEnabled(enableMinuteMode, for: app.bundleId)
                    if enableMinuteMode && timeAccessEnabled {
                        model.applyFamilyControlsSelection(for: app.bundleId)
                    } else {
                        model.rebuildFamilyControlsShield()
                    }
                })) {
                    Text(loc(appLanguage, "Open mode", "Открытый режим")).tag(0)
                    Text(loc(appLanguage, "Minute mode", "Минутный режим")).tag(1)
                }
                .pickerStyle(.segmented)

                if minuteModeEnabled {
                Text(loc(appLanguage, "Pay per minute of actual use. Requires Screen Time access.", "Платите за каждую минуту использования. Нужен доступ к Screen Time."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                Text(loc(appLanguage, "Pay once to unlock for a set time. Great for quick visits.", "Разовая оплата за доступ на время. Удобно для коротких визитов."))
                        .font(.caption)
                        .foregroundColor(.secondary)
            }
                }
            }

    @ViewBuilder
    private func minuteModeSection(timeAccessEnabled: Bool, selection: FamilyActivitySelection) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time access (Screen Time)")
                        .font(.subheadline.weight(.semibold))
            
            if timeAccessEnabled {
                HStack(spacing: 12) {
                    // Show selected app icons
                    #if canImport(FamilyControls)
                    ForEach(Array(selection.applicationTokens.prefix(5)), id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if selection.applicationTokens.count > 5 {
                        Text("+\(selection.applicationTokens.count - 5)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    #endif
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.1)))
            } else {
                Text(loc(appLanguage, "Select the app to enable time control.", "Выберите приложение для контроля времени."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button(timeAccessEnabled ? loc(appLanguage, "Change selection", "Изменить выбор") : loc(appLanguage, "Connect app", "Подключить")) {
                        Task {
                            try? await model.family.requestAuthorization()
                            showTimeAccessPicker = true
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.08)))
                }
    }
    
    @ViewBuilder
    private func openModeSection(currentLevel: ShieldLevel, accent: Color) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Access options")
                        .font(.subheadline.weight(.semibold))
                    accessOptionRow(title: "Day pass", window: .day1, level: currentLevel, tint: accent, isDisabled: false)
                    accessOptionRow(title: "1 hour", window: .hour1, level: currentLevel, tint: accent, isDisabled: false)
                    accessOptionRow(title: "5 minutes", window: .minutes5, level: currentLevel, tint: accent, isDisabled: false)
                    accessOptionRow(title: "Single entry", window: .single, level: currentLevel, tint: accent, isDisabled: false)
                }
    }

    private func formatSteps(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func levelProgressForGuide(spent: Int, level: ShieldLevel) -> Double {
        guard let nextThreshold = level.nextThreshold else { return 1.0 }
        let levelStart = level.threshold
        let levelSpan = nextThreshold - levelStart
        guard levelSpan > 0 else { return 1.0 }
        let localSpent = spent - levelStart
        return min(max(Double(localSpent) / Double(levelSpan), 0), 1)
    }
    
    @ViewBuilder
    private func priceTag(_ label: String, cost: Int, isCurrent: Bool, accent: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .foregroundColor(.secondary)
            Text("\(cost)")
                .foregroundColor(isCurrent ? accent : .primary)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.08))
        )
    }
    
    private func accessOptionRow(title: String, window: AccessWindow, level: ShieldLevel, tint: Color, isDisabled: Bool) -> some View {
        let cost = windowCost(for: level, window: window)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(cost) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(get: {
                model.allowedAccessWindows(for: app.bundleId).contains(window)
            }, set: { newValue in
                model.updateAccessWindow(window, enabled: newValue, for: app.bundleId)
            })) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: tint))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.08))
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
    }
    
    private func windowCost(for level: ShieldLevel, window: AccessWindow) -> Int {
        switch window {
        case .single: return level.entryCost
        case .minutes5: return level.fiveMinutesCost
        case .hour1: return level.hourCost
        case .day1: return level.dayCost
        }
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
    
    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc(appLanguage, "Manuals", "Мануалы"))
                    .font(.title2.bold())
                Text(loc(appLanguage, "Learn how to use shields effectively", "Узнайте, как эффективно использовать щиты"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Setup Guide Card
    private var setupGuideCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
                            Button {
                withAnimation(.spring(response: 0.3)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "gearshape.2.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                                    Text(appLanguage == "ru" ? "Как подключить щит" : "How to set up a shield")
                                        .font(.headline)
                            .foregroundColor(.primary)
                        Text(appLanguage == "ru" ? "Пошаговая инструкция" : "Step-by-step guide")
                            .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue.opacity(0.6))
                }
                .padding(16)
                            }
                            
                            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(alignment: .leading, spacing: 16) {
                    // Image carousel
                                    let manualImages = (1...11).map { "manual_1_\($0)" }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                                                Image(name)
                                                    .resizable()
                                                    .scaledToFit()
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                                                    .onTapGesture {
                                                        openGallery(images: manualImages, startAt: index)
                                                    }
                                            }
                                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                                    }
                                    
                    // Steps
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.number")
                                .foregroundColor(.blue)
                                    Text(appLanguage == "ru" ? "Шаги" : "Steps")
                                .font(.subheadline.bold())
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            stepRow(number: 1, text: appLanguage == "ru" ? "Откройте ссылку на щит и добавьте его в Команды." : "Open the shield link and add it to Shortcuts.")
                            stepRow(number: 2, text: appLanguage == "ru" ? "В Команды → Автоматизация → + → Приложение выберите нужное приложение и включите «Открыто» и «Выполнять сразу»." : "In Shortcuts → Automation → + → App, pick the target app and enable 'Is Opened' and 'Run Immediately'.")
                            stepRow(number: 3, text: appLanguage == "ru" ? "Укажите щит [app] CTRL и сохраните." : "Select the [app] CTRL shield and save.")
                            stepRow(number: 4, text: appLanguage == "ru" ? "Откройте приложение один раз, чтобы активировать автоматизацию." : "Open the app once to activate automation.")
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // Tip
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                                    Text(appLanguage == "ru" ? "Подсказка" : "Tip")
                                .font(.subheadline.bold())
                            Text(appLanguage == "ru" ? "Если щит не срабатывает, убедитесь, что включены уведомления и доступ к Командам." : "If the shield doesn't fire, ensure notifications and Shortcuts access are enabled.")
                                .font(.subheadline)
                                        .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.yellow.opacity(0.1))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
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
            ("flame.fill", .orange, "Чем больше путешествуете, тем сильнее прокачивается щит — топливо тратится, опыт копится.", "The more you travel, the stronger the shield gets — fuel spent turns into experience."),
            ("star.fill", .yellow, "Уровней 10: второй открывается после 10 000 шагов, дальше пороги растут до 500 000.", "There are 10 levels: level II at 10,000 steps, then thresholds grow up to 500,000."),
            ("bolt.fill", .green, "С ростом уровня входить легче: I=100 шагов, ... , X=10 шагов.", "Higher level = cheaper launch: I=100 steps ... X=10 steps."),
            ("chart.bar.fill", .blue, "За прогрессом смотрите в карточке щита: там видно, сколько топлива уже сожжено.", "Track your progress on the shield page to see how much fuel you've burned.")
        ]
        
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.ru) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon)
                        .foregroundColor(item.color)
                        .frame(width: 24)
                    Text(appLanguage == "ru" ? item.ru : item.en)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func entryOptionsContent() -> some View {
        let manualImages = ["manual_2_1", "manual_2_2", "manual_2_3"]
        let items: [(icon: String, color: Color, ru: String, en: String)] = [
            ("clock.fill", .purple, "Во время путешествий по соцсетям нужен разный запас времени.", "Different worlds need different fuel."),
            ("door.left.hand.open", .orange, "Где-то хватает одного входа, где-то надо «жить» часами.", "Sometimes one entry is enough, sometimes you camp there for hours."),
            ("square.grid.2x2.fill", .blue, "Выбирайте формат: разовый, 5 мин, 1 час или день.", "Pick your mode: single, 5 min, 1 hour, or a day pass."),
            ("bolt.fill", .green, "Стоимость зависит от уровня (10–100 шагов за вход, 50–500 за 5 мин и т.д.).", "Costs scale with your level (10–100 for single, 50–500 for 5 min, etc.)."),
            ("slider.horizontal.3", .gray, "Лишние варианты можно выключить в настройках щита.", "Toggle off the modes you don't need in the shield settings.")
        ]

        VStack(alignment: .leading, spacing: 16) {
            // Image carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                            .onTapGesture {
                                openGallery(images: manualImages, startAt: index)
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            // Text items
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items, id: \.ru) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .frame(width: 24)
                        Text(appLanguage == "ru" ? item.ru : item.en)
                            .font(.subheadline)
                        .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        }
        .padding(16)
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
                    // Icon
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(iconColor)
                    }
                    
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: expanded.wrappedValue ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundColor(iconColor.opacity(0.6))
                }
                .padding(16)
            }

            if expanded.wrappedValue {
                Divider()
                    .padding(.horizontal, 16)
                
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
