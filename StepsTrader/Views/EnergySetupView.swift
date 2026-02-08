import SwiftUI

struct EnergySetupView: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    private var dayEndTimeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let date = Calendar.current.date(from: comps) ?? Date()
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DayEndSettingsView(model: model)
                    } label: {
                        HStack {
                            Text(loc(appLanguage, "End of day"))
                            Spacer()
                            Text(dayEndTimeLabel)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Daily reset time"))
                } footer: {
                    Text(loc(appLanguage, "Points reset at this time every day."))
                }
                
                Section {
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .activity,
                            appLanguage: appLanguage
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .foregroundColor(.green)
                            Text(loc(appLanguage, "Activity"))
                        }
                    }
                    
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .creativity,
                            appLanguage: appLanguage
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text(loc(appLanguage, "Creativity"))
                        }
                    }
                    
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .joys,
                            appLanguage: appLanguage
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.orange)
                            Text(loc(appLanguage, "Joys"))
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Daily gallery"))
                } footer: {
                    Text(loc(appLanguage, "Set goals and manage cards per category."))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc(appLanguage, "Daily setup"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) {
                        onDone?()
                        dismiss()
                    }
                }
            }
        }
    }
}
