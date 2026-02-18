import SwiftUI

struct EnergySetupView: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    private var dayEndTimeLabel: String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DayEndSettingsView(model: model)
                    } label: {
                        HStack {
                            Text("End of day")
                            Spacer()
                            Text(dayEndTimeLabel)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Daily reset time")
                } footer: {
                    Text("Points reset at this time every day.")
                }
                
                Section {
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .body
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .foregroundColor(.green)
                            Text("Activity")
                        }
                    }
                    
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .mind
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text("Creativity")
                        }
                    }
                    
                    NavigationLink {
                        CategorySettingsView(
                            model: model,
                            category: .heart
                        )
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.orange)
                            Text("Joys")
                        }
                    }
                } header: {
                    Text("Daily gallery")
                } footer: {
                    Text("Set goals and manage cards per category.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Daily setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone?()
                        dismiss()
                    }
                }
            }
        }
    }
}
