import SwiftUI

struct DayEndSettingsView: View {
    @ObservedObject var model: AppModel
    @ScaledMetric private var displayNumberSize: CGFloat = 36
    @AppStorage(SharedKeys.dayEndHour) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute) private var dayEndMinuteSetting: Int = 0
    @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader()) private var sleepTarget: Double = EnergyDefaults.sleepTargetHours

    @State private var selectedMinutes: Int = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    private let minuteStep: Int = 15

    private var allowedMinutes: [Int] {
        var result: [Int] = []
        for m in stride(from: 21 * 60, to: 24 * 60, by: minuteStep) { result.append(m) }
        for m in stride(from: 0, through: 3 * 60, by: minuteStep) { result.append(m) }
        return result
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button { dismiss() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.subheadline.weight(.semibold))
                                Text(String(localized: "Back"))
                                    .font(.subheadline)
                            }
                            .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(String(localized: "Sleep & Reset", comment: "Navigation title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Color.clear.frame(width: 50, height: 1)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    // Sleep goal
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "bed.double")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.indigo)
                                .frame(width: 28, height: 28)
                                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            Text(String(localized: "Sleep Goal"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.adaptivePrimaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        SleepDurationStepper(hours: $sleepTarget)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 14)
                            .onChange(of: sleepTarget) { _, _ in
                                UserDefaults.stepsTrader().set(sleepTarget, forKey: "userSleepTarget")
                                model.recalculateDailyEnergy()
                            }
                    }
                    .glassCard()

                    // Day reset
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .frame(width: 28, height: 28)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                            Text(String(localized: "Day Resets At"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.adaptivePrimaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)

                        Text(formatTime(selectedMinutes))
                            .font(.system(size: displayNumberSize, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.15), value: selectedMinutes)
                            .frame(maxWidth: .infinity)

                        DayResetTimePicker(
                            selectedMinutes: $selectedMinutes,
                            allowedMinutes: allowedMinutes
                        )
                        .padding(.bottom, 14)
                    }
                    .glassCard()

                    Text(String(localized: "Your canvas and colors reset at this time each day."))
                        .font(.caption)
                        .foregroundColor(theme.adaptiveSecondaryText)
                        .padding(.horizontal, 4)
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
        .onAppear {
            let current = dayEndHourSetting * 60 + dayEndMinuteSetting
            selectedMinutes = allowedMinutes.contains(current) ? current : 0
        }
        .onChange(of: selectedMinutes) { _, newValue in
            let hour = (newValue / 60) % 24
            let minute = newValue % 60
            dayEndHourSetting = hour
            dayEndMinuteSetting = minute
            model.updateDayEnd(hour: hour, minute: minute)
        }
    }

    private func formatTime(_ minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = (minutes / 60) % 24
        comps.minute = minutes % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }
}
