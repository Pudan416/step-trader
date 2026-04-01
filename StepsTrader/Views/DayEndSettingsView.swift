import SwiftUI

struct DayEndSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.dayEndHour) private var dayEndHourSetting: Int = 0
    @AppStorage(SharedKeys.dayEndMinute) private var dayEndMinuteSetting: Int = 0
    
    @State private var selectedMinutes: Int = 21 * 60
    @Environment(\.dismiss) private var dismiss
    @Environment(\.topCardHeight) private var topCardHeight
    
    private let minuteStep: Int = 15
    
    private var allowedMinutes: [Int] {
        var result: [Int] = []
        for minutes in stride(from: 21 * 60, to: 24 * 60, by: minuteStep) {
            result.append(minutes)
        }
        for minutes in stride(from: 0, through: 3 * 60, by: minuteStep) {
            result.append(minutes)
        }
        return result
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Back + title header
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
                        Text(String(localized: "Day reset", comment: "Navigation title"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Color.clear.frame(width: 50, height: 1)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    
                    // Picker card
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "DAILY RESET TIME", comment: "Section header"))
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                        
                        Picker(String(localized: "End of day", comment: "Picker label"), selection: $selectedMinutes) {
                            ForEach(allowedMinutes, id: \.self) { minutes in
                                Text(formatTime(minutes))
                                    .tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .accessibilityLabel(String(localized: "Daily reset time", comment: "Accessibility label"))
                        .padding(.horizontal, 8)
                        
                        Text(String(localized: "Choose a time between 21:00 and 03:00."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
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
        .onAppear {
            let current = dayEndHourSetting * 60 + dayEndMinuteSetting
            if allowedMinutes.contains(current) {
                selectedMinutes = current
            } else {
                selectedMinutes = 21 * 60
                updateDayEnd(for: selectedMinutes)
            }
        }
        .onChange(of: selectedMinutes) { _, newValue in
            updateDayEnd(for: newValue)
        }
    }
    
    private func updateDayEnd(for minutes: Int) {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        dayEndHourSetting = hour
        dayEndMinuteSetting = minute
        model.updateDayEnd(hour: hour, minute: minute)
    }
    
    private func formatTime(_ minutes: Int) -> String {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }
}
