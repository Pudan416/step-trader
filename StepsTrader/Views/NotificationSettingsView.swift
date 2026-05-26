import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

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
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: String(localized: "Notifications", comment: "Navigation title"))
                        .padding(.horizontal, 16)

                    // MARK: - Access Window
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "Access window", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        SettingsToggleRow(
                            icon: "timer",
                            title: String(localized: "1 min before time is over"),
                            isOn: $oneMinBefore
                        )

                        DetailDivider()

                        SettingsToggleRow(
                            icon: "clock.badge.exclamationmark",
                            title: String(localized: "When the timer is over"),
                            isOn: $timerOver
                        )
                    }
                    .padding(.horizontal, 16)

                    DetailDivider().padding(.horizontal, 16)

                    // MARK: - Canvas Reminder
                    VStack(alignment: .leading, spacing: 0) {
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

                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 15))
                                    .foregroundStyle(theme.adaptiveSecondaryText)
                                    .frame(width: 24)
                                Text(String(localized: "Remind at"))
                                    .font(.subheadline)
                                    .foregroundStyle(theme.adaptivePrimaryText)
                                Spacer()
                                DatePicker("", selection: canvasTimeBinding, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .tint(AppColors.brandAccent)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 16)

                    DetailDivider().padding(.horizontal, 16)

                    // MARK: - Day Reset Warning
                    VStack(alignment: .leading, spacing: 0) {
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
                                    .font(.system(size: 15))
                                    .foregroundStyle(theme.adaptiveSecondaryText)
                                    .frame(width: 24)
                                Text(String(localized: "Warn before reset"))
                                    .font(.subheadline)
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
                                            .font(.subheadline)
                                            .foregroundStyle(theme.adaptiveSecondaryText)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
    }

    // MARK: - Reschedule helpers

    private func rescheduleCanvas() {
        (model.notificationService as? NotificationManager)?.scheduleDailyCanvasReminder()
    }

    private func rescheduleDayReset() {
        (model.notificationService as? NotificationManager)?
            .scheduleDayResetWarning(dayEndHour: model.dayEndHour, dayEndMinute: model.dayEndMinute)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(model: DIContainer.shared.makeAppModel())
    }
}
