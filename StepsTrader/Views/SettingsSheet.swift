import SwiftUI
import WidgetKit
#if canImport(DeviceActivity)
import DeviceActivity
#endif

// MARK: - Settings Sheet (minimal hub -> glass detail pages)
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    var embeddedInTab: Bool = false

    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @State private var showLogin = false
    @State private var showProfileEditor = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(String(localized: "Settings", comment: "Settings page title"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .padding(.top, 8)

                        accountRow

                        VStack(spacing: 0) {
                            permissionsRow
                            rowDivider
                            settingsRow(icon: "paintpalette", title: String(localized: "Appearance")) {
                                SettingsAppearancePage(model: model)
                            }
                            rowDivider
                            settingsRow(icon: "bell", title: String(localized: "Notifications")) {
                                NotificationSettingsView(model: model)
                            }
                            rowDivider
                            settingsRow(icon: "bolt", title: String(localized: "Limits")) {
                                SettingsEnergyPage(model: model)
                            }
                            rowDivider
                            settingsRow(icon: "photo.on.rectangle.angled", title: String(localized: "Wallpaper")) {
                                SettingsShortcutPage(model: model)
                            }
                            rowDivider
                            settingsRow(icon: "square.stack.3d.up", title: String(localized: "Widget")) {
                                SettingsWidgetPage(model: model)
                            }
                        }
                        .glassCard()

                        VStack(spacing: 0) {
                            settingsRow(icon: "info.circle", title: String(localized: "About", comment: "Settings row label")) {
                                SettingsAboutPage(model: model)
                            }
                        }
                        .glassCard()

                        #if DEBUG
                        shieldDiagnosticsRow
                        #endif

                        VStack(spacing: 4) {
                            Text(String(localized: "You are not nowhere. You are now here.", comment: "App philosophy tagline"))
                                .font(.caption)
                                .foregroundColor(theme.adaptiveMutedText)
                            Text("v\(appVersion) (\(buildNumber))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.adaptiveMutedText.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
            }
            .energyGradientBackground(model: model)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: embeddedInTab ? topCardHeight : 0)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
        }
    }

    // MARK: - Permissions row

    private var permissionsRow: some View {
        NavigationLink {
            SettingsPermissionsPage(model: model)
        } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.adaptiveSecondaryText)
                        .frame(width: 24)
                    if model.hasPermissionIssues {
                        Circle()
                            .fill(.orange)
                            .frame(width: 8, height: 8)
                            .offset(x: 3, y: -3)
                    }
                }
                Text(String(localized: "Permissions", comment: "Settings row label"))
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptivePrimaryText)
                Spacer()
                if model.hasPermissionIssues {
                    Text("!")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.orange))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveMutedText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation row

    private func settingsRow<Dest: View>(icon: String, title: String, @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptivePrimaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveMutedText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor)
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    // MARK: - Account row

    @ViewBuilder
    private var accountRow: some View {
        if authService.isAuthenticated, let user = authService.currentUser {
            Button { showProfileEditor = true } label: {
                HStack(spacing: 12) {
                    accountAvatar(user: user)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.adaptivePrimaryText)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(theme.adaptiveSecondaryText)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.adaptiveMutedText)
                }
                .padding(14)
                .glassCard()
            }
            .buttonStyle(.plain)
        } else {
            Button { showLogin = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .frame(width: 24)
                    Text(String(localized: "Sign in with Apple"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.adaptivePrimaryText)
                    Spacer()
                }
                .padding(14)
                .glassCard()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shield Diagnostics (DEBUG only)

    #if DEBUG
    @State private var diagCopied = false
    @State private var budgetsReset = false
    @State private var colorsRestored = false

    @State private var shieldActionLogs: [String] = []
    @State private var showShieldActionLogs = false

    private var shieldDiagnosticsRow: some View {
        VStack(spacing: 0) {
                Button {
                    let text = model.blockingStore.dumpShieldDiagnostics()
                    UIPasteboard.general.string = text
                    diagCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagCopied = false }
                } label: {
                    diagButton(
                        icon: "shield.lefthalf.filled",
                        text: diagCopied ? "Copied to clipboard!" : "Copy Shield Diagnostics",
                        color: .orange,
                        highlight: diagCopied,
                        trailing: "doc.on.clipboard"
                    )
                }
                .buttonStyle(.plain)

                diagDivider

                Button {
                    let defaults = UserDefaults(suiteName: SharedKeys.appGroupId)
                    shieldActionLogs = defaults?.stringArray(forKey: SharedKeys.shieldActionLogs) ?? ["(no logs yet)"]
                    showShieldActionLogs = true
                } label: {
                    diagButton(
                        icon: "bell.badge",
                        text: "View ShieldAction Logs",
                        color: .blue,
                        trailing: "list.bullet.rectangle"
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showShieldActionLogs) {
                    NavigationStack {
                        List(shieldActionLogs, id: \.self) { log in
                            Text(log).font(.caption2).textSelection(.enabled)
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

                diagDivider

                Button {
                    let defaults = UserDefaults.stepsTrader()
                    for group in model.blockingStore.ticketGroups {
                        defaults.removeObject(forKey: SharedKeys.usageBudgetKey(group.id))
                        defaults.removeObject(forKey: SharedKeys.usageBudgetStartedKey(group.id))
                        defaults.removeObject(forKey: SharedKeys.usageBudgetInitialKey(group.id))
                    }
                    #if canImport(DeviceActivity)
                    let center = DeviceActivityCenter()
                    let budgetActivities = center.activities.filter { $0.rawValue.hasPrefix("usageBudget_") }
                    center.stopMonitoring(budgetActivities)
                    #endif
                    model.rebuildFamilyControlsShield()
                    budgetsReset = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { budgetsReset = false }
                } label: {
                    diagButton(
                        icon: "clock.arrow.circlepath",
                        text: budgetsReset ? "All budgets cleared!" : "Reset All Usage Budgets",
                        color: .red,
                        highlight: budgetsReset,
                        trailing: "trash"
                    )
                }
                .buttonStyle(.plain)

                diagDivider

                Button {
                    model.spentStepsToday = 0
                    model.stepsBalance = model.baseEnergyToday
                    model.recalculateDailyEnergy()
                    colorsRestored = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { colorsRestored = false }
                } label: {
                    diagButton(
                        icon: "paintpalette",
                        text: colorsRestored ? "Colors restored!" : "Restore Colors to Max",
                        color: .yellow,
                        highlight: colorsRestored,
                        trailing: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.plain)
            }
            .glassCard()
    }

    private var diagDivider: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor)
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    private func diagButton(icon: String, text: String, color: Color, highlight: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(highlight ? .green : theme.adaptivePrimaryText)

            Spacer()

            if let trailing {
                Image(systemName: trailing)
                    .font(.caption2)
                    .foregroundColor(theme.adaptiveMutedText)
            }
        }
        .padding(.horizontal, 14)
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.adaptivePrimaryText)
            }
        }
    }
}
