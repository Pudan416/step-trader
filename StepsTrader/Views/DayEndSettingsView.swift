import SwiftUI

struct DayEndSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader()) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader()) private var dayEndMinuteSetting: Int = 0

    @State private var selectedMinutes: Int = 23 * 60
    @Environment(\.dismiss) private var dismiss
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    private var allowedMinutes: [Int] { DayEndOptions.allowedMinutes }

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
                            .foregroundStyle(.primary)
                        }
                        Spacer()
                        Text(String(localized: "Day Reset", comment: "Navigation title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Color.clear.frame(width: 50, height: 1)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .semibold))
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

                        DayResetTimePicker(
                            selectedMinutes: $selectedMinutes,
                            allowedMinutes: allowedMinutes
                        )
                        .padding(.bottom, 14)
                    }
                    .glassCard()

                    Text(String(localized: "Your canvas and colors reset at this time each day."))
                        .font(.caption)
                        .foregroundStyle(theme.adaptiveSecondaryText)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .energyGradientBackground(model: model, showGrain: false)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
        .onAppear { syncSelectedFromStorage() }
        .onChange(of: selectedMinutes) { _, newValue in
            let hour = (newValue / 60) % 24
            let minute = newValue % 60
            dayEndHourSetting = hour
            dayEndMinuteSetting = minute
            model.updateDayEnd(hour: hour, minute: minute)
        }
    }

    /// Snap to nearest valid picker step on appear. If the stored value isn't on the
    /// grid (e.g. legacy dayEnd=0 before the picker was constrained), we write the
    /// snapped value back so the visible picker and persisted state always agree.
    private func syncSelectedFromStorage() {
        let current = dayEndHourSetting * 60 + dayEndMinuteSetting
        if allowedMinutes.contains(current) {
            selectedMinutes = current
            return
        }
        let snapped = DayEndOptions.nearestAllowed(to: current)
        selectedMinutes = snapped
        let h = (snapped / 60) % 24
        let m = snapped % 60
        dayEndHourSetting = h
        dayEndMinuteSetting = m
        model.updateDayEnd(hour: h, minute: m)
    }

}

#Preview {
    NavigationStack {
        DayEndSettingsView(model: DIContainer.shared.makeAppModel())
    }
}
