import SwiftUI
import UIKit

struct AppsPage: View {
    @ObservedObject var model: AppModel
    let automationApps: [AutomationApp]
    let tariffs: [Tariff]
    @State private var clockTick: Int = 0
    private let tickTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var guideApp: GuideItem?
    @State private var showPopularPicker: Bool = false
    @State private var showOtherPicker: Bool = false
    @State private var pendingTariffForPicker: Tariff? = nil
    @State private var statusVersion = UUID()
    @AppStorage("appLanguage") private var appLanguage: String = "en"
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
    }

    private func groupedActivatedApps() -> [(Tariff, [AutomationApp])] {
        let groups = Dictionary(grouping: activatedApps) { currentTariff(for: $0) }
        return Tariff.allCases.map { tariff in
            let list = groups[tariff] ?? []
            return (tariff, list.sorted { $0.name < $1.name })
        }
    }
    
    private var deactivatedApps: [AutomationApp] {
        automationApps.filter {
            let status = statusFor($0, configured: automationConfiguredSet, pending: automationPendingSet)
            return status == .none
        }
        .sorted { $0.name < $1.name }
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
    
    private var othersPreview: [AutomationApp] {
        Array(deactivatedOthers.prefix(3))
    }
    
    private var othersRest: [AutomationApp] {
        Array(deactivatedOthers.dropFirst(3))
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let horizontalPadding: CGFloat = 16
                let columnSpacing: CGFloat = 12
                let columnWidth = (geo.size.width - horizontalPadding * 2 - columnSpacing) / 2
                let gridSpacing: CGFloat = 10
                let gridItemSize = max(64.0, (columnWidth - gridSpacing) / 2)
                let bottomPadding: CGFloat = 8
                
                HStack(alignment: .top, spacing: columnSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc(appLanguage, "Activated", "Активированные"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        ScrollView {
                            if activatedApps.isEmpty {
                                Text(loc(appLanguage, "No modules here yet.", "Пока пусто."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    ForEach(groupedActivatedApps(), id: \.0) { tariff, apps in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(tariffHeader(for: tariff))
                                                .font(.subheadline)
                                                .bold()
                                            activatedGrid(for: apps, size: gridItemSize, spacing: gridSpacing, tariff: tariff)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(.bottom, bottomPadding)
                        .scrollIndicators(.hidden)
                    }
                    .frame(width: columnWidth, height: geo.size.height, alignment: .topLeading)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(loc(appLanguage, "Deactivated", "Неактивные"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                // Popular subset
                                Text(loc(appLanguage, "Main", "Главные"))
                                    .font(.subheadline).bold()
                                let columns = Array(repeating: GridItem(.fixed(gridItemSize), spacing: gridSpacing), count: 2)
                                LazyVGrid(columns: columns, alignment: .center, spacing: gridSpacing) {
                                    ForEach(deactivatedPopular) { app in
                                        automationButton(
                                            app,
                                            status: statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet),
                                            width: gridItemSize
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                
                                // Others list with preview + full list
                                Text(loc(appLanguage, "Others", "Другие"))
                                    .font(.subheadline).bold()
                                LazyVGrid(columns: columns, alignment: .center, spacing: gridSpacing) {
                                    ForEach(othersPreview) { app in
                                        automationButton(
                                            app,
                                            status: statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet),
                                            width: gridItemSize
                                        )
                                    }
                                    if !othersRest.isEmpty {
                                        Button {
                                            showOtherPicker = true
                                        } label: {
                                            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color.gray.opacity(0.08))
                                                .frame(width: gridItemSize, height: gridItemSize)
                                                .overlay(
                                                    Text("...")
                                                        .font(.system(size: 28, weight: .bold))
                                                        .foregroundColor(Color.gray.opacity(0.7))
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                
                                // Websites placeholder
                                Text(loc(appLanguage, "Websites", "Сайты"))
                                    .font(.subheadline).bold()
                                Button {
                                    // Placeholder, no action
                                } label: {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.gray.opacity(0.12))
                                        .frame(height: 50)
                                        .overlay(
                                            Text(loc(appLanguage, "Web links", "Веб-сайты"))
                                                .foregroundColor(.secondary)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollIndicators(.hidden)
                        .padding(.bottom, bottomPadding)
                    }
                    .frame(width: columnWidth, height: geo.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, horizontalPadding)
                .id(statusVersion)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .sheet(item: $guideApp, onDismiss: { guideApp = nil }) { item in
            AutomationGuideView(
                app: item,
                model: model,
                markPending: markPending(bundleId:),
                deleteModule: deactivate(bundleId:),
                entryTariffBinding: entryTariffSliderBinding(for:),
                dayPassTariffBinding: dayPassTariffSliderBinding(for:),
                tariffs: tariffs
            )
        }
        .sheet(isPresented: $showPopularPicker) {
            pickerView(apps: deactivatedPopular, title: loc(appLanguage, "Popular apps", "Популярные приложения"))
        }
        .sheet(isPresented: $showOtherPicker) {
            pickerView(apps: deactivatedOthers, title: loc(appLanguage, "Other apps", "Другие приложения"))
        }
        .onReceive(tickTimer) { _ in
            clockTick &+= 1
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

    private func statusPriority(_ status: AutomationStatus) -> Int {
        switch status {
        case .configured: return 0
        case .pending: return 1
        case .none: return 2
        }
    }

    private func tariffHeader(for tariff: Tariff) -> String {
        let count = activatedApps.filter { currentTariff(for: $0) == tariff }.count
        let maxText = "4"
        let base: String
        switch tariff {
        case .free: base = loc(appLanguage, "Free", "Free")
        case .easy: base = loc(appLanguage, "Lite", "Lite")
        case .medium: base = loc(appLanguage, "Medium", "Medium")
        case .hard: base = loc(appLanguage, "Hard", "Hard")
        }
        return "\(base) (\(count)/\(maxText))"
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
                                    let mins = max(0, remaining / 60)
                                    let secs = max(0, remaining % 60)
                                    let formatted = String(format: "%02d:%02d", mins, secs)
                                    Text(formatted)
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.45))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 6)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
        if let tariff {
            model.updateUnlockSettings(
                for: app.bundleId,
                entryCost: tariff.entryCostSteps,
                dayPassCost: dayPassCost(for: tariff)
            )
        }
        statusVersion = UUID()
    }
    
    // Sheet with full list per category
    private func pickerView(apps: [AutomationApp], title: String) -> some View {
        NavigationView {
            List {
                ForEach(apps) { app in
                    Button {
                        if let tariff = pendingTariffForPicker {
                            activate(app, tariff: tariff)
                            pendingTariffForPicker = nil
                            showPopularPicker = false
                            showOtherPicker = false
                        } else {
                            // Open guide without auto-activating
                            let item = GuideItem(
                                name: app.name,
                                icon: app.icon,
                                imageName: app.imageName,
                                scheme: app.scheme,
                                link: app.link,
                                status: statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet),
                                bundleId: app.bundleId
                            )
                            guideApp = item
                            showPopularPicker = false
                            showOtherPicker = false
                        }
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
                showPopularPicker = false
                showOtherPicker = false
            })
        }
    }
    
    // MARK: - Tariff sliders
    private func entryTariffSliderBinding(for app: AutomationApp) -> Binding<Double> {
        Binding<Double>(
            get: { Double(indexForEntryTariff(app)) },
            set: { newValue in
                let idx = min(max(Int(newValue.rounded()), 0), tariffs.count - 1)
                let tariff = tariffs[idx]
                guard canAssign(tariff: tariff, to: app) else {
                    model.message = loc(appLanguage, "Limit reached for \(tariff.displayName)", "Достигнут лимит для \(tariff.displayName)")
                    statusVersion = UUID()
                    return
                }
                model.updateUnlockSettings(
                    for: app.bundleId,
                    entryCost: tariff.entryCostSteps,
                    dayPassCost: dayPassCost(for: tariff)
                )
            }
        )
    }
    
    private func dayPassTariffSliderBinding(for app: AutomationApp) -> Binding<Double> {
        Binding<Double>(
            get: { Double(indexForDayPassTariff(app)) },
            set: { newValue in
                let idx = min(max(Int(newValue.rounded()), 0), tariffs.count - 1)
                let tariff = tariffs[idx]
                guard canAssign(tariff: tariff, to: app) else {
                    model.message = loc(appLanguage, "Limit reached for \(tariff.displayName)", "Достигнут лимит для \(tariff.displayName)")
                    statusVersion = UUID()
                    return
                }
                let cost = dayPassCost(for: tariff)
                model.updateUnlockSettings(
                    for: app.bundleId,
                    entryCost: tariff.entryCostSteps,
                    dayPassCost: cost
                )
            }
        )
    }
    
    private func indexForEntryTariff(_ app: AutomationApp) -> Int {
        let tariff = currentTariff(for: app)
        return tariffs.firstIndex(of: tariff) ?? 0
    }
    
    private func indexForDayPassTariff(_ app: AutomationApp) -> Int {
        let tariff = currentTariff(for: app)
        return tariffs.firstIndex(of: tariff) ?? 0
    }
    
    private func dayPassCost(for tariff: Tariff) -> Int {
        switch tariff {
        case .free: return 0
        case .easy: return 1000
        case .medium: return 5000
        case .hard: return 10000
        }
    }
    
    private var remainingStepsToday: Int {
        max(0, Int(model.stepsToday) - model.spentStepsToday)
    }
    
    // MARK: - Layout for activated groups
    private func activatedGrid(for apps: [AutomationApp], size: CGFloat, spacing: CGFloat, tariff: Tariff) -> some View {
        let columns = Array(repeating: GridItem(.fixed(size), spacing: spacing), count: 2)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(0..<4, id: \.self) { idx in
                if idx < apps.count {
                    let app = apps[idx]
                    automationButton(
                        app,
                        status: statusFor(app, configured: automationConfiguredSet, pending: automationPendingSet),
                        width: size,
                        tariff: tariff
                    )
                } else {
                    addCard(size: size, tariff: tariff)
                }
            }
        }
    }

    private func addCard(size: CGFloat, tariff: Tariff) -> some View {
        Button {
            pendingTariffForPicker = tariff
            showPopularPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 18)
                .fill(tileColor(for: tariff, status: .none))
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(tileAccent(for: tariff))
                )
                .frame(width: size, height: size)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func nextDeactivatedPopular() -> AutomationApp? {
        deactivatedPopular.first
    }
    
    private func currentTariff(for app: AutomationApp) -> Tariff {
        let settings = model.unlockSettings(for: app.bundleId)
        if let tariff = Tariff.allCases.first(where: {
            $0.entryCostSteps == settings.entryCostSteps && dayPassCost(for: $0) == settings.dayPassCostSteps
        }) {
            return tariff
        }
        return .easy
    }

    private func maxAllowed(for tariff: Tariff) -> Int? {
        switch tariff {
        case .free: return 4
        case .easy: return 4
        case .medium: return 4
        case .hard: return 4
        }
    }

    private func canAssign(tariff: Tariff, to app: AutomationApp) -> Bool {
        let current = currentTariff(for: app)
        if current == tariff { return true }
        guard let limit = maxAllowed(for: tariff) else { return true }

        let activeCount = activatedApps.filter {
            statusFor($0, configured: automationConfiguredSet, pending: automationPendingSet) != .none
                && currentTariff(for: $0) == tariff
                && $0.bundleId != app.bundleId
        }.count

        return activeCount < limit
    }
}

struct AutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let app: GuideItem
    @ObservedObject var model: AppModel
    let markPending: (String) -> Void
    let deleteModule: (String) -> Void
    let entryTariffBinding: (AutomationApp) -> Binding<Double>
    let dayPassTariffBinding: (AutomationApp) -> Binding<Double>
    let tariffs: [Tariff]
    @State private var showDeactivateAlert = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                header

                unlockSettings

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
            HStack(spacing: 12) {
                guideIconView()
                    .frame(width: 48, height: 48)
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
                        Text("The module is provided but not connected to \(app.name)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    case .none:
                        Text("The module for \(app.name) is not taken")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if app.status == .configured || app.status == .pending {
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 80)
                    .foregroundColor(app.status == .configured ? .green : .yellow)
                    .padding(.top, 8)
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
    
    private func entryLabel(for app: AutomationApp) -> String {
        let idx = min(max(Int(entryTariffBinding(app).wrappedValue.rounded()), 0), tariffs.count - 1)
        let tariff = tariffs[idx]
        return "\(tariff.displayName) • \(tariff.entryCostSteps) steps"
    }
    
    private func dayPassLabel(for app: AutomationApp) -> String {
        let idx = min(max(Int(dayPassTariffBinding(app).wrappedValue.rounded()), 0), tariffs.count - 1)
        let tariff = tariffs[idx]
        return "\(tariff.displayName) • \(dayPassCost(for: tariff)) steps"
    }
    
    private func dayPassCost(for tariff: Tariff) -> Int {
        switch tariff {
        case .free: return 0
        case .easy: return 1000
        case .medium: return 5000
        case .hard: return 10000
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
                    Text("3) Pick the universal Steps Trader shortcut or your own action.")
                    Text("4) Launch \(app.name) once to activate the automation.")
                }
            }
            .font(.callout)
        }
    }
    
    private var unlockSettings: some View {
        let automationApp = AutomationApp(
            name: app.name,
            scheme: app.scheme,
            icon: app.icon,
            imageName: app.imageName,
            link: app.link,
            bundleId: app.bundleId
        )
        let settings = model.unlockSettings(for: app.bundleId)
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("Unlock settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Single entry")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: entryTariffBinding(automationApp),
                    in: 0...Double(tariffs.count - 1),
                    step: 1
                )
                Text(entryLabel(for: automationApp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Day pass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(
                    value: dayPassTariffBinding(automationApp),
                    in: 0...Double(tariffs.count - 1),
                    step: 1
                )
                Text(dayPassLabel(for: automationApp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Per entry")
                    Spacer()
                    Text("\(settings.entryCostSteps) steps")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Day pass")
                    Spacer()
                    if model.hasDayPass(for: app.bundleId) {
                        Text("Active today")
                            .foregroundColor(.green)
                    } else {
                        Text("\(settings.dayPassCostSteps) steps")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
}

struct ManualsPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @State private var isExpanded: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        withAnimation(.easeInOut) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(appLanguage == "ru" ? "Как подключить модуль" : "How to set a module")
                                .font(.title2)
                                .fontWeight(.bold)
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 180)
                                .overlay(
                                    Text(appLanguage == "ru" ? "Место для картинки" : "Image placeholder")
                                        .foregroundColor(.secondary)
                                )
                            
                            Text(appLanguage == "ru" ? "Шаги" : "Steps")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(appLanguage == "ru" ? "1. Откройте ссылку на модуль и добавьте его в Команды." : "1. Open the module link and add it to Shortcuts.")
                                Text(appLanguage == "ru" ? "2. В Команды → Автоматизация → + → Приложение выберите нужное приложение и включите «Открыто» и «Выполнять сразу»." : "2. In Shortcuts → Automation → + → App, pick the target app and enable “Is Opened” and “Run Immediately”.")
                                Text(appLanguage == "ru" ? "3. Укажите модуль Steps Trader и сохраните." : "3. Select the Steps Trader module and save.")
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
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.08)))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .background(Color.clear)
    }
}
