import SwiftUI

struct EnergySetupView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
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
        List {
            Section {
                DatePicker(
                    loc(appLanguage, "End of day", "Конец дня"),
                    selection: dayEndDateBinding,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
            } header: {
                Text(loc(appLanguage, "Daily reset time", "Время сброса"))
            } footer: {
                Text(loc(appLanguage, "Points reset at this time every day.", "Баллы сбрасываются в это время каждый день."))
            }
            
            Section {
                optionList(category: .recovery, title: loc(appLanguage, "Recovery choices (pick up to 4)", "Восстановление (до 4)"))
            }
            
            Section {
                optionList(category: .activity, title: loc(appLanguage, "Activity choices (pick up to 4)", "Активность (до 4)"))
            }
            
            Section {
                optionList(category: .joy, title: loc(appLanguage, "Joy choices (pick up to 4)", "Радость (до 4)"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc(appLanguage, "Daily setup", "Настройка дня"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(loc(appLanguage, "Done", "Готово")) {
                    dismiss()
                }
            }
        }
    }
    
    private func optionList(category: EnergyCategory, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ForEach(model.availableOptions(for: category)) { option in
                Button {
                    model.togglePreferredOption(optionId: option.id, category: category)
                } label: {
                    HStack {
                        Text(option.title(for: appLanguage))
                            .foregroundColor(.primary)
                        Spacer()
                        if model.isPreferredOptionSelected(option.id, category: category) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
