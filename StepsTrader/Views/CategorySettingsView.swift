import SwiftUI

struct CategorySettingsView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    @Environment(\.editMode) private var editMode
    
    // Settings state
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var orderedOptions: [EnergyOption] = []
    @State private var editingOption: EnergyOption? = nil
    @State private var showAddSheet = false
    
    var body: some View {
        List {
            if category == .activity {
                Section {
                    stepsTargetSection
                }
            } else if category == .recovery {
                Section {
                    sleepTargetSection
                }
            }
            
            Section {
                ForEach(orderedOptions) { option in
                    optionRow(option: option)
                }
                .onMove(perform: moveOptions)
            } header: {
                Text(loc(appLanguage, "Cards"))
            } footer: {
                Text(loc(appLanguage, "Tap to select up to 4. Swipe custom cards to edit or delete."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(loc(appLanguage, "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CustomActivityEditorView(
                category: category,
                appLanguage: appLanguage,
                initialTitle: nil,
                initialIcon: nil,
                isEditing: false
            ) { title, icon in
                _ = model.addCustomOption(
                    category: category,
                    titleEn: title,
                    titleRu: title,
                    icon: icon
                )
                reloadOptions()
            }
        }
        .sheet(item: $editingOption) { option in
            CustomActivityEditorView(
                category: category,
                appLanguage: appLanguage,
                initialTitle: option.title(for: appLanguage),
                initialIcon: option.icon,
                isEditing: true
            ) { title, icon in
                model.replaceOptionWithCustom(
                    optionId: option.id,
                    category: category,
                    titleEn: title,
                    titleRu: title,
                    icon: icon
                )
                reloadOptions()
            }
        }
        .onAppear {
            reloadOptions()
        }
        .onChange(of: stepsTarget) { _, _ in
            model.recalculateDailyEnergy()
        }
        .onChange(of: sleepTarget) { _, _ in
            model.recalculateDailyEnergy()
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
        }
    }
    
    private func optionRow(option: EnergyOption) -> some View {
        let isSelected = model.isPreferredOptionSelected(option.id, category: category)
        let isCustom = option.id.hasPrefix("custom_")
        let isEditing = editMode?.wrappedValue.isEditing == true
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(isSelected ? 0.2 : 0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? categoryColor : .secondary)
            }
            
            Text(option.title(for: appLanguage))
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            if !isEditing {
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing {
                editingOption = option
            } else {
                model.togglePreferredOption(optionId: option.id, category: category)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isCustom, !isEditing {
                Button {
                    editingOption = option
                } label: {
                    Label(loc(appLanguage, "Edit"), systemImage: "pencil")
                }
                .tint(.blue)
                
                Button(role: .destructive) {
                    model.deleteCustomOption(optionId: option.id)
                    reloadOptions()
                } label: {
                    Label(loc(appLanguage, "Delete"), systemImage: "trash")
                }
            }
        }
    }
    
    private var categoryColor: Color {
        switch category {
        case .activity: return .green
        case .recovery: return .blue
        case .joys: return .orange
        }
    }

    private func moveOptions(from source: IndexSet, to destination: Int) {
        var ids = orderedOptions.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        model.updateOptionsOrder(ids, category: category)
        reloadOptions()
    }
    
    private func reloadOptions() {
        orderedOptions = model.orderedOptions(for: category)
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
