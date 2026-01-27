import SwiftUI

struct CategorySettingsView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    @Environment(\.dismiss) private var dismiss
    
    // Settings state
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var selectedOptions: Set<String> = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Category-specific settings
                    if category == .move {
                        stepsTargetSection
                    } else if category == .reboot {
                        sleepTargetSection
                    }
                    
                    // Options selection
                    optionsSelectionSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(loc(appLanguage, "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Save")) {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                print("🟡 CategorySettingsView: Loading settings for category: \(category.rawValue)")
                // Загружаем настройки асинхронно
                await loadSettingsAsync()
                print("🟡 CategorySettingsView: Settings loaded")
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            print("🟢 CategorySettingsView body appeared, category: \(category.rawValue), appLanguage: \(appLanguage)")
        }
    }
    
    private var stepsTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Daily Steps Goal"))
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("\(formatNumber(Int(stepsTarget)))")
                        .font(.title2.bold())
                    Text(loc(appLanguage, "steps"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                
                HStack {
                    Text("5,000")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("15,000")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                    .tint(categoryColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var sleepTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc(appLanguage, "Daily Sleep Goal"))
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text(String(format: "%.1fh", sleepTarget))
                        .font(.title2.bold())
                    Text(loc(appLanguage, "hours"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                
                HStack {
                    Text("6h")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("10h")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                    .tint(categoryColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var optionsSelectionSection: some View {
        let allOptions = EnergyDefaults.options.filter { $0.category == category }
        
        return VStack(alignment: .leading, spacing: 16) {
            Text(loc(appLanguage, "Select Activities"))
                .font(.headline)
            
            Text(loc(appLanguage, "Choose up to 4 activities you want to track daily"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            if allOptions.isEmpty {
                Text(loc(appLanguage, "No options available for this category"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(allOptions) { option in
                        optionToggle(option: option)
                    }
                }
            }
        }
        .onAppear {
            print("🟡 CategorySettingsView: optionsSelectionSection appeared for \(category.rawValue), allOptions count: \(allOptions.count), selectedOptions count: \(selectedOptions.count)")
        }
    }
    
    private func optionToggle(option: EnergyOption) -> some View {
        let isSelected = selectedOptions.contains(option.id)
        
        return Button {
            if isSelected {
                selectedOptions.remove(option.id)
            } else {
                if selectedOptions.count < EnergyDefaults.maxSelectionsPerCategory {
                    selectedOptions.insert(option.id)
                }
            }
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
    
    private var categoryColor: Color {
        switch category {
        case .move: return .green
        case .reboot: return .blue
        case .joy: return .orange
        }
    }
    
    private func loadSettings() {
        // Загружаем настройки синхронно, но быстро
        let preferred = model.preferredOptions(for: category)
        selectedOptions = Set(preferred.map { $0.id })
        
        // Load targets from UserDefaults or use defaults from EnergyDefaults
        let defaults = UserDefaults.stepsTrader()
        if category == .move {
            stepsTarget = defaults.object(forKey: "userStepsTarget") as? Double ?? EnergyDefaults.stepsTarget
        } else if category == .reboot {
            sleepTarget = defaults.object(forKey: "userSleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
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
        
        // Save targets to UserDefaults - these are used in calculations
        let defaults = UserDefaults.stepsTrader()
        if category == .move {
            defaults.set(stepsTarget, forKey: "userStepsTarget")
            // Trigger recalculation
            model.recalculateDailyEnergy()
        } else if category == .reboot {
            defaults.set(sleepTarget, forKey: "userSleepTarget")
            // Trigger recalculation
            model.recalculateDailyEnergy()
        }
    }
    
    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
