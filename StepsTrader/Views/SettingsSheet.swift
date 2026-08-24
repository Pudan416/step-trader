import SwiftUI

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
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .padding(.top, 8)

                    accountRow

                    section(header: String(localized: "General", comment: "Settings section header")) {
                        flatRow(icon: "figure.walk", title: String(localized: "Your day")) {
                            SettingsEnergyPage(model: model)
                        }
                        .accessibilityIdentifier("settings.yourDay")
                        rowDivider
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
                        flatRow(
                            icon: "square.stack.3d.up",
                            title: String(localized: "Widgets & wallpaper", comment: "Settings row and combined page title")
                        ) {
                            SettingsWidgetsWallpaperPage(model: model)
                        }
                        .accessibilityIdentifier("settings.destination.widgetsWallpaper")
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
                    section(header: String(localized: "Developer", comment: "Settings section header")) {
                        flatRow(
                            icon: "hammer",
                            title: String(localized: "Developer", comment: "Settings developer destination")
                        ) {
                            SettingsDeveloperPage(model: model)
                        }
                        .accessibilityIdentifier("settings.destination.developer")
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
                .font(.caption2.weight(.semibold))
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
                        .font(.caption2.weight(.semibold))
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
            .font(.system(size: 15))
            .foregroundStyle(theme.adaptiveSecondaryText)
            .frame(width: 24)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(theme.adaptivePrimaryText)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
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
            NavigationLink {
                SettingsAccountPage(authService: authService, model: model)
            } label: {
                HStack(spacing: 12) {
                    accountAvatar(user: user)
                    Text(user.displayName)
                        .font(.subheadline.weight(.semibold))
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
                        .font(.system(size: 16))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .frame(width: 24)
                    Text(String(localized: "Sign in with Apple"))
                        .font(.subheadline.weight(.medium))
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
                .font(.caption)
                .italic()
                .foregroundStyle(theme.adaptiveMutedText)
            Text("v\(appVersion) (\(buildNumber))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.adaptiveMutedText.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

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

#Preview {
    SettingsSheet(model: DIContainer.shared.makeAppModel(), embeddedInTab: true)
}

// `MattePressStyle` lives in `Settings/SettingsComponents.swift` so it can be
// shared by every settings detail page.
