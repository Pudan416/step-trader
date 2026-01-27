import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import UIKit


struct AppsPage: View {
    @ObservedObject var model: AppModel
    let automationApps: [AutomationApp]
    @State private var clockTick: Int = 0
    private let tickTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var guideApp: GuideItem?
    @State private var showDeactivatedPicker: Bool = false
    @State private var statusVersion = UUID()
    @State private var openShieldBundleId: String? = nil
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
        .sorted { lhs, rhs in
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
            pickerView(apps: deactivatedOverflow, title: loc(appLanguage, "Other shields"))
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
                    Text(loc(appLanguage, "Unprotected"))
                        .font(.subheadline.weight(.semibold))
                    Text(loc(appLanguage, "These apps roam free. Fix that."))
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
                    Text(loc(appLanguage, "All locked down 🔒"))
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
                    Text(loc(appLanguage, "Your Arsenal"))
                        .font(.subheadline.weight(.semibold))
                    Text(loc(appLanguage, "Shields keeping you focused"))
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
                    Text(loc(appLanguage, "No shields active"))
                        .font(.caption.weight(.semibold))
                    Text(loc(appLanguage, "Pick an app above and take control 💪"))
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
        let accent = Color(red: 0.88, green: 0.51, blue: 0.85)
        let isMinuteMode = model.isFamilyControlsModeEnabled(for: app.bundleId)
        let hasActiveAccess = model.remainingAccessSeconds(for: app.bundleId).map { $0 > 0 } ?? false
        let settings = model.unlockSettings(for: app.bundleId)
        
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
                                Text(loc(appLanguage, isMinuteMode ? "Minute" : "Open"))
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
                                Text(loc(appLanguage, "Access: ") + formatRemaining(remaining))
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("\(formatSteps(spent)) " + loc(appLanguage, "invested"))
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
                
                // Cost info
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text(isMinuteMode 
                            ? "\(settings.entryCostSteps) " + loc(appLanguage, "/min")
                            : "\(settings.entryCostSteps) " + loc(appLanguage, "/entry"))
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(accent.opacity(0.15))
                    )
                    
                    Spacer()
                    
                    if spent > 0 {
                        Text("\(formatSteps(spent)) " + loc(appLanguage, "spent"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
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
                    Label(loc(appLanguage, "Deactivate shield"), systemImage: "trash")
                }
            case .none:
                Button {
                    activate(app)
                } label: {
                    Label(loc(appLanguage, "Activate"), systemImage: "checkmark.circle")
                }
            }
        }
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
                    Label(loc(appLanguage, "Deactivate shield"), systemImage: "trash")
                }
            case .none:
                Button {
                    activate(app)
                } label: {
                    Label(loc(appLanguage, "Activate"), systemImage: "checkmark.circle")
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
        // Use default costs
        model.updateUnlockSettings(for: app.bundleId, entryCost: 100, dayPassCost: 10000)
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
            .navigationBarItems(trailing: Button(loc(appLanguage, "Close")) {
                showDeactivatedPicker = false
            })
        }
    }
}

