import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory?
    let outerWorldSteps: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var selectedOption: EnergyOption? = nil
    @State private var selectedOptionEntry: OptionEntry? = nil
    
    // Optional callback for canvas integration
    var onActivityConfirmed: ((String, EnergyCategory, String) -> Void)? = nil
    var onActivityUndo: ((String, EnergyCategory) -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header: category asset + points
                    headerSection

                    // Activity list
                    if let category = category {
                        optionsSection(category: category)
                    } else {
                        outerWorldContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedOption) { option in
                if let category = category {
                    OptionEntrySheet(
                        option: option,
                        category: category,
                        entry: $selectedOptionEntry,
                        onSave: { entry in
                            saveEntry(entry, for: option)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Title
    
    private var categoryTitle: String {
        switch category {
        case .body: return "Body"
        case .mind: return "Mind"
        case .heart: return "Heart"
        case nil: return "Outer World"
        }
    }
    
    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            // Category asset image (tinted) instead of SF Symbol
            categoryAssetImage
                .frame(width: 80, height: 80)
            
            // Points — compact
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(currentPoints)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .monospacedDigit()
                Text("/\(maxPoints)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var categoryAssetImage: some View {
        let assetName = categoryAssetName
        if let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(categoryColor.opacity(0.6))
                .aspectRatio(contentMode: .fit)
        } else {
            // Fallback to SF Symbol
            Image(systemName: categoryIcon)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(categoryColor.opacity(0.6))
        }
    }
    
    // MARK: - Activity List
    
    @ViewBuilder
    private func optionsSection(category: EnergyCategory) -> some View {
        let options = EnergyDefaults.options.filter { $0.category == category }
        
        VStack(spacing: 6) {
            ForEach(options) { option in
                optionRow(option: option, category: category)
            }
        }
    }
    
    private func optionRow(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        
        return Button {
            if isSelected {
                withAnimation(.spring(response: 0.3)) {
                    model.toggleDailySelection(optionId: option.id, category: category)
                    deleteEntry(for: option.id)
                    onActivityUndo?(option.id, category)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                selectedOptionEntry = loadEntry(for: option.id)
                selectedOption = option
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: 10) {
                // Small icon
                Image(systemName: option.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isSelected ? getEntryColor(for: option.id) : theme.textPrimary.opacity(0.06))
                    )
                
                // Title only — no description
                Text(option.title(for: "en"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(getEntryColor(for: option.id))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? getEntryColor(for: option.id).opacity(0.08) : theme.textPrimary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var outerWorldContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collect energy drops by exploring the Outer World")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
    }
    
    // MARK: - Helpers
    
    private var categoryColor: Color {
        switch category {
        case .body: return .green
        case .mind: return .purple
        case .heart: return .orange
        case nil: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch category {
        case .body: return "figure.run"
        case .mind: return "sparkles"
        case .heart: return "heart.fill"
        case nil: return "battery.100.bolt"
        }
    }
    
    /// Returns the first asset name for this category (used as header icon)
    private var categoryAssetName: String {
        switch category {
        case .body: return "body 1"
        case .mind: return "mind 1"
        case .heart: return "heart 1"
        case nil: return ""
        }
    }
    
    private var currentPoints: Int {
        switch category {
        case .body: return model.activityPointsToday
        case .mind: return model.creativityPointsToday
        case .heart: return model.joysCategoryPointsToday
        case nil: return outerWorldSteps
        }
    }
    
    private var maxPoints: Int {
        switch category {
        case .body: return 20
        case .mind: return 20
        case .heart: return 20
        case nil: return 50
        }
    }
    
    // MARK: - Entry Management
    
    private func loadEntry(for optionId: String) -> OptionEntry? {
        let dayKey = AppModel.dayKey(for: Date())
        let entryId = "\(optionId)_\(dayKey)"
        guard let data = UserDefaults.standard.data(forKey: "option_entry_\(entryId)"),
              let entry = try? JSONDecoder().decode(OptionEntry.self, from: data) else {
            return nil
        }
        return entry
    }
    
    private func saveEntry(_ entry: OptionEntry, for option: EnergyOption) {
        guard let category = category else { return }
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: "option_entry_\(entry.id)")
        }
        if !model.isDailySelected(option.id, category: category) {
            model.toggleDailySelection(optionId: option.id, category: category)
        }
        onActivityConfirmed?(option.id, category, entry.colorHex)
    }
    
    private func deleteEntry(for optionId: String) {
        let dayKey = AppModel.dayKey(for: Date())
        let entryId = "\(optionId)_\(dayKey)"
        UserDefaults.standard.removeObject(forKey: "option_entry_\(entryId)")
    }
    
    private func getEntryColor(for optionId: String) -> Color {
        if let entry = loadEntry(for: optionId) {
            return Color(hex: entry.colorHex)
        }
        return categoryColor
    }
}
