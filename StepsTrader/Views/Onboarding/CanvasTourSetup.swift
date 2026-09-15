import SwiftUI
import HealthKit

/// The tour's optional setup sheet reuses the product settings and services.
/// The presenter sends `.setupCompleted` on `onContinue`, then dismisses this
/// sheet. The coordinator waits for the presenter's actual sheet dismissal.
struct CanvasTourSetup: View {
    @ObservedObject var model: AppModel
    var openAccountOnAppear = false
    var onContinue: () -> Void

    @ObservedObject private var authService = AuthenticationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appTheme) private var theme
    @Environment(\.canvasChromePalette) private var palette
    @State private var showLogin = false
    @State private var openedInitialAccount = false
    @State private var loginSessionID: UUID?
    @State private var showApps = false
    @State private var appsSessionID: UUID?

    private var notifications: SettingsPermissionPresentation {
        .notifications(
            status: model.notificationAuthorizationStatus,
            remindersEnabled: SettingsPermissionPresentation.remindersEnabled(in: .stepsTrader())
        )
    }

    private var healthStatus: String {
        let presentation = SettingsPermissionPresentation.health(
            isAvailable: HKHealthStore.isHealthDataAvailable(),
            // The existing has*Data flags also cover successful empty queries.
            hasReturnedData: model.stepsToday > 0 || model.dailySleepHours > 0
        )
        switch presentation.status {
        case .connected: return String(localized: "Data available")
        case .unavailable: return String(localized: "Unavailable")
        default:
            return model.hasStepsData || model.hasSleepData
                ? String(localized: "Waiting for data")
                : String(localized: "Check access")
        }
    }

    private var hasValidGroup: Bool {
        model.ticketGroups.contains { group in
            group.templateApp == nil
                ? group.selection.hasGroupTargets
                : group.selection.isSingleApplication
        }
    }

    private var appAccessStatus: String {
        if !model.blockingStore.isAuthorized { return String(localized: "Access needed") }
        return hasValidGroup ? String(localized: "Ready") : String(localized: "Choose apps")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SettingsDetailBackground(model: model)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(String(localized: "Everything here is optional."))
                            .font(.geist(.body))
                            .foregroundStyle(palette.surfaceColor)
                            .padding(14)
                            .background(palette.textColor, in: RoundedRectangle(cornerRadius: 18))
                        SettingsGroupedSurface {
                            accountRow
                            DetailDivider()
                            NavigationLink {
                                CanvasTourNotificationsPage(model: model)
                            } label: {
                                SettingsNavRow(icon: "bell.fill", title: String(localized: "Notifications"), value: notifications.status.displayText)
                            }
                            .accessibilityIdentifier("canvas_tour.setup.notifications")
                            DetailDivider()
                            NavigationLink {
                                SettingsPermissionsPage(model: model)
                            } label: {
                                SettingsNavRow(icon: "heart.fill", title: String(localized: "Health"), value: healthStatus)
                            }
                            .accessibilityIdentifier("canvas_tour.setup.health")
                            DetailDivider()
                            NavigationLink {
                                appAccessPage
                            } label: {
                                SettingsNavRow(icon: "hourglass", title: String(localized: "App access"), value: appAccessStatus)
                            }
                            .accessibilityIdentifier("canvas_tour.setup.appAccess")
                        }
                        Button(String(localized: "Continue"), action: onContinue)
                            .font(.geist(.headline))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("canvas_tour.setup.continue")

                    }
                    .padding(20)
                }
            }
            .navigationTitle(String(localized: "Your setup"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let sessionID = CanvasTour.shared.sessionID
                await model.refreshNotificationAuthorizationStatus()
                guard !Task.isCancelled, CanvasTour.shared.isActive,
                      CanvasTour.shared.step == .setup,
                      CanvasTour.shared.sessionID == sessionID else { return }
                if openAccountOnAppear, !openedInitialAccount, !authService.hasAppleAccount {
                    openedInitialAccount = true
                    presentLogin()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refreshNotificationAuthorizationStatus() } }
            }
            .sheet(isPresented: $showLogin, onDismiss: {
                guard CanvasTour.shared.isActive, CanvasTour.shared.step == .setup,
                      CanvasTour.shared.sessionID == loginSessionID else { return }
                CanvasTour.shared.sheetDismissed("setup.login", sessionID: loginSessionID)
                CanvasTour.shared.sheetPresented("setup", returnContext: "setup")
                CanvasTour.shared.report(authService.hasAppleAccount
                    ? "Account: Apple account is present; sync status is separate"
                    : "Account: login dismissed without Apple account")
            }) {
                LoginView(authService: authService)
                    .canvasTourExitChrome(context: "setup.login")
            }
            .sheet(isPresented: $showApps, onDismiss: {
                guard CanvasTour.shared.isActive, CanvasTour.shared.step == .setup,
                      CanvasTour.shared.sessionID == appsSessionID else { return }
                CanvasTour.shared.sheetDismissed("setup.apps", sessionID: appsSessionID)
                CanvasTour.shared.sheetPresented("setup", returnContext: "setup")
            }) {
                VStack(spacing: 0) {
                    HStack {
                        Button(String(localized: "Back to setup")) { showApps = false }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("canvas_tour.setup.apps.back")
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    AppsPageSimplified(model: model)
                }
                .todayCanvasBackground(detail: true)
                .canvasTourExitChrome(context: "setup.apps")
            }
            .onChange(of: CanvasTour.shared.isActive) { _, active in
                if !active { showLogin = false; showApps = false }
            }
            .onChange(of: CanvasTour.shared.sessionID) { _, sessionID in
                if loginSessionID != sessionID { showLogin = false }
                if appsSessionID != sessionID { showApps = false }
            }
        }
        .environment(\.topCardHeight, 0)
        .canvasTourExitChrome(context: "setup")
    }

    @ViewBuilder
    private var accountRow: some View {
        if authService.hasAppleAccount {
            NavigationLink {
                SettingsAccountPage(authService: authService, model: model)
            } label: {
                SettingsNavRow(icon: "person.crop.circle", title: String(localized: "Account"), value: String(localized: "Signed in"))
            }
            .accessibilityIdentifier("canvas_tour.setup.account")
        } else {
            Button(action: presentLogin) {
                SettingsNavRow(icon: "person.crop.circle", title: String(localized: "Account"), value: String(localized: "Sign in"))
            }
            .accessibilityIdentifier("canvas_tour.setup.account")
        }
    }

    private var appAccessPage: some View {
        ZStack {
            SettingsDetailBackground(model: model)
            VStack(spacing: 20) {
                SettingsGroupedSurface {
                    NavigationLink {
                        SettingsPermissionsPage(model: model)
                    } label: {
                        SettingsNavRow(icon: "hourglass", title: String(localized: "Screen Time access"), value: SettingsPermissionPresentation.screenTime(isAuthorized: model.blockingStore.isAuthorized).status.displayText)
                    }
                    DetailDivider()
                    Button {
                        appsSessionID = CanvasTour.shared.sessionID
                        CanvasTour.shared.sheetPresented("setup.apps", returnContext: "setup")
                        showApps = true
                    } label: {
                        SettingsNavRow(icon: "app.badge", title: String(localized: "Choose apps"), value: hasValidGroup ? String(localized: "Apps selected") : String(localized: "Choose apps"))
                    }
                }
                Text(String(localized: "App blocking needs Screen Time access and a saved selection of apps."))
                    .font(.geist(.callout))
                    .foregroundStyle(palette.surfaceColor)
                    .padding(14)
                    .background(palette.textColor, in: RoundedRectangle(cornerRadius: 18))
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(String(localized: "App access"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presentLogin() {
        guard CanvasTour.shared.isActive, CanvasTour.shared.step == .setup else { return }
        loginSessionID = CanvasTour.shared.sessionID
        CanvasTour.shared.sheetPresented("setup.login", returnContext: "setup")
        showLogin = true
    }
}

/// Explanation around the actual notification settings page. Its existing
/// permission action performs the system request and preserves reminder toggles.
private struct CanvasTourNotificationsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.canvasChromePalette) private var palette

    var body: some View {
        NotificationSettingsView(model: model)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Get alerts when app access is ending and the Canvas reminders you choose. You can change them anytime."))
                        .font(.geist(.callout))
                        .foregroundStyle(palette.surfaceColor)
                            .padding(14)
                            .background(palette.textColor, in: RoundedRectangle(cornerRadius: 18))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Not now")) { dismiss() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("canvas_tour.setup.notifications.later")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .todayCanvasBackground(detail: true)
            }
    }
}
