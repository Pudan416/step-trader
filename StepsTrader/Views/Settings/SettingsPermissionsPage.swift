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

    @State private var permissionFailure: SettingsPermissionFailurePresentation?

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

                        if let failure = permissionFailure(for: .health) {
                            DetailDivider()
                            permissionFailureRow(failure)
                        }

                        DetailDivider()

                        permissionRow(
                            icon: "hourglass",
                            title: String(localized: "Screen Time", comment: "Permission row – Family Controls"),
                            subtitle: String(localized: "App blocking & limits", comment: "Permission row – Family Controls detail"),
                            presentation: screenTimePresentation,
                            actionTitle: String(localized: "Allow access", comment: "Screen Time permission action"),
                            onFix: requestScreenTimeAuthorization
                        )

                        if let failure = permissionFailure(for: .screenTime) {
                            DetailDivider()
                            permissionFailureRow(failure)
                        }

                        DetailDivider()

                        permissionRow(
                            icon: "bell.fill",
                            title: String(localized: "Notifications", comment: "Permission row – Notifications"),
                            subtitle: String(localized: "Timers, reminders, alerts", comment: "Permission row – Notifications detail"),
                            presentation: notificationPresentation,
                            actionTitle: notificationActionTitle,
                            onFix: handleNotificationAction
                        )

                        if let failure = permissionFailure(for: .notifications) {
                            DetailDivider()
                            permissionFailureRow(failure)
                        }
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
                Text(presentation.status.displayText)
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
            clearPermissionFailure(for: .health)
            do {
                try await model.healthStore.requestAuthorization()
                await model.refreshStepsIfAuthorized()
                await model.refreshSleepIfAuthorized()
            } catch {
                AppLogger.healthKit.error(
                    "Permission page auth failed: \(error.localizedDescription)"
                )
                permissionFailure = .health
            }
        }
    }

    private func requestScreenTimeAuthorization() {
        Task {
            clearPermissionFailure(for: .screenTime)
            do {
                try await model.blockingStore.requestAuthorization()
            } catch {
                AppLogger.familyControls.error(
                    "Permission page authorization failed: \(error.localizedDescription)"
                )
                permissionFailure = .screenTime
            }
        }
    }

    private func handleNotificationAction() {
        switch notificationPresentation.action {
        case .requestPermission:
            requestNotificationAuthorization()
        case .openSystemSettings, .checkAccess:
            openAppSettings()
        case nil:
            break
        }
    }

    private func permissionFailure(
        for permission: SettingsPermissionKind
    ) -> SettingsPermissionFailurePresentation? {
        guard permissionFailure?.permission == permission else { return nil }
        return permissionFailure
    }

    private func clearPermissionFailure(for permission: SettingsPermissionKind) {
        guard permissionFailure?.permission == permission else { return }
        permissionFailure = nil
    }

    private func retry(_ permission: SettingsPermissionKind) {
        switch permission {
        case .health:
            requestHealthAuthorization()
        case .notifications:
            requestNotificationAuthorization()
        case .screenTime:
            requestScreenTimeAuthorization()
        }
    }

    private func permissionFailureRow(
        _ failure: SettingsPermissionFailurePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(failure.message)
                .font(.geist(.subheadline).weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if failure.actions.contains(.tryAgain) {
                    Button(String(localized: "Try Again", comment: "Permission retry action")) {
                        retry(failure.permission)
                    }
                }
                if failure.actions.contains(.openSettings) {
                    Button(String(localized: "Open Settings", comment: "Permission recovery action")) {
                        openAppSettings()
                    }
                }
            }
            .font(.geist(.caption).weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityIdentifier(permissionFailureIdentifier(for: failure.permission))
    }

    private func requestNotificationAuthorization() {
        Task {
            clearPermissionFailure(for: .notifications)
            do {
                try await model.requestNotificationPermission()
            } catch {
                permissionFailure = .notifications
            }
        }
    }

    private func permissionFailureIdentifier(
        for permission: SettingsPermissionKind
    ) -> String {
        switch permission {
        case .health: "settings.permissions.health.error"
        case .notifications: "settings.permissions.notifications.error"
        case .screenTime: "settings.permissions.screenTime.error"
        }
    }

}

#Preview {
    NavigationStack {
        SettingsPermissionsPage(model: DIContainer.shared.makeAppModel())
    }
}
