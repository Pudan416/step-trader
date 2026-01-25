import SwiftUI

struct CategorySettingsView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    @Environment(\.dismiss) private var dismiss
    
    // Settings state
    @State private var stepsTarget: Double = 10_000
    @State private var sleepTarget: Double = 8.0
    @State private var selectedOptions: Set<String> = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Category-specific settings
                    if category == .activity {
                        stepsTargetSection
                    } else if category == .recovery {
                        sleepTargetSection
                    }
                    
                    // Options selection
                    optionsSelectionSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc("Settings", "Настройки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("Cancel", "Отмена")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("Save", "Сохранить")) {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                // Загружаем настройки асинхронно
                await loadSettingsAsync()
            }
        }
    }
    
    private var stepsTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Daily Steps Goal", "Цель по шагам на день"))
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("\(formatNumber(Int(stepsTarget)))")
                        .font(.title2.bold())
                    Text(loc("steps", "шагов"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Slider(value: $stepsTarget, in: 5_000...20_000, step: 500)
                    .tint(categoryColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var sleepTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("Daily Sleep Goal", "Цель по сну на день"))
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text(String(format: "%.1fh", sleepTarget))
                        .font(.title2.bold())
                    Text(loc("hours", "часов"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Slider(value: $sleepTarget, in: 6...12, step: 0.5)
                    .tint(categoryColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var optionsSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(loc("Select Activities", "Выберите активности"))
                .font(.headline)
            
            Text(loc("Choose up to 4 activities you want to track daily", "Выберите до 4 активностей для ежедневного отслеживания"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            let allOptions = EnergyDefaults.options.filter { $0.category == category }
            
            LazyVStack(spacing: 12) {
                ForEach(allOptions) { option in
                    optionToggle(option: option)
                }
            }
        }
    }
    
    private func optionToggle(option: EnergyOption) -> some View {
        Toggle(isOn: Binding(
            get: { selectedOptions.contains(option.id) },
            set: { enabled in
                if enabled {
                    if selectedOptions.count < EnergyDefaults.maxSelectionsPerCategory {
                        selectedOptions.insert(option.id)
                    }
                } else {
                    selectedOptions.remove(option.id)
                }
            }
        )) {
            HStack {
                Text(option.title(for: appLanguage))
                    .font(.subheadline)
                Spacer()
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: categoryColor))
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var categoryColor: Color {
        switch category {
        case .recovery: return .blue
        case .activity: return .green
        case .joy: return .orange
        }
    }
    
    private func loadSettings() {
        // Загружаем настройки синхронно, но быстро
        let preferred = model.preferredOptions(for: category)
        selectedOptions = Set(preferred.map { $0.id })
        
        // Load targets from UserDefaults or use defaults from EnergyDefaults
        let defaults = UserDefaults.stepsTrader()
        if category == .activity {
            stepsTarget = defaults.object(forKey: "stepsTarget") as? Double ?? EnergyDefaults.stepsTarget
        } else if category == .recovery {
            sleepTarget = defaults.object(forKey: "sleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
        }
    }
    
    @MainActor
    private func loadSettingsAsync() async {
        // Загружаем настройки асинхронно
        loadSettings()
    }
    
    private func saveSettings() {
        // Save preferred options
        model.updatePreferredOptions(Array(selectedOptions), category: category)
        
        // Save targets to UserDefaults
        // Note: These are stored but not directly used in calculations - they're for user reference
        // The actual calculations use EnergyDefaults values
        let defaults = UserDefaults.stepsTrader()
        if category == .activity {
            defaults.set(stepsTarget, forKey: "stepsTarget")
        } else if category == .recovery {
            defaults.set(sleepTarget, forKey: "sleepTarget")
        }
    }
    
    private func formatNumber(_ value: Int) -> String {
        value < 1000 ? "\(value)" : "\(value / 1000)k"
    }
    
    private func loc(_ en: String, _ ru: String) -> String {
        appLanguage == "ru" ? ru : en
    }
}
