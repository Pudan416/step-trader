import SwiftUI

struct SettingsEnergyPage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = EnergyDefaults.sleepTargetHours
    @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader()) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader()) private var dayEndMinuteSetting: Int = 0
    @Environment(\.appTheme) private var theme

    private var dayStartMinutes: Binding<Int> {
        Binding(
            get: { dayEndHourSetting * 60 + dayEndMinuteSetting },
            set: { minutes in
                guard DayEndOptions.allowedMinutes.contains(minutes) else { return }
                // Keep the model as the single writer so it can re-anchor the day.
                model.updateDayEnd(hour: minutes / 60, minute: minutes % 60)
            }
        )
    }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // MARK: - Steps
                    SettingsGroupedSurface {
                        VStack(spacing: 12) {
                            sectionHeader(
                                icon: "figure.walk",
                                title: String(localized: "Daily step goal"),
                                color: AppColors.brandAccent
                            )

                            StepGoalDrumPicker(value: $stepsTarget)
                                .environment(\.appTheme, .night)
                                .padding(.bottom, 14)
                                .onChange(of: stepsTarget) { _, _ in
                                    model.recalculateDailyEnergy()
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.yourDay.steps")

                    // MARK: - Sleep Goal
                    SettingsGroupedSurface {
                        VStack(spacing: 12) {
                            sectionHeader(
                                icon: "bed.double.fill",
                                title: String(localized: "Sleep goal"),
                                color: Color.indigo
                            )

                            SleepDurationStepper(hours: $sleepTarget)
                                .environment(\.appTheme, .night)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 14)
                                .onChange(of: sleepTarget) { _, _ in
                                    model.recalculateDailyEnergy()
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.yourDay.sleep")

                    // MARK: - Day Start
                    SettingsGroupedSurface {
                        VStack(spacing: 10) {
                            sectionHeader(
                                icon: "clock.arrow.circlepath",
                                title: String(localized: "Day starts at"),
                                color: Color.orange
                            )

                            DayResetTimePicker(
                                selectedMinutes: dayStartMinutes,
                                allowedMinutes: DayEndOptions.allowedMinutes
                            )
                            .padding(.bottom, 14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("settings.yourDay.boundary")

                    SettingsFooter(text: String(localized: "Late-night activity stays in the previous day until this time."))
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Goals & schedule", comment: "Settings section title"))
    }

    // MARK: - Shared

    private func sectionHeader(icon: String, title: String, color: Color, value: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.geist(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.geist(.subheadline).weight(.semibold))
                .foregroundStyle(SettingsCardAppearance.primaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(.geist(.subheadline).weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

}

#Preview {
    NavigationStack {
        SettingsEnergyPage(model: DIContainer.shared.makeAppModel())
    }
}
