import SwiftUI
import UIKit

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
        let label: String
        let tariff: Tariff
        let threshold: Int
        let nextThreshold: Int?
        
        var id: String { label }
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
        [
            .init(label: "I", tariff: .hard, threshold: 0, nextThreshold: 10_000),
            .init(label: "II", tariff: .medium, threshold: 10_000, nextThreshold: 30_000),
            .init(label: "III", tariff: .easy, threshold: 30_000, nextThreshold: 100_000),
            .init(label: "IV", tariff: .free, threshold: 100_000, nextThreshold: nil)
        ]
    }
    
    var body: some View {
        NavigationView {
            let horizontalPadding: CGFloat = 16
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    deactivatedSection(horizontalPadding: horizontalPadding)
                    activatedSection
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 12)
                .id(statusVersion)
            }
            .scrollIndicators(.hidden)
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
            pickerView(apps: deactivatedOverflow, title: loc(appLanguage, "Other modules", "Остальные модули"))
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
        let columns = 6
        let availableWidth = UIScreen.main.bounds.width - horizontalPadding * 2
        let tileSize = max(48, (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Deactivated modules", "Неактивные модули"))
                .font(.headline)
            
            if deactivatedAll.isEmpty {
                Text(loc(appLanguage, "All modules are connected", "Все модули подключены"))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    }
    
    @ViewBuilder
    private var activatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Activated modules", "Подключенные модули"))
                .font(.headline)
            
            if activatedApps.isEmpty {
                Text(loc(appLanguage, "No modules here yet.", "Пока пусто."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(activatedApps) { app in
                            moduleLevelCard(for: app)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func overflowTile(size: CGFloat) -> some View {
        Button {
            showDeactivatedPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.08))
                .frame(width: size, height: size)
                .overlay(
                    Text("...")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color.gray.opacity(0.7))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func moduleLevelCard(for app: AutomationApp) -> some View {
        let status = statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet)
        let spent = spentSteps(for: app)
        let current = currentLevel(forSpent: spent)
        let nextSteps = stepsToNextLevel(forSpent: spent)
        
        return Button {
            openGuide(for: app, status: status)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        appIconView(app)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if let remaining = model.remainingAccessSeconds(for: app.bundleId), remaining > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text(formatRemaining(remaining))
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .padding(2)
                        }
                    }
                    .id(clockTick)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.headline)
                        Text(moduleCardSubtitle(for: current, stepsLeft: nextSteps))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    statusIcon(for: status)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(moduleLevels) { stage in
                        moduleLevelRow(for: stage, spent: spent, current: current)
                    }
                }
                
                Text("\(formatSteps(spent)) " + loc(appLanguage, "steps spent in this module", "шагов потрачено в модуле"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(width: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            switch status {
            case .configured, .pending:
                Button(role: .destructive) {
                    deactivate(app)
                } label: {
                    Label(loc(appLanguage, "Deactivate module", "Отключить модуль"), systemImage: "trash")
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
                .tint(tileAccent(for: stage.tariff))
                .progressViewStyle(.linear)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tileAccent(for: stage.tariff).opacity(active ? 0.16 : 0.08))
        )
    }
    
    private func moduleCardSubtitle(for level: ModuleLevelStage, stepsLeft: Int?) -> String {
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
        model.appStepsSpentToday[app.bundleId, default: 0]
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
        let costs = levelCosts(for: stage.tariff)
        let entryLine = loc(appLanguage, "Entry: \(formatSteps(costs.entry)) steps", "Вход: \(formatSteps(costs.entry)) шагов")
        let fiveLine = loc(appLanguage, "5 minutes: \(formatSteps(costs.fiveMinutes)) steps", "5 минут: \(formatSteps(costs.fiveMinutes)) шагов")
        let hourLine = loc(appLanguage, "1 hour: \(formatSteps(costs.hour)) steps", "1 час: \(formatSteps(costs.hour)) шагов")
        let dayLine = loc(appLanguage, "Day: \(formatSteps(costs.day)) steps", "День: \(formatSteps(costs.day)) шагов")
        return [entryLine, fiveLine, hourLine, dayLine].joined(separator: "\n")
    }
    
    private func levelCosts(for tariff: Tariff) -> (entry: Int, fiveMinutes: Int, hour: Int, day: Int) {
        let entry = tariff.entryCostSteps
        let five = windowCost(for: tariff, window: .minutes5)
        let hour = windowCost(for: tariff, window: .hour1)
        let day = windowCost(for: tariff, window: .day1)
        return (entry, five, hour, day)
    }
    
    private func windowCost(for tariff: Tariff, window: AccessWindow) -> Int {
        switch tariff {
        case .free:
            return 0
        case .easy:
            switch window {
            case .single: return 10
            case .minutes5: return 50
            case .hour1: return 500
            case .day1: return 5000
            }
        case .medium:
            switch window {
            case .single: return 50
            case .minutes5: return 250
            case .hour1: return 2500
            case .day1: return 10000
            }
        case .hard:
            switch window {
            case .single: return 100
            case .minutes5: return 500
            case .hour1: return 5000
            case .day1: return 20000
            }
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
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(tileColor(for: tariff, status: status))
                        .frame(width: width, height: width)
                        .overlay(
                            ZStack {
                                appIconView(app)
                                    .frame(width: width * 0.6, height: width * 0.6)
                                if let remaining = model.remainingAccessSeconds(for: app.bundleId), remaining > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "timer")
                                        Text(formatRemaining(remaining))
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Capsule())
                                    .padding(6)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                }
                            }
                            .id(clockTick)
                        )
                    statusIcon(for: status)
                        .padding(6)
                }
            }
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            switch status {
            case .configured, .pending:
                Button(role: .destructive) {
                    deactivate(app)
                } label: {
                    Label(loc(appLanguage, "Deactivate module", "Отключить модуль"), systemImage: "trash")
                }
            case .none:
                Button {
                    activate(app)
                } label: {
                    Label(loc(appLanguage, "Activate", "Активировать"), systemImage: "checkmark.circle")
                }
            }
        }
        .opacity(status == .none ? 0.55 : 1.0)
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
    
    private func tileAccent(for tariff: Tariff) -> Color {
        switch tariff {
        case .free: return Color.cyan.opacity(0.7)
        case .easy: return Color.green.opacity(0.7)
        case .medium: return Color.orange.opacity(0.8)
        case .hard: return Color.red.opacity(0.8)
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
    
    private func activate(_ app: AutomationApp, tariff: Tariff? = nil) {
        markPending(bundleId: app.bundleId)
        let selectedTariff = tariff ?? .hard
        model.updateUnlockSettings(for: app.bundleId, tariff: selectedTariff)
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
    
    private func dayPassCost(for tariff: Tariff) -> Int {
        switch tariff {
        case .free: return 0
        case .easy: return 1000
        case .medium: return 5000
        case .hard: return 10000
        }
    }
    
    private func currentTariff(for app: AutomationApp) -> Tariff {
        let settings = model.unlockSettings(for: app.bundleId)
        if let tariff = Tariff.allCases.first(where: {
            $0.entryCostSteps == settings.entryCostSteps && dayPassCost(for: $0) == settings.dayPassCostSteps
        }) {
            return tariff
        }
        return .hard
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

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: 8)
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
                            Text(app.status == .configured ? "Update the module" : "Get the module")
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

                Spacer()
                
                if app.status != .none {
                    Button {
                        if app.status == .configured {
                            showDeactivateAlert = true
                        } else {
                            deleteModule(app.bundleId)
                            dismiss()
                        }
                    } label: {
                        Text("Deactivate module")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.85))
                            )
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Deactivate module", isPresented: $showDeactivateAlert) {
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://automation") ?? URL(string: "shortcuts://") {
                        openURL(url)
                    }
                    deleteModule(app.bundleId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { showDeactivateAlert = false }
            } message: {
                Text("To fully deactivate this module, remove the automation from the Shortcuts app.")
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
                        Text("Module for \(app.name) is working")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    case .pending:
                        Text("Module is not connected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    case .none:
                        Text("The module for \(app.name) is not taken")
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
                    Text("3) Pick the universal Space CTRL shortcut or your own action.")
                    Text("4) Launch \(app.name) once to activate the automation.")
                }
            }
            .font(.callout)
        }
    }
    
    private var unlockSettings: some View {
        let currentTariff = model.currentLevelTariff(for: app.bundleId)
        let accent = tileAccent(for: currentTariff)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Access level")
                .font(.headline)
            
            HStack(spacing: 10) {
                Text("Level")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(currentTariff.displayName)
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(accent.opacity(0.2))
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Access options")
                    .font(.subheadline.weight(.semibold))
                accessOptionRow(title: "Day pass", window: .day1, tariff: currentTariff, tint: accent)
                accessOptionRow(title: "1 hour", window: .hour1, tariff: currentTariff, tint: accent)
                accessOptionRow(title: "5 minutes", window: .minutes5, tariff: currentTariff, tint: accent)
                accessOptionRow(title: "Single entry", window: .single, tariff: currentTariff, tint: accent)
            }
            
            Text("Levels change automatically based on steps spent in this module.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
    
    private func accessOptionRow(title: String, window: AccessWindow, tariff: Tariff, tint: Color) -> some View {
        let cost = windowCost(for: tariff, window: window)
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
    }
    
    private func windowCost(for tariff: Tariff, window: AccessWindow) -> Int {
        switch tariff {
        case .free:
            return 0
        case .easy:
            switch window {
            case .single: return 10
            case .minutes5: return 50
            case .hour1: return 500
            case .day1: return 5000
            }
        case .medium:
            switch window {
            case .single: return 50
            case .minutes5: return 250
            case .hour1: return 2500
            case .day1: return 10000
            }
        case .hard:
            switch window {
            case .single: return 100
            case .minutes5: return 500
            case .hour1: return 5000
            case .day1: return 20000
            }
        }
    }
    
    private func tileAccent(for tariff: Tariff) -> Color {
        switch tariff {
        case .free: return Color.cyan.opacity(0.7)
        case .easy: return Color.green.opacity(0.7)
        case .medium: return Color.orange.opacity(0.8)
        case .hard: return Color.red.opacity(0.8)
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
    private let cardBackground = Color.gray.opacity(0.08)
    
    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation(.easeInOut) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                HStack {
                                    Text(appLanguage == "ru" ? "Как подключить модуль" : "How to set up a module")
                                        .font(.title3.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 12) {
                                    let manualImages = (1...11).map { "manual_1_\($0)" }
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                                                Image(name)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(height: 220)
                                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                                    .shadow(radius: 4)
                                                    .onTapGesture {
                                                        openGallery(images: manualImages, startAt: index)
                                                    }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    
                                    Text(appLanguage == "ru" ? "Шаги" : "Steps")
                                        .font(.headline)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(appLanguage == "ru" ? "1. Откройте ссылку на модуль и добавьте его в Команды." : "1. Open the module link and add it to Shortcuts.")
                                        Text(appLanguage == "ru" ? "2. В Команды → Автоматизация → + → Приложение выберите нужное приложение и включите «Открыто» и «Выполнять сразу»." : "2. In Shortcuts → Automation → + → App, pick the target app and enable “Is Opened” and “Run Immediately”.")
                                        Text(appLanguage == "ru" ? "3. Укажите модуль [Space] CTRL и сохраните." : "3. Select the [Space] CTRL module and save.")
                                        Text(appLanguage == "ru" ? "4. Откройте приложение один раз, чтобы активировать автоматизацию." : "4. Open the app once to activate automation.")
                                    }
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    
                                    Text(appLanguage == "ru" ? "Подсказка" : "Tip")
                                        .font(.headline)
                                    Text(appLanguage == "ru" ? "Если модуль не срабатывает, убедитесь, что включены уведомления и доступ к Командам." : "If the module doesn’t fire, ensure notifications and Shortcuts access are enabled.")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(cardBackground))
                    }
                    .padding()

                    expandableCard(
                        title: appLanguage == "ru" ? "Как прокачивать уровни" : "How levels grow",
                        expanded: $isLevelsExpanded,
                        content: levelsContent
                    )

                    expandableCard(
                        title: appLanguage == "ru" ? "Как настраивать варианты входа" : "How to configure entry options",
                        expanded: $isEntryExpanded,
                        content: entryOptionsContent
                    )
                }
                
                if showGallery {
                    ZStack {
                        Color.black.opacity(0.75)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture { closeGallery() }
                        
                        TabView(selection: $galleryIndex) {
                            ForEach(Array(galleryImages.enumerated()), id: \.offset) { index, name in
                                if let uiImage = UIImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                        .tag(index)
                                        .padding()
                                } else {
                                    Color.clear.tag(index)
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .background(Color.clear)
                        .ignoresSafeArea()
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if abs(value.translation.height) > 60 {
                                        closeGallery()
                                    }
                                }
                        )
                    }
                    .zIndex(2)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .background(Color.clear)
        .onDisappear {
            showGallery = false
            galleryImages = []
            isExpanded = false
            isLevelsExpanded = false
            isEntryExpanded = false
        }
    }

    @ViewBuilder
    private func levelsContent() -> some View {
        let ru = [
            "• Чем больше путешествуете, тем сильнее прокачивается модуль — топливо тратится, опыт копится.",
            "• Уровни: II после 10 000 шагов, III после 30 000, IV после 100 000 в этом модуле.",
            "• С ростом уровня входить легче: I=100 шагов, II=50, III=10, IV=0 — просто фиксируете свои вылеты.",
            "• За прогрессом смотрите в карточке модуля: там видно, сколько топлива уже сожжено."
        ]
        let en = [
            "• The more you travel, the stronger the module gets — fuel spent turns into experience.",
            "• Levels: II at 10,000 steps, III at 30,000, IV at 100,000 in that module.",
            "• Higher level = cheaper launch: I=100 steps, II=50, III=10, IV=0 — just log your departures.",
            "• Track your progress on the module page to see how much fuel you've burned."
        ]
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appLanguage == "ru" ? ru : en, id: \.self) { line in
                Text(line).font(.body).foregroundColor(.primary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(cardBackground))
    }

    @ViewBuilder
    private func entryOptionsContent() -> some View {
        let manualImages = ["manual_2_1", "manual_2_2", "manual_2_3"]
        let ruText = [
            "Во время путешествий по соцсетям нужен разный запас времени.",
            "Где-то хватает одного входа, где-то надо «жить» часами.",
            "Выбирайте формат: разовый, 5 мин, 1 час или день.",
            "Стоимость зависит от уровня (от 10 до 100 шагов за вход, 5–500 за 5 мин, 500–5000 за час, день по тарифу).",
            "Лишние варианты можно выключить в настройках модуля — их не будет на PayGate."
        ]
        let enText = [
            "Different worlds need different fuel.",
            "Sometimes one entry is enough, sometimes you camp there for an hour.",
            "Pick your mode: single, 5 min, 1 hour, or a day pass.",
            "Costs scale with your level (about 10–100 steps for single, 5–500 for 5 min, 500–5000 for an hour, day by tariff).",
            "Toggle off the modes you don’t need in the module settings — they disappear from PayGate."
        ]

        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(manualImages.enumerated()), id: \.offset) { index, name in
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(radius: 3)
                            .onTapGesture {
                                openGallery(images: manualImages, startAt: index)
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(appLanguage == "ru" ? ruText : enText, id: \.self) { line in
                    Text(line)
                        .font(.body)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(cardBackground))
    }

    private func openGallery(images: [String], startAt index: Int) {
        galleryImages = images
        galleryIndex = index
        withAnimation(.easeInOut) {
            showGallery = true
        }
    }
    
    private func closeGallery() {
        withAnimation(.easeInOut) {
            showGallery = false
        }
    }

    private func expandableCard(title: String, expanded: Binding<Bool>, content: @escaping () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(cardBackground))
            }

            if expanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(cardBackground))
    }
}
