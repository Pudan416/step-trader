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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader())
    private var stepsTarget = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader())
    private var sleepTarget = EnergyDefaults.sleepTargetHours
    @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader())
    private var dayEndHour = 0
    @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader())
    private var dayEndMinute = 0
    @State private var showLogin = false
    /// Fallback route storage when no external binding is supplied (preview /
    /// standalone usage). The tab instance uses `featureTipRouteBinding` instead.
    @State private var localFeatureTipRoute: FeatureTipSettingsPage?

    private let horizontalContentPadding: CGFloat = 20

    private var featureTipRoute: Binding<FeatureTipSettingsPage?> {
        featureTipRouteBinding ?? $localFeatureTipRoute
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var yourDaySummary: SettingsYourDaySummary {
        SettingsYourDaySummary(
            stepsTarget: stepsTarget,
            sleepTargetHours: sleepTarget,
            dayEndHour: dayEndHour,
            dayEndMinute: dayEndMinute
        )
    }

    private func gridColumns(availableContentWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: SettingsGridLayout.minimumCardWidth),
                spacing: SettingsGridLayout.spacing,
                alignment: .top
            ),
            count: SettingsGridLayout.columnCount(
                for: dynamicTypeSize,
                availableWidth: availableContentWidth
            )
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { container in
                let availableContentWidth = max(
                    0,
                    container.size.width - horizontalContentPadding * 2
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(String(localized: "Settings", comment: "Settings page title"))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .padding(.top, 8)

                        VStack(spacing: 16) {
                            accountCard

                            NavigationLink {
                                SettingsEnergyPage(model: model)
                            } label: {
                                SettingsYourDayCardLabel(summary: yourDaySummary)
                            }
                            .buttonStyle(MattePressStyle())
                            .accessibilityIdentifier("settings.yourDay")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionLabel(
                                text: String(localized: "App settings", comment: "Settings destination group title")
                            )
                            .accessibilityIdentifier("settings.appSettings.section")

                            LazyVGrid(
                                columns: gridColumns(availableContentWidth: availableContentWidth),
                                spacing: SettingsGridLayout.spacing
                            ) {
                                NavigationLink {
                                    SettingsAppearancePage(model: model)
                                } label: {
                                    SettingsDestinationCardLabel(
                                        icon: "paintpalette",
                                        title: String(localized: "Appearance", comment: "Settings destination title")
                                    )
                                }
                                .buttonStyle(MattePressStyle())
                                .accessibilityIdentifier("settings.destination.appearance")

                                NavigationLink {
                                    NotificationSettingsView(model: model)
                                } label: {
                                    SettingsDestinationCardLabel(
                                        icon: "bell",
                                        title: String(localized: "Notifications", comment: "Settings destination title")
                                    )
                                }
                                .buttonStyle(MattePressStyle())
                                .accessibilityIdentifier("settings.destination.notifications")

                                NavigationLink {
                                    SettingsPermissionsPage(model: model)
                                } label: {
                                    SettingsDestinationCardLabel(
                                        icon: "lock.shield",
                                        title: String(localized: "Permissions", comment: "Settings destination title"),
                                        warningText: model.hasPermissionIssues
                                            ? String(localized: "Action needed", comment: "Permissions warning label")
                                            : nil
                                    )
                                }
                                .buttonStyle(MattePressStyle())
                                .accessibilityIdentifier("settings.destination.permissions")

                                NavigationLink {
                                    SettingsWidgetsWallpaperPage(model: model)
                                } label: {
                                    SettingsDestinationCardLabel(
                                        icon: "square.stack.3d.up",
                                        title: String(localized: "Widgets & wallpaper", comment: "Settings destination title")
                                    )
                                }
                                .buttonStyle(MattePressStyle())
                                .accessibilityIdentifier("settings.destination.widgetsWallpaper")
                            }
                        }

                        SettingsInformationGroup {
                            NavigationLink {
                                ManualsPage(model: model)
                            } label: {
                                SettingsNavRow(
                                    icon: "book",
                                    title: String(localized: "Notes from Kosta", comment: "Settings destination title")
                                )
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(MattePressStyle())
                            .accessibilityIdentifier("settings.destination.notes")

                            DetailDivider(inset: 50)

                            NavigationLink {
                                SettingsAboutPage(model: model)
                            } label: {
                                SettingsNavRow(
                                    icon: "info.circle",
                                    title: String(localized: "About", comment: "Settings destination title")
                                )
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(MattePressStyle())
                            .accessibilityIdentifier("settings.destination.about")
                        }

                        #if DEBUG
                        NavigationLink {
                            SettingsDeveloperPage(model: model)
                        } label: {
                            SettingsNavRow(
                                icon: "hammer",
                                title: String(localized: "Developer", comment: "Settings developer destination")
                            )
                            .frame(minHeight: 44)
                            .settingsCardSurface()
                        }
                        .buttonStyle(MattePressStyle())
                        .accessibilityIdentifier("settings.destination.developer")
                        #endif

                        versionFooter
                    }
                    .padding(.horizontal, horizontalContentPadding)
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
    }

    // MARK: - Account card

    @ViewBuilder
    private var accountCard: some View {
        if authService.hasAppleAccount, let user = authService.currentUser {
            NavigationLink {
                SettingsAccountPage(authService: authService, model: model)
            } label: {
                SettingsAccountCardLabel(
                    presentation: .signedIn(
                        displayName: user.displayName,
                        initials: SettingsAccountPresentation.initials(for: user.displayName),
                        avatarData: user.avatarData
                    )
                )
            }
            .buttonStyle(MattePressStyle())
            .accessibilityIdentifier("settings.account")
        } else {
            Button { showLogin = true } label: {
                SettingsAccountCardLabel(presentation: .signedOut)
            }
            .buttonStyle(MattePressStyle())
            .accessibilityIdentifier("settings.account")
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
}

#Preview {
    SettingsSheet(model: DIContainer.shared.makeAppModel(), embeddedInTab: true)
}

// `MattePressStyle` lives in `Settings/SettingsComponents.swift` so it can be
// shared by every settings detail page.
