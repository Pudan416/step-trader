import SwiftUI

struct SettingsEnergyPage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = EnergyDefaults.sleepTargetHours
    @AppStorage(SharedKeys.dayEndHour) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute) private var dayEndMinuteSetting: Int = 0
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    private let minuteStep: Int = 15

    private var allowedBedtimeMinutes: [Int] {
        var result: [Int] = []
        for m in stride(from: 21 * 60, to: 24 * 60, by: minuteStep) { result.append(m) }
        for m in stride(from: 0, through: 3 * 60, by: minuteStep) { result.append(m) }
        return result
    }

    @State private var bedtimeMinutes: Int = 0

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailHeader(title: String(localized: "Limits", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Steps
                    VStack(spacing: 12) {
                        sectionHeader(
                            icon: "figure.walk",
                            title: String(localized: "Daily Steps Goal"),
                            color: AppColors.brandAccent,
                            value: formatCompactNumber(Int(stepsTarget))
                        )

                        StepGoalDrumPicker(value: $stepsTarget)
                            .padding(.bottom, 14)
                            .onChange(of: stepsTarget) { _, _ in
                                UserDefaults.stepsTrader().set(stepsTarget, forKey: "userStepsTarget")
                                model.recalculateDailyEnergy()
                            }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Sleep Goal
                    VStack(spacing: 12) {
                        sectionHeader(
                            icon: "bed.double.fill",
                            title: String(localized: "Sleep Goal"),
                            color: Color.indigo
                        )

                        SleepDurationStepper(hours: $sleepTarget)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 14)
                            .onChange(of: sleepTarget) { _, _ in
                                UserDefaults.stepsTrader().set(sleepTarget, forKey: "userSleepTarget")
                                model.recalculateDailyEnergy()
                            }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Day Reset
                    VStack(spacing: 10) {
                        sectionHeader(
                            icon: "clock.arrow.circlepath",
                            title: String(localized: "Day Resets At"),
                            color: Color.orange
                        )

                        Text(formatTime(bedtimeMinutes))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.15), value: bedtimeMinutes)
                            .frame(maxWidth: .infinity)

                        DayResetTimePicker(
                            selectedMinutes: $bedtimeMinutes,
                            allowedMinutes: allowedBedtimeMinutes
                        )
                        .padding(.bottom, 14)
                        .onChange(of: bedtimeMinutes) { _, newValue in
                            let hour = (newValue / 60) % 24
                            let minute = newValue % 60
                            dayEndHourSetting = hour
                            dayEndMinuteSetting = minute
                            model.updateDayEnd(hour: hour, minute: minute)
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    SettingsFooter(text: String(localized: "Your canvas and colors reset at this time each day."))
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let current = dayEndHourSetting * 60 + dayEndMinuteSetting
            bedtimeMinutes = allowedBedtimeMinutes.contains(current) ? current : 0
        }
    }

    // MARK: - Shared

    private func sectionHeader(icon: String, title: String, color: Color, value: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.adaptivePrimaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func formatTime(_ minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = (minutes / 60) % 24
        comps.minute = minutes % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }
}
