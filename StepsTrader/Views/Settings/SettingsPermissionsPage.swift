import SwiftUI
import HealthKit
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

struct SettingsPermissionsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @State private var healthAuthorizationError: String?

    private var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    private var usesSuccessfulZeroHealthFixture: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("ui-testing")
            && arguments.contains("ui-testing-health-zero-success")
        #else
        false
        #endif
    }

    private var usesDeniedNotificationsFixture: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("ui-testing")
            && arguments.contains("ui-testing-notifications-denied")
        #else
        false
        #endif
    }

    private var healthPresentation: SettingsPermissionPresentation {
        SettingsPermissionPresentation.health(
            isAvailable: isHealthKitAvailable,
            hasReturnedData: usesSuccessfulZeroHealthFixture
                || model.hasStepsData
                || model.hasSleepData
        )
    }

    private var screenTimePresentation: SettingsPermissionPresentation {
        SettingsPermissionPresentation.screenTime(
            isAuthorized: model.blockingStore.isAuthorized
        )
    }

    private var notificationPresentation: SettingsPermissionPresentation {
        SettingsPermissionPresentation.notifications(
            status: usesDeniedNotificationsFixture
                ? .denied
                : model.notificationAuthorizationStatus
        )
    }

    private var missingPermissionCount: Int {
        [healthPresentation, screenTimePresentation, notificationPresentation]
            .filter(\.contributesToWarning)
            .count
    }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if missingPermissionCount > 0 {
                        statusBanner
                            .padding(.horizontal, 16)
                    }

                    SettingsGroupedSurface {
                        permissionRow(
                            icon: "heart.fill",
                            title: String(localized: "Health", comment: "Permission row – HealthKit"),
                            subtitle: String(localized: "Steps, sleep, workouts", comment: "Permission row – HealthKit detail"),
                            presentation: healthPresentation,
                            actionTitle: String(localized: "Check access", comment: "Health permission action"),
                            onFix: requestHealthAuthorization
                        )

                        if let healthAuthorizationError {
                            DetailDivider()
                            healthErrorRow(message: healthAuthorizationError)
                        }

                        DetailDivider()

                        permissionRow(
                            icon: "hourglass",
                            title: String(localized: "Screen Time", comment: "Permission row – Family Controls"),
                            subtitle: String(localized: "App blocking & limits", comment: "Permission row – Family Controls detail"),
                            presentation: screenTimePresentation,
                            actionTitle: String(localized: "Allow access", comment: "Screen Time permission action"),
                            onFix: {
                                Task {
                                    do {
                                        try await model.blockingStore.requestAuthorization()
                                    } catch {
                                        openAppSettings()
                                    }
                                }
                            }
                        )

                        DetailDivider()

                        permissionRow(
                            icon: "bell.fill",
                            title: String(localized: "Notifications", comment: "Permission row – Notifications"),
                            subtitle: String(localized: "Timers, reminders, alerts", comment: "Permission row – Notifications detail"),
                            presentation: notificationPresentation,
                            actionTitle: notificationActionTitle,
                            onFix: handleNotificationAction
                        )
                    }
                    .padding(.horizontal, 16)

                    SettingsFooter(text: String(localized: "If a permission was denied, tap it to open Settings where you can enable it.", comment: "Permissions – footer hint"))
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Permissions", comment: "Permissions page title"))
        .task {
            seedSuccessfulZeroHealthFixtureIfNeeded()
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.geist(.title3))
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Some permissions are missing", comment: "Permissions – missing banner title"))
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(String(localized: "\(missingPermissionCount) of 3 not granted", comment: "Permissions – missing count"))
                    .font(.geist(.caption))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Permission row

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        presentation: SettingsPermissionPresentation,
        actionTitle: String?,
        onFix: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.geist(size: 15))
                .foregroundStyle(permissionColor(for: presentation))
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.geist(.subheadline))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(subtitle)
                    .font(.geist(.caption))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(statusText(for: presentation.status))
                    .font(.geist(.caption).weight(.semibold))
                    .foregroundStyle(permissionColor(for: presentation))
                    .multilineTextAlignment(.trailing)

                if presentation.action != nil, let actionTitle {
                    Button(actionTitle, action: onFix)
                        .font(.geist(.caption).weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - Helpers

    private func refreshNotificationStatus() async {
        if usesDeniedNotificationsFixture {
            model.notificationAuthorizationStatus = .denied
            return
        }
        await model.refreshNotificationAuthorizationStatus()
    }

    private func seedSuccessfulZeroHealthFixtureIfNeeded() {
        guard usesSuccessfulZeroHealthFixture else { return }
        model.healthStore.stepsToday = 0
        model.healthStore.hasStepsData = true
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var notificationActionTitle: String? {
        switch notificationPresentation.action {
        case .requestPermission:
            String(localized: "Allow notifications", comment: "Notification permission action")
        case .openSystemSettings:
            String(localized: "Open Settings", comment: "Permission recovery action")
        case .checkAccess:
            String(localized: "Check access", comment: "Permission check action")
        case nil:
            nil
        }
    }

    private func statusText(for status: SettingsPermissionStatus) -> String {
        switch status {
        case .connected:
            String(localized: "Connected", comment: "Permission status")
        case .checkAccess:
            String(localized: "Check access", comment: "Permission status")
        case .unavailable:
            String(localized: "N/A", comment: "Permission – not available badge")
        case .allowed:
            String(localized: "Allowed", comment: "Notification permission status")
        case .notRequested:
            String(localized: "Not requested", comment: "Notification permission status")
        case .offInSystemSettings:
            String(localized: "Off in System Settings", comment: "Notification permission status")
        case .actionNeeded:
            String(localized: "Action needed", comment: "Permission status")
        }
    }

    private func permissionColor(
        for presentation: SettingsPermissionPresentation
    ) -> Color {
        switch presentation.status {
        case .connected, .allowed:
            .green
        case .unavailable, .checkAccess:
            theme.adaptiveMutedText
        case .notRequested, .offInSystemSettings, .actionNeeded:
            .orange
        }
    }

    private func requestHealthAuthorization() {
        Task {
            healthAuthorizationError = nil
            do {
                try await model.healthStore.requestAuthorization()
                await model.refreshStepsIfAuthorized()
                await model.refreshSleepIfAuthorized()
            } catch {
                AppLogger.healthKit.error(
                    "Permission page auth failed: \(error.localizedDescription)"
                )
                healthAuthorizationError = error.localizedDescription
            }
        }
    }

    private func handleNotificationAction() {
        switch notificationPresentation.action {
        case .requestPermission:
            Task { await model.requestNotificationPermission() }
        case .openSystemSettings, .checkAccess:
            openAppSettings()
        case nil:
            break
        }
    }

    private func healthErrorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Health access couldn't be checked", comment: "Health permission error title"))
                .font(.geist(.subheadline).weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
            Text(message)
                .font(.geist(.caption))
                .foregroundStyle(theme.adaptiveSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(String(localized: "Try Again", comment: "Health permission retry action")) {
                    requestHealthAuthorization()
                }
                Button(String(localized: "Open Settings", comment: "Permission recovery action")) {
                    openAppSettings()
                }
            }
            .font(.geist(.caption).weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier("settings.permissions.health.error")
    }

}

#Preview {
    NavigationStack {
        SettingsPermissionsPage(model: DIContainer.shared.makeAppModel())
    }
}
