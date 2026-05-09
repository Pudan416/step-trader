import SwiftUI

struct SettingsEnergyPage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = EnergyDefaults.sleepTargetHours
    @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader()) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader()) private var dayEndMinuteSetting: Int = 0
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    private var allowedBedtimeMinutes: [Int] { DayEndOptions.allowedMinutes }

    @State private var bedtimeMinutes: Int = 23 * 60

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
        .onAppear { syncBedtimeFromStorage() }
    }

    /// Mirrors `DayEndSettingsView.syncSelectedFromStorage()`: if the stored dayEnd
    /// is off-grid, snap to the nearest valid step and write the snapped value back so
    /// the picker UI and persistent state agree.
    private func syncBedtimeFromStorage() {
        let current = dayEndHourSetting * 60 + dayEndMinuteSetting
        if allowedBedtimeMinutes.contains(current) {
            bedtimeMinutes = current
            return
        }
        let snapped = DayEndOptions.nearestAllowed(to: current)
        bedtimeMinutes = snapped
        let h = (snapped / 60) % 24
        let m = snapped % 60
        dayEndHourSetting = h
        dayEndMinuteSetting = m
        model.updateDayEnd(hour: h, minute: m)
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

}
