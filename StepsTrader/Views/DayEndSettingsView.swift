import SwiftUI

struct DayEndSettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    
    @State private var selectedMinutes: Int = 21 * 60
    
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
        List {
            Section {
                Picker(loc(appLanguage, "End of day"), selection: $selectedMinutes) {
                    ForEach(allowedMinutes, id: \.self) { minutes in
                        Text(formatTime(minutes))
                            .tag(minutes)
                    }
                }
                .pickerStyle(.wheel)
            } header: {
                Text(loc(appLanguage, "Daily reset time"))
            } footer: {
                Text(loc(appLanguage, "Choose a time between 21:00 and 03:00."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc(appLanguage, "End of day"))
        .navigationBarTitleDisplayMode(.inline)
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
