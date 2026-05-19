import SwiftUI
import HealthKit
import UserNotifications
#if canImport(FamilyControls)
import FamilyControls
#endif

struct SettingsPermissionsPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// HealthKit hides read-permission status — `hasStepsData` becomes `true` even
    /// when the user denied read access (fetch returns 0, no error). Use actual
    /// non-zero data as the verification signal for the permissions badge.
    private var healthVerified: Bool {
        model.stepsToday > 0 || model.dailySleepHours > 0
    }

    private var hasHealthData: Bool {
        model.hasStepsData || model.hasSleepData
    }

    private var isFamilyControlsAuthorized: Bool {
        model.blockingStore.isAuthorized
    }

    private var isNotificationsGranted: Bool {
        notificationStatus == .authorized
    }

    private var missingPermissionCount: Int {
        var count = 0
        if !healthVerified { count += 1 }
        if !isFamilyControlsAuthorized { count += 1 }
        if !isNotificationsGranted { count += 1 }
        return count
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: String(localized: "Permissions", comment: "Permissions page title"))
                        .padding(.horizontal, 16)

                    if missingPermissionCount > 0 {
                        statusBanner
                            .padding(.horizontal, 16)
                    }

                    VStack(spacing: 0) {
                        permissionRow(
                            icon: "heart.fill",
                            title: String(localized: "Health", comment: "Permission row – HealthKit"),
                            subtitle: String(localized: "Steps, sleep, workouts", comment: "Permission row – HealthKit detail"),
                            isGranted: healthVerified,
                            isAvailable: isHealthKitAvailable,
                            alwaysTappable: true,
                            onFix: {
                                Task {
                                    do {
                                        try await model.healthStore.requestAuthorization()
                                        await model.refreshStepsIfAuthorized()
                                    } catch {
                                        AppLogger.healthKit.error("Permission page auth failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                        )

                        DetailDivider()

                        permissionRow(
                            icon: "hourglass",
                            title: String(localized: "Screen Time", comment: "Permission row – Family Controls"),
                            subtitle: String(localized: "App blocking & limits", comment: "Permission row – Family Controls detail"),
                            isGranted: isFamilyControlsAuthorized,
                            isAvailable: true,
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
                            isGranted: isNotificationsGranted,
                            isAvailable: true,
                            onFix: {
                                Task {
                                    let center = UNUserNotificationCenter.current()
                                    let settings = await center.notificationSettings()
                                    if settings.authorizationStatus == .denied {
                                        openAppSettings()
                                    } else {
                                        await model.requestNotificationPermission()
                                        await refreshNotificationStatus()
                                    }
                                }
                            }
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
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
        .task {
            await refreshNotificationStatus()
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Some permissions are missing", comment: "Permissions – missing banner title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(String(localized: "\(missingPermissionCount) of 3 not granted", comment: "Permissions – missing count"))
                    .font(.caption)
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
        isGranted: Bool,
        isAvailable: Bool,
        alwaysTappable: Bool = false,
        onFix: @escaping () -> Void
    ) -> some View {
        Button(action: {
            onFix()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isGranted ? .green : .orange)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(theme.adaptivePrimaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.adaptiveSecondaryText)
                }

                Spacer()

                if !isAvailable {
                    Text(String(localized: "N/A", comment: "Permission – not available badge"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.adaptiveMutedText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.adaptiveMutedText.opacity(0.12)))
                } else if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 18))
                } else {
                    Text(String(localized: "Enable", comment: "Permission – enable button"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.orange))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(MattePressStyle())
        .disabled(!isAvailable || (!alwaysTappable && isGranted))
    }

    // MARK: - Helpers

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            notificationStatus = settings.authorizationStatus
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

}

#Preview {
    NavigationStack {
        SettingsPermissionsPage(model: DIContainer.shared.makeAppModel())
    }
}
