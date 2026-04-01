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
    private var canvasReminder: Bool = true

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
                return Calendar.current.date(from: comps) ?? Date()
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    // MARK: - Access window
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel(String(localized: "ACCESS WINDOW", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        toggleRow(
                            icon: "timer",
                            title: String(localized: "1 min before time is over"),
                            isOn: $oneMinBefore
                        )

                        divider

                        toggleRow(
                            icon: "clock.badge.exclamationmark",
                            title: String(localized: "When the timer is over"),
                            isOn: $timerOver
                        )
                    }
                    .glassCard()

                    // MARK: - Canvas reminder
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel(String(localized: "CANVAS REMINDER", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        toggleRow(
                            icon: "paintpalette",
                            title: String(localized: "Daily canvas reminder"),
                            isOn: $canvasReminder
                        )
                        .onChange(of: canvasReminder) { _, _ in rescheduleCanvas() }

                        if canvasReminder {
                            divider

                            HStack {
                                Image(systemName: "clock")
                                    .font(.subheadline)
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

                        Text(String(localized: "Get a nudge to fill your canvas with the things that colored up your day."))
                            .font(.caption)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                            .padding(.top, 4)
                    }
                    .glassCard()

                    // MARK: - Day reset warning
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel(String(localized: "DAY RESET WARNING", comment: "Notification section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        toggleRow(
                            icon: "arrow.counterclockwise",
                            title: String(localized: "Canvas reset warning"),
                            isOn: $dayResetWarning
                        )
                        .onChange(of: dayResetWarning) { _, _ in rescheduleDayReset() }

                        if dayResetWarning {
                            divider

                            HStack {
                                Image(systemName: "hourglass")
                                    .font(.subheadline)
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
                                    Text(dayResetWarningHours == 1 ? String(localized: "1 hour") : String(localized: "\(dayResetWarningHours) hours"))
                                        .font(.subheadline)
                                        .foregroundStyle(theme.adaptiveSecondaryText)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(theme.adaptiveMutedText)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        Text(String(localized: "A heads-up before your canvas resets for a new day."))
                            .font(.caption)
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                            .padding(.top, 4)
                    }
                    .glassCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .energyGradientBackground(model: model)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Back"))
                        .font(.subheadline)
                }
                .foregroundStyle(theme.adaptivePrimaryText)
            }
            Spacer()
            Text(String(localized: "Notifications", comment: "Navigation title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            Color.clear.frame(width: 50, height: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptivePrimaryText)
            }
        }
        .tint(AppColors.brandAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.adaptiveDividerColor)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(theme.adaptiveMutedText)
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
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
