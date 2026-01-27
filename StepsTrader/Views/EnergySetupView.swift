import SwiftUI

struct EnergySetupView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @AppStorage("userStepsTarget") private var userStepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var userSleepTarget: Double = 8.0
    @Environment(\.dismiss) private var dismiss
    
    private var dayEndDateBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let cal = Calendar.current
                let now = Date()
                return cal.date(
                    bySettingHour: dayEndHourSetting,
                    minute: dayEndMinuteSetting,
                    second: 0,
                    of: now
                ) ?? now
            },
            set: { newValue in
                let cal = Calendar.current
                dayEndHourSetting = cal.component(.hour, from: newValue)
                dayEndMinuteSetting = cal.component(.minute, from: newValue)
                model.updateDayEnd(hour: dayEndHourSetting, minute: dayEndMinuteSetting)
            }
        )
    }
    
    var body: some View {
        NavigationView {
            List {
                // Daily reset time
                Section {
                    DatePicker(
                        loc(appLanguage, "End of day"),
                        selection: dayEndDateBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                } header: {
                    Text(loc(appLanguage, "Daily reset time"))
                } footer: {
                    Text(loc(appLanguage, "Points reset at this time every day."))
                }
                
                // Move section
                Section {
                    // Steps target
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text(loc(appLanguage, "Daily Steps Goal"))
                                .font(.headline)
                        }
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(formatNumber(Int(userStepsTarget)))")
                                    .font(.title2.bold())
                                Text(loc(appLanguage, "steps"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            Slider(value: $userStepsTarget, in: 5_000...15_000, step: 500)
                            
                            HStack {
                                Text("5,000")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("15,000")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Move activities
                    optionList(category: .move)
                } header: {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.green)
                        Text(loc(appLanguage, "Move"))
                    }
                } footer: {
                    Text(loc(appLanguage, "Set your daily steps goal and select up to 4 activities you want to track daily."))
                }
                
                // Reboot section
                Section {
                    // Sleep target
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            Text(loc(appLanguage, "Daily Sleep Goal"))
                                .font(.headline)
                        }
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text(String(format: "%.1f", userSleepTarget))
                                    .font(.title2.bold())
                                Text(loc(appLanguage, "hours"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            Slider(value: $userSleepTarget, in: 6...10, step: 0.5)
                            
                            HStack {
                                Text("6h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("10h")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Reboot activities
                    optionList(category: .reboot)
                } header: {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundColor(.blue)
                        Text(loc(appLanguage, "Reboot"))
                    }
                } footer: {
                    Text(loc(appLanguage, "Set your daily sleep goal and select up to 4 recovery activities you want to track daily."))
                }
                
                // Choice section
                Section {
                    optionList(category: .joy)
                } header: {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.orange)
                        Text(loc(appLanguage, "Choice"))
                    }
                } footer: {
                    Text(loc(appLanguage, "Select up to 4 choices you want to track daily."))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc(appLanguage, "Daily setup"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) {
                        // Save targets
                        let defaults = UserDefaults.stepsTrader()
                        defaults.set(userStepsTarget, forKey: "userStepsTarget")
                        defaults.set(userSleepTarget, forKey: "userSleepTarget")
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func optionList(category: EnergyCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.availableOptions(for: category)) { option in
                optionRow(option: option, category: category)
            }
        }
    }
    
    private func optionRow(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isPreferredOptionSelected(option.id, category: category)
        let categoryColor: Color = {
            switch category {
            case .move: return .green
            case .reboot: return .blue
            case .joy: return .orange
            }
        }()
        
        return Button {
            model.togglePreferredOption(optionId: option.id, category: category)
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? categoryColor : .secondary)
                }
                
                // Title
                Text(option.title(for: appLanguage))
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(categoryColor)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
