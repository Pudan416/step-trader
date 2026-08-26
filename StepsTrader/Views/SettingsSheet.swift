import SwiftUI
import WidgetKit
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Settings Sheet (matte tactile hub — no liquid glass)
/// The settings page intentionally drops the liquid-glass treatment used by
/// the floating tab bar and energy card. Inside the page the gradient is
/// dimmed by a matte wash and an additional grain layer is rendered *over*
/// the content so the rows read like ink stamped on paper. The visual
/// contrast (glossy chrome ↔ matte interior) is the point.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    var embeddedInTab: Bool = false
    /// Optional externally-owned deep-link route. The host (MainTabView) owns it
    /// so a feature-tip CTA can push a sub-page even if this tab was never opened
    /// before (lazy TabView content): the value is already set by the time this
    /// view is first created, so `navigationDestination` pushes on appear.
    var featureTipRouteBinding: Binding<FeatureTipSettingsPage?>? = nil

    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @State private var showLogin = false
    @State private var showProfileEditor = false
    /// Fallback route storage when no external binding is supplied (preview /
    /// standalone usage). The tab instance uses `featureTipRouteBinding` instead.
    @State private var localFeatureTipRoute: FeatureTipSettingsPage?

    private var featureTipRoute: Binding<FeatureTipSettingsPage?> {
        featureTipRouteBinding ?? $localFeatureTipRoute
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(String(localized: "Settings", comment: "Settings page title"))
                        .font(.geist(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .padding(.top, 8)

                    accountRow

                    section(header: String(localized: "General", comment: "Settings section header")) {
                        flatRow(icon: "paintpalette", title: String(localized: "Appearance")) {
                            SettingsAppearancePage(model: model)
                        }
                        rowDivider
                        flatRow(icon: "bell", title: String(localized: "Notifications")) {
                            NotificationSettingsView(model: model)
                        }
                    }

                    section(header: String(localized: "System", comment: "Settings section header")) {
                        permissionsRow
                        rowDivider
                        flatRow(icon: "photo.on.rectangle.angled", title: String(localized: "Wallpaper")) {
                            SettingsShortcutPage(model: model)
                        }
                        rowDivider
                        flatRow(icon: "square.stack.3d.up", title: String(localized: "Widget")) {
                            SettingsWidgetPage(model: model)
                        }
                    }

                    section(header: String(localized: "Info", comment: "Settings section header")) {
                        flatRow(icon: "book", title: String(localized: "Notes from Kosta", comment: "Settings row label")) {
                            ManualsPage(model: model)
                        }
                        rowDivider
                        flatRow(icon: "info.circle", title: String(localized: "About", comment: "Settings row label")) {
                            SettingsAboutPage(model: model)
                        }
                    }

                    #if DEBUG
                    section(header: "Developer") {
                        shieldDiagnosticsRows
                    }
                    #endif

                    versionFooter
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 96)
            }
            .energyGradientBackground(model: model, showGrain: false)
            .overlay {
                // Subtle grain rendered ABOVE the rows so the plain-text
                // settings interior still has a tactile printed feel —
                // without darkening the underlying gradient.
                // Grain removed — textures only on canvas & feeds
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: embeddedInTab ? topCardHeight : 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: featureTipRoute) { page in
                switch page {
                case .wallpaper:
                    SettingsShortcutPage(model: model)
                case .widget:
                    SettingsWidgetPage(model: model)
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService, model: model)
            }
            #if DEBUG
            .fullScreenCover(isPresented: $showOnboardingDemo) {
                OnboardingDemoView()
            }
            .fullScreenCover(isPresented: $replayOnboardingLive) {
                OnboardingFlowView(
                    model: model,
                    authService: authService,
                    showsDebugSkip: true
                ) {
                    replayOnboardingLive = false
                }
            }
            #endif
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.uppercased())
                .font(.geist(.caption2).weight(.semibold))
                .tracking(3)
                .foregroundStyle(theme.adaptiveMutedText)
                .padding(.leading, 2)

            VStack(spacing: 0) { content() }

            Rectangle()
                .fill(theme.adaptiveDividerColor.opacity(0.7))
                .frame(height: 0.5)
                .padding(.top, 4)
        }
    }

    // MARK: - Permissions row

    private var permissionsRow: some View {
        NavigationLink {
            SettingsPermissionsPage(model: model)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    rowIcon("lock.shield")
                    if model.hasPermissionIssues {
                        Circle()
                            .fill(.orange)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: -2)
                    }
                }
                rowTitle(String(localized: "Permissions", comment: "Settings row label"))
                Spacer()
                if model.hasPermissionIssues {
                    Text(String(localized: "Action needed", comment: "Permissions warning label").uppercased())
                        .font(.geist(.caption2).weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.orange)
                }
                rowChevron
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MattePressStyle())
    }

    // MARK: - Generic flat row

    private func flatRow<Dest: View>(
        icon: String,
        title: String,
        @ViewBuilder destination: () -> Dest
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                rowIcon(icon)
                rowTitle(title)
                Spacer()
                rowChevron
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(MattePressStyle())
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.geist(size: 15))
            .foregroundStyle(theme.adaptiveSecondaryText)
            .frame(width: 24)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(.geist(.subheadline))
            .foregroundStyle(theme.adaptivePrimaryText)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.geist(size: 12, weight: .semibold))
            .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor.opacity(0.5))
            .frame(height: 0.5)
            .padding(.leading, 36)
    }

    // MARK: - Account row

    @ViewBuilder
    private var accountRow: some View {
        if authService.hasAppleAccount, let user = authService.currentUser {
            Button { showProfileEditor = true } label: {
                HStack(spacing: 12) {
                    accountAvatar(user: user)
                    Text(user.displayName)
                        .font(.geist(.subheadline).weight(.semibold))
                        .foregroundStyle(theme.adaptivePrimaryText)
                    Spacer()
                    rowChevron
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(MattePressStyle())
        } else {
            Button { showLogin = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.geist(size: 16))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .frame(width: 24)
                    Text(String(localized: "Sign in with Apple"))
                        .font(.geist(.subheadline).weight(.medium))
                        .foregroundStyle(theme.adaptivePrimaryText)
                    Spacer()
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 4)
                .overlay {
                    Rectangle()
                        .stroke(
                            theme.adaptivePrimaryText.opacity(0.45),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MattePressStyle())
        }
    }

    // MARK: - Footer

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                .font(.geist(.caption))
                .italic()
                .foregroundStyle(theme.adaptiveMutedText)
            Text("v\(appVersion) (\(buildNumber))")
                .font(.geist(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Shield Diagnostics (DEBUG only)

    #if DEBUG
    @State private var diagCopied = false
    @State private var budgetsReset = false
    @State private var colorsRestored = false
    @State private var healthReset = false
    @State private var showOnboardingDemo = false
    @State private var replayOnboardingLive = false
    @State private var debugFeatureTip: FeatureTip?
    @State private var featureTipsReset = false
    @Environment(CoachMarkManager.self) private var coachMarkManager

    @State private var shieldActionLogs: [String] = []
    @State private var showShieldActionLogs = false

    @ViewBuilder
    private var shieldDiagnosticsRows: some View {
        Button {
            let text = model.blockingStore.dumpShieldDiagnostics()
            UIPasteboard.general.string = text
            diagCopied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                diagCopied = false
            }
        } label: {
            diagButton(
                icon: "shield.lefthalf.filled",
                text: diagCopied ? "Copied to clipboard!" : "Copy Shield Diagnostics",
                highlight: diagCopied,
                trailing: "doc.on.clipboard"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            let defaults = UserDefaults(suiteName: SharedKeys.appGroupId)
            shieldActionLogs = defaults?.stringArray(forKey: SharedKeys.shieldActionLogs) ?? ["(no logs yet)"]
            showShieldActionLogs = true
        } label: {
            diagButton(
                icon: "bell.badge",
                text: "View ShieldAction Logs",
                trailing: "list.bullet.rectangle"
            )
        }
        .buttonStyle(MattePressStyle())
        .sheet(isPresented: $showShieldActionLogs) {
            NavigationStack {
                List(shieldActionLogs, id: \.self) { log in
                    Text(log).font(.geist(.caption2)).textSelection(.enabled)
                }
                .navigationTitle("ShieldAction Logs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Copy All") {
                            UIPasteboard.general.string = shieldActionLogs.joined(separator: "\n")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear") {
                            UserDefaults(suiteName: SharedKeys.appGroupId)?.removeObject(forKey: SharedKeys.shieldActionLogs)
                            shieldActionLogs = ["(cleared)"]
                        }
                    }
                }
            }
        }

        rowDivider

        Button {
            let defaults = UserDefaults.stepsTrader()
            for group in model.blockingStore.ticketGroups {
                defaults.removeObject(forKey: SharedKeys.usageBudgetKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(group.id))
            }
            #if canImport(DeviceActivity)
            let center = DeviceActivityCenter()
            let budgetActivities = center.activities.filter { $0.rawValue.hasPrefix("usageBudget_") }
            center.stopMonitoring(budgetActivities)
            #endif
            model.rebuildFamilyControlsShield()
            budgetsReset = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                budgetsReset = false
            }
        } label: {
            diagButton(
                icon: "clock.arrow.circlepath",
                text: budgetsReset ? "All budgets cleared!" : "Reset All Usage Budgets",
                highlight: budgetsReset,
                trailing: "trash"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            model.spentStepsToday = 0
            model.persistDailyEnergyState()
            model.recalculateDailyEnergy()
            colorsRestored = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                colorsRestored = false
            }
        } label: {
            diagButton(
                icon: "paintpalette",
                text: colorsRestored ? "Colors restored!" : "Restore Colors to Max",
                highlight: colorsRestored,
                trailing: "arrow.counterclockwise"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            Task {
                await model.debugForceHealthReset()
                healthReset = true
                try? await Task.sleep(for: .seconds(2))
                healthReset = false
            }
        } label: {
            diagButton(
                icon: "heart.text.clipboard",
                text: healthReset ? "Health data refreshed!" : "Force Health Reset (New Day)",
                highlight: healthReset,
                trailing: "arrow.clockwise"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            showOnboardingDemo = true
        } label: {
            diagButton(
                icon: "play.rectangle",
                text: "Preview Onboarding (Demo)",
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            replayOnboardingLive = true
        } label: {
            diagButton(
                icon: "arrow.counterclockwise.circle",
                text: "Replay Onboarding (Live)",
                trailing: "restart"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            coachMarkManager.start()
        } label: {
            diagButton(
                icon: "hand.point.up.left",
                text: "Preview Coach Marks",
                trailing: "questionmark.circle"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            debugFeatureTip = .widgets
        } label: {
            diagButton(
                icon: "square.stack.3d.up",
                text: "Preview Widget Tip",
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            debugFeatureTip = .wallpaper
        } label: {
            diagButton(
                icon: "photo.on.rectangle.angled",
                text: "Preview Wallpaper Tip",
                trailing: "eye"
            )
        }
        .buttonStyle(MattePressStyle())

        rowDivider

        Button {
            FeatureTip.resetAllSeenFlags()
            featureTipsReset = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                featureTipsReset = false
            }
        } label: {
            diagButton(
                icon: "arrow.counterclockwise",
                text: featureTipsReset ? "Feature tip flags cleared!" : "Reset Feature Tip Flags",
                highlight: featureTipsReset,
                trailing: "trash"
            )
        }
        .buttonStyle(MattePressStyle())
        .sheet(item: $debugFeatureTip) { tip in
            FeatureTipSheet(tip: tip)
        }
    }

    private func diagButton(icon: String, text: String, highlight: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Text(text)
                .font(.geist(.subheadline))
                .foregroundStyle(highlight ? .green : theme.adaptivePrimaryText)
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.geist(.caption2))
                    .foregroundStyle(theme.adaptiveMutedText.opacity(0.7))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    #endif

    // MARK: - Avatar

    @ViewBuilder
    private func accountAvatar(user: AppUser) -> some View {
        if let data = user.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(theme.adaptivePrimaryText.opacity(0.08))
                    .frame(width: 40, height: 40)
                Text(String(user.displayName.prefix(2)).uppercased())
                    .font(.geist(.caption).weight(.bold))
                    .foregroundStyle(theme.adaptivePrimaryText)
            }
        }
    }
}

#Preview {
    SettingsSheet(model: DIContainer.shared.makeAppModel(), embeddedInTab: true)
}

// `MattePressStyle` lives in `Settings/SettingsComponents.swift` so it can be
// shared by every settings detail page.
