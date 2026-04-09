import SwiftUI

struct SettingsEnergyPage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader()) private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = EnergyDefaults.sleepTargetHours
    @AppStorage(SharedKeys.dayEndHour) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute) private var dayEndMinuteSetting: Int = 0
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: String(localized: "Limits", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: - Targets
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionLabel(text: String(localized: "DAILY TARGETS", comment: "Limits section header"))
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        sliderRow(
                            icon: "figure.walk",
                            title: String(localized: "Steps goal"),
                            value: formatCompactNumber(Int(stepsTarget)),
                            sliderValue: $stepsTarget,
                            range: 5_000...15_000,
                            step: 500,
                            minLabel: "5K",
                            maxLabel: "15K"
                        )
                        .onChange(of: stepsTarget) { _, _ in
                            UserDefaults.stepsTrader().set(stepsTarget, forKey: "userStepsTarget")
                            model.recalculateDailyEnergy()
                        }

                        DetailDivider()

                        sliderRow(
                            icon: "bed.double.fill",
                            title: String(localized: "Sleep goal"),
                            value: String(format: "%.1fh", sleepTarget),
                            sliderValue: $sleepTarget,
                            range: 6...10,
                            step: 0.5,
                            minLabel: "6h",
                            maxLabel: "10h"
                        )
                        .onChange(of: sleepTarget) { _, _ in
                            UserDefaults.stepsTrader().set(sleepTarget, forKey: "userSleepTarget")
                            model.recalculateDailyEnergy()
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, 16)

                    // MARK: - Day Boundary
                    NavigationLink {
                        DayEndSettingsView(model: model)
                    } label: {
                        SettingsNavRow(
                            icon: "clock.arrow.circlepath",
                            title: String(localized: "Day resets at"),
                            value: formattedDayEnd
                        )
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    SettingsFooter(text: String(localized: "Your canvas and colors reset at this time each day."))
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Slider Row

    private func sliderRow(
        icon: String,
        title: String,
        value: String,
        sliderValue: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        minLabel: String,
        maxLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(theme.adaptiveSecondaryText)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(theme.adaptivePrimaryText)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(theme.adaptivePrimaryText)
            }
            Slider(value: sliderValue, in: range, step: step)
                .tint(AppColors.brandAccent)
            HStack {
                Text(minLabel).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
                Spacer()
                Text(maxLabel).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var formattedDayEnd: String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }
}
