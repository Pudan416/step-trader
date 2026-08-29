import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SharedKeys.notifyOneMinBefore, store: UserDefaults.stepsTrader())
    private var oneMinBefore: Bool = true

    @AppStorage(SharedKeys.notifyWhenTimerOver, store: UserDefaults.stepsTrader())
    private var timerOver: Bool = true

    @AppStorage(SharedKeys.notifyCanvasReminder, store: UserDefaults.stepsTrader())
    private var canvasReminder: Bool = false

    @AppStorage(SharedKeys.canvasReminderHour, store: UserDefaults.stepsTrader())
    private var canvasHour: Int = 21

    @AppStorage(SharedKeys.canvasReminderMinute, store: UserDefaults.stepsTrader())
    private var canvasMinute: Int = 0

    @AppStorage(SharedKeys.notifyDayResetWarning, store: UserDefaults.stepsTrader())
    private var dayResetWarning: Bool = true

    @AppStorage(SharedKeys.dayResetWarningHours, store: UserDefaults.stepsTrader())
    private var dayResetWarningHours: Int = 1

    private var usesDeniedNotificationsFixture: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("ui-testing")
            && arguments.contains("ui-testing-notifications-denied")
        #else
        false
        #endif
    }

    private var notificationPresentation: SettingsPermissionPresentation {
        SettingsPermissionPresentation.notifications(
            status: usesDeniedNotificationsFixture
                ? .denied
                : model.notificationAuthorizationStatus
        )
    }

    private var notificationDeliveryIsUnavailable: Bool {
        notificationPresentation.status != .allowed
    }

    private var canvasTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var comps = DateComponents()
                comps.hour = canvasHour
                comps.minute = canvasMinute
                return Calendar.current.date(from: comps) ?? Date.now
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                canvasHour = comps.hour ?? 21
                canvasMinute = comps.minute ?? 0
                rescheduleCanvas()
            }
        )
    }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - System Authorization
                    VStack(alignment: .leading, spacing: 8) {
                        SettingsGroupedSurface {
                            SettingsSectionLabel(text: String(localized: "Notification access", comment: "Notification authorization section header"))
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)

                            HStack(spacing: 12) {
                                Image(systemName: "bell.badge")
                                    .font(.geist(size: 15))
                                    .foregroundStyle(notificationStatusColor)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                Text(String(localized: "System notifications", comment: "Notification authorization row title"))
                                    .font(.geist(.subheadline))
                                    .foregroundStyle(theme.adaptivePrimaryText)

                                Spacer(minLength: 12)

                                Text(notificationStatusText)
                                    .font(.geist(.caption).weight(.semibold))
                                    .foregroundStyle(notificationStatusColor)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)

                            if let actionTitle = notificationActionTitle {
                                DetailDivider()

                                Button(actionTitle) {
                                    handleNotificationAction()
                                }
                                .font(.geist(.subheadline).weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("settings.notifications.authorization")

                        if notificationDeliveryIsUnavailable {
                            SettingsFooter(text: String(localized: "Reminders will not be delivered until notifications are allowed.", comment: "Notifications unavailable footer"))
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Access Window
                    SettingsGroupedSurface {
                        SettingsSectionLabel(text: String(localized: "Access window", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        SettingsToggleRow(
                            icon: "timer",
                            title: String(localized: "1 minute before access ends", comment: "Notification preference for access ending soon"),
                            isOn: $oneMinBefore
                        )

                        DetailDivider()

                        SettingsToggleRow(
                            icon: "clock.badge.exclamationmark",
                            title: String(localized: "When access ends", comment: "Notification preference for access ending"),
                            isOn: $timerOver
                        )
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.notifications.accessWindow")

                    // MARK: - Canvas Reminder
                    SettingsGroupedSurface {
                        SettingsSectionLabel(text: String(localized: "Canvas reminder", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        SettingsToggleRow(
                            icon: "paintpalette",
                            title: String(localized: "Daily canvas reminder"),
                            isOn: $canvasReminder,
                            subtitle: String(localized: "Get a nudge to fill your canvas with the things that colored up your day.")
                        )
                        .onChange(of: canvasReminder) { _, _ in rescheduleCanvas() }

                        if canvasReminder {
                            DetailDivider()

                            DatePicker(
                                selection: canvasTimeBinding,
                                displayedComponents: .hourAndMinute
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.geist(size: 15))
                                        .foregroundStyle(theme.adaptiveSecondaryText)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    Text(String(localized: "Remind at", comment: "Canvas reminder time label"))
                                        .font(.geist(.subheadline))
                                        .foregroundStyle(theme.adaptivePrimaryText)
                                }
                            }
                            .tint(AppColors.brandAccent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Day Reset Warning
                    SettingsGroupedSurface {
                        SettingsSectionLabel(text: String(localized: "Day reset", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        SettingsToggleRow(
                            icon: "arrow.counterclockwise",
                            title: String(localized: "Canvas reset warning"),
                            isOn: $dayResetWarning,
                            subtitle: String(localized: "A heads-up before your canvas resets for a new day.")
                        )
                        .onChange(of: dayResetWarning) { _, _ in rescheduleDayReset() }

                        if dayResetWarning {
                            DetailDivider()

                            HStack(spacing: 12) {
                                Image(systemName: "hourglass")
                                    .font(.geist(size: 15))
                                    .foregroundStyle(theme.adaptiveSecondaryText)
                                    .frame(width: 24)
                                Text(String(localized: "Warn before reset"))
                                    .font(.geist(.subheadline))
                                    .foregroundStyle(theme.adaptivePrimaryText)
                                Spacer()
                                Menu {
                                    ForEach([1, 2, 3], id: \.self) { h in
                                        Button {
                                            dayResetWarningHours = h
                                            rescheduleDayReset()
                                        } label: {
                                            if dayResetWarningHours == h {
                                                Label(h == 1 ? String(localized: "1 hour") : String(localized: "\(h) hours"), systemImage: "checkmark")
                                            } else {
                                                Text(h == 1 ? String(localized: "1 hour") : String(localized: "\(h) hours"))
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(dayResetWarningHours == 1 ? String(localized: "1 hour") : String(localized: "\(dayResetWarningHours) hours"))
                                            .font(.geist(.subheadline))
                                            .foregroundStyle(theme.adaptiveSecondaryText)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.geist(.caption2))
                                            .foregroundStyle(theme.adaptiveMutedText)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Notifications", comment: "Navigation title"))
        .task {
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationStatus() }
        }
    }

    // MARK: - Reschedule helpers

    private func rescheduleCanvas() {
        (model.notificationService as? NotificationManager)?.scheduleDailyCanvasReminder()
    }

    private func rescheduleDayReset() {
        (model.notificationService as? NotificationManager)?
            .scheduleDayResetWarning(dayEndHour: model.dayEndHour, dayEndMinute: model.dayEndMinute)
    }

    private var notificationStatusText: String {
        switch notificationPresentation.status {
        case .allowed:
            String(localized: "Allowed", comment: "Notification permission status")
        case .notRequested:
            String(localized: "Not requested", comment: "Notification permission status")
        case .offInSystemSettings:
            String(localized: "Off in System Settings", comment: "Notification permission status")
        case .checkAccess:
            String(localized: "Check access", comment: "Notification permission status")
        case .connected:
            String(localized: "Connected", comment: "Permission status")
        case .unavailable:
            String(localized: "N/A", comment: "Permission – not available badge")
        case .actionNeeded:
            String(localized: "Action needed", comment: "Permission status")
        }
    }

    private var notificationActionTitle: String? {
        switch notificationPresentation.action {
        case .requestPermission:
            String(localized: "Allow notifications", comment: "Notification permission action")
        case .openSystemSettings, .checkAccess:
            String(localized: "Open Settings", comment: "Permission recovery action")
        case nil:
            nil
        }
    }

    private var notificationStatusColor: Color {
        switch notificationPresentation.status {
        case .allowed, .connected:
            .green
        case .notRequested, .offInSystemSettings, .actionNeeded:
            .orange
        case .checkAccess, .unavailable:
            theme.adaptiveMutedText
        }
    }

    private func handleNotificationAction() {
        switch notificationPresentation.action {
        case .requestPermission:
            Task {
                await model.requestNotificationPermission()
                await refreshNotificationStatus()
            }
        case .openSystemSettings, .checkAccess:
            openAppSettings()
        case nil:
            break
        }
    }

    private func refreshNotificationStatus() async {
        if usesDeniedNotificationsFixture {
            model.notificationAuthorizationStatus = .denied
            return
        }
        await model.refreshNotificationAuthorizationStatus()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(model: DIContainer.shared.makeAppModel())
    }
}
