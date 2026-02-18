import SwiftUI

struct CategorySettingsView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String = "en"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    // Settings state
    // Use the app group suite so @AppStorage and loadSettings/saveSettings
    // read/write the same UserDefaults (audit fix #44)
    @AppStorage("userStepsTarget", store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget", store: UserDefaults(suiteName: SharedKeys.appGroupId))
    private var sleepTarget: Double = 8.0
    @State private var selectedOptions: Set<String> = []
    @State private var deleteOptionId: String? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Category-specific settings
                    if category == .body {
                        stepsTargetSection
                    } else if category == .heart {
                        sleepTargetSection
                    }
                    
                    // Options selection
                    optionsSelectionSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(theme.backgroundColor)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                AppLogger.energy.debug("🟡 CategorySettingsView: Loading settings for category: \(category.rawValue)")
                // Load settings asynchronously
                await loadSettingsAsync()
                AppLogger.energy.debug("🟡 CategorySettingsView: Settings loaded")
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            AppLogger.energy.debug("🟢 CategorySettingsView body appeared, category: \(category.rawValue), appLanguage: \(appLanguage)")
        }
    }
    
    private var stepsTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Steps Goal")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text("\(formatGroupedNumber(Int(stepsTarget)))")
                        .font(.title2.bold())
                    Text("steps")
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
                    .tint(category.color)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var sleepTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Sleep Goal")
                .font(.headline)
            
            VStack(spacing: 8) {
                HStack {
                    Text(String(format: "%.1fh", sleepTarget))
                        .font(.title2.bold())
                    Text("hours")
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
                    .tint(category.color)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var optionsSelectionSection: some View {
        let allOptions = model.orderedOptions(for: category)
        
        return VStack(alignment: .leading, spacing: 16) {
            Text("Select Activities")
                .font(.headline)
            
            Text("Choose up to 4 activities I want to track daily")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if allOptions.isEmpty {
                Text("No options available for this category")
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
            AppLogger.energy.debug("🟡 CategorySettingsView: optionsSelectionSection appeared for \(category.rawValue), allOptions count: \(allOptions.count), selectedOptions count: \(selectedOptions.count)")
        }
        .alert(
            "Delete activity?",
            isPresented: Binding(
                get: { deleteOptionId != nil },
                set: { if !$0 { deleteOptionId = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                deleteOptionId = nil
            }
            Button("Delete", role: .destructive) {
                if let id = deleteOptionId {
                    model.deleteOption(optionId: id)
                    selectedOptions.remove(id)
                }
                deleteOptionId = nil
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }
    
    private func optionToggle(option: EnergyOption) -> some View {
        let isSelected = selectedOptions.contains(option.id)
        
        let toggleSelection = {
            if isSelected {
                selectedOptions.remove(option.id)
            } else {
                if selectedOptions.count < EnergyDefaults.maxSelectionsPerCategory {
                    selectedOptions.insert(option.id)
                }
            }
        }

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(category.color.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: option.icon)
                    .font(.systemSerif(18, weight: .semibold))
                    .foregroundColor(isSelected ? category.color : .secondary)
            }
            
            // Title
            Text(option.title(for: "en"))
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Only allow deleting custom options, not built-in ones
            if option.id.hasPrefix("custom_") {
                Button {
                    deleteOptionId = option.id
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            // Checkmark
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(category.color)
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleSelection)
    }
    
    private func loadSettings() {
        // Load settings synchronously (fast path)
        let preferred = model.preferredOptions(for: category)
        selectedOptions = Set(preferred.map { $0.id })
        
        // Load targets from UserDefaults or use defaults from EnergyDefaults
        let defaults = UserDefaults.stepsTrader()
        if category == .body {
            stepsTarget = defaults.object(forKey: "userStepsTarget") as? Double ?? EnergyDefaults.stepsTarget
        } else if category == .heart {
            sleepTarget = defaults.object(forKey: "userSleepTarget") as? Double ?? EnergyDefaults.sleepTargetHours
        }
    }
    
    @MainActor
    private func loadSettingsAsync() async {
        // Load settings asynchronously
        loadSettings()
    }
    
    private func saveSettings() {
        // Save preferred options
        model.updatePreferredOptions(Array(selectedOptions), category: category)
        
        // Save targets to UserDefaults - these are used in calculations
        let defaults = UserDefaults.stepsTrader()
        if category == .body {
            defaults.set(stepsTarget, forKey: "userStepsTarget")
            // Trigger recalculation
            model.recalculateDailyEnergy()
        } else if category == .heart {
            defaults.set(sleepTarget, forKey: "userSleepTarget")
            // Trigger recalculation
            model.recalculateDailyEnergy()
        }
    }
}
