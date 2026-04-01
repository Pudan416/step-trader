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

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .font(.subheadline)
                                .foregroundColor(theme.adaptiveSecondaryText)
                                .frame(width: 24)
                            Text(String(localized: "Steps goal"))
                                .font(.subheadline)
                                .foregroundColor(theme.adaptivePrimaryText)
                            Spacer()
                            Text(formatCompactNumber(Int(stepsTarget)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(theme.adaptivePrimaryText)
                        }
                        Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                            .tint(AppColors.brandAccent)
                        HStack {
                            Text(String(localized: "5K", comment: "Steps slider minimum")).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
                            Spacer()
                            Text(String(localized: "15K", comment: "Steps slider maximum")).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
                        }
                    }
                    .padding(14)
                    .glassCard()
                    .onChange(of: stepsTarget) { _, _ in
                        UserDefaults.stepsTrader().set(stepsTarget, forKey: "userStepsTarget")
                        model.recalculateDailyEnergy()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .font(.subheadline)
                                .foregroundColor(theme.adaptiveSecondaryText)
                                .frame(width: 24)
                            Text(String(localized: "Sleep goal"))
                                .font(.subheadline)
                                .foregroundColor(theme.adaptivePrimaryText)
                            Spacer()
                            Text(String(format: "%.1fh", sleepTarget))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(theme.adaptivePrimaryText)
                        }
                        Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                            .tint(AppColors.brandAccent)
                        HStack {
                            Text(String(localized: "6h", comment: "Sleep slider minimum")).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
                            Spacer()
                            Text(String(localized: "10h", comment: "Sleep slider maximum")).font(.caption2).foregroundColor(theme.adaptiveSecondaryText)
                        }
                    }
                    .padding(14)
                    .glassCard()
                    .onChange(of: sleepTarget) { _, _ in
                        UserDefaults.stepsTrader().set(sleepTarget, forKey: "userSleepTarget")
                        model.recalculateDailyEnergy()
                    }

                    NavigationLink {
                        DayEndSettingsView(model: model)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundColor(theme.adaptiveSecondaryText)
                                .frame(width: 24)
                            Text(String(localized: "Day resets at"))
                                .font(.subheadline)
                                .foregroundColor(theme.adaptivePrimaryText)
                            Spacer()
                            Text(formattedDayEnd)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(theme.adaptiveSecondaryText)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(theme.adaptiveMutedText)
                        }
                        .padding(14)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var formattedDayEnd: String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }

}
