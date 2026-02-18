import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory?
    let outerWorldSteps: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var selectedOption: EnergyOption? = nil
    @State private var selectedOptionEntry: OptionEntry? = nil
    
    // Optional callback for canvas integration — (optionId, category, hexColor, assetVariant?)
    var onActivityConfirmed: ((String, EnergyCategory, String, Int?) -> Void)? = nil
    var onActivityUndo: ((String, EnergyCategory) -> Void)? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 16) {
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
            }
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
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
        .presentationBackground(.clear)
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
            // Category asset image (tinted)
            categoryAssetImage
                .frame(width: 80, height: 80)
            
            // Points — compact
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(currentPoints)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("/\(maxPoints)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassCard()
    }
    
    @ViewBuilder
    private var categoryAssetImage: some View {
        let assetName = categoryAssetName
        if let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle((category?.color ?? .cyan).opacity(0.6))
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: categoryIcon)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle((category?.color ?? .cyan).opacity(0.6))
        }
    }
    
    // MARK: - Activity List
    
    @ViewBuilder
    private func optionsSection(category: EnergyCategory) -> some View {
        let options = EnergyDefaults.options.filter { $0.category == category }
        
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
                optionRow(option: option, category: category)
            }
        }
        .glassCard()
    }
    
    private func optionRow(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let isDisabled = !isSelected && model.isDailyLimitReached(for: category)
        
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
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(isSelected ? getEntryColor(for: option.id) : Color.primary.opacity(0.06))
                    )
                
                // Title
                Text(option.title(for: "en"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(getEntryColor(for: option.id))
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1.0)
    }
    
    private var outerWorldContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collect energy drops by exploring the Outer World")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .glassCard()
    }
    
    // MARK: - Helpers
    
    private var categoryIcon: String {
        switch category {
        case .body: return "figure.run"
        case .mind: return "sparkles"
        case .heart: return "heart.fill"
        case nil: return "battery.100.bolt"
        }
    }
    
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
        onActivityConfirmed?(option.id, category, entry.colorHex, entry.assetVariant)
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
        return category?.color ?? .cyan
    }
}
