import SwiftUI

// MARK: - CHOICES tab: today's choices with stats header
struct ChoiceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.appTheme) private var theme
    
    private var todayFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        f.locale = Locale(identifier: appLanguage == "ru" ? "ru_RU" : "en_US")
        return f.string(from: Date())
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Date + stats header
                VStack(alignment: .leading, spacing: 12) {
                    Text(todayFormatted)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 24) {
                        // Steps
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk")
                                .foregroundColor(theme.activityColor)
                            Text("\(formatSteps(model.stepsToday))")
                                .font(.subheadline.weight(.medium))
                            Text("+\(model.stepsPointsToday)")
                                .font(.caption)
                                .foregroundColor(theme.activityColor)
                        }
                        
                        // Sleep
                        HStack(spacing: 6) {
                            Image(systemName: "moon.fill")
                                .foregroundColor(theme.recoveryColor)
                            Text(formatSleep(model.dailySleepHours))
                                .font(.subheadline.weight(.medium))
                            Text("+\(model.sleepPointsToday)")
                                .font(.caption)
                                .foregroundColor(theme.recoveryColor)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Category rows
                CategoryCardsRow(
                    model: model,
                    category: .activity,
                    appLanguage: appLanguage
                )
                CategoryCardsRow(
                    model: model,
                    category: .recovery,
                    appLanguage: appLanguage
                )
                CategoryCardsRow(
                    model: model,
                    category: .joys,
                    appLanguage: appLanguage
                )
            }
            .padding(.vertical, 12)
        }
        .background(theme.backgroundColor)
        .navigationBarHidden(true)
    }
    
    private func formatSteps(_ steps: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: Int(steps))) ?? "\(Int(steps))"
    }
    
    private func formatSleep(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m > 0 {
            return "\(h)h \(m)m"
        }
        return "\(h)h"
    }
}

// MARK: - Memories: horizontal scroll of past days
struct MemoriesSection: View {
    let pastDays: [String: PastDaySnapshot]
    @Binding var selectedDayKey: String?
    let appLanguage: String
    
    private static let calendar = Calendar.current
    
    private var dayKeysOrdered: [String] {
        let today = Self.calendar.startOfDay(for: Date())
        return (0...60).reversed().compactMap { offset -> String? in
            guard let d = Self.calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return AppModel.dayKey(for: d)
        }
    }
    
    private var todayKey: String {
        AppModel.dayKey(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dayKeysOrdered, id: \.self) { dayKey in
                            MemoryDayCard(
                                dayKey: dayKey,
                                isToday: dayKey == todayKey,
                                hasData: pastDays[dayKey] != nil,
                                isSelected: selectedDayKey == dayKey
                            ) {
                                selectedDayKey = dayKey
                            }
                            .id(dayKey)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.none) {
                            proxy.scrollTo(todayKey, anchor: .trailing)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Memory day card
struct MemoryDayCard: View {
    let dayKey: String
    let isToday: Bool
    let hasData: Bool
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.appTheme) private var theme
    
    private var dayNum: String {
        guard let d = date(from: dayKey) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: d)
    }
    
    private func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    
    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme == .minimal ? theme.backgroundSecondary : (isToday ? theme.accentColor : Color(.secondarySystemBackground)))
                .frame(width: 44, height: 56)
                .overlay(
                    VStack(spacing: 2) {
                        Text(dayNum)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(theme == .minimal ? theme.textPrimary : (isToday ? .white : .primary))
                        if hasData {
                            Circle()
                                .fill(theme == .minimal ? theme.textPrimary.opacity(0.6) : (isToday ? Color.white.opacity(0.6) : Color.accentColor))
                                .frame(width: 5, height: 5)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected && !isToday ? theme.accentColor : (theme == .minimal ? theme.stroke : Color.clear), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category cards row with horizontal scroll
struct CategoryCardsRow: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    @State private var showCustomActivitySheet = false
    @State private var pendingOptionId: String? = nil
    @State private var showConfirmation = false
    @Environment(\.appTheme) private var theme
    
    private var categoryTitle: String {
        switch category {
        case .activity: return loc(appLanguage, "Activity")
        case .recovery: return loc(appLanguage, "Recovery")
        case .joys: return loc(appLanguage, "Joys")
        }
    }
    
    private var categoryColor: Color {
        switch category {
        case .activity: return theme.activityColor
        case .recovery: return theme.recoveryColor
        case .joys: return theme.joysColor
        }
    }
    
    private var selectedCount: Int {
        model.dailySelectionsCount(for: category)
    }
    
    /// Сначала выбранные, потом остальные
    private var orderedOptions: [EnergyOption] {
        let allOptions = model.orderedOptions(for: category)
        
        // Разделяем на выбранные и невыбранные
        let selected = allOptions.filter { model.isDailySelected($0.id, category: category) }
        let notSelected = allOptions.filter { !model.isDailySelected($0.id, category: category) }
        
        return selected + notSelected
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(categoryTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(categoryColor)
                Text(loc(appLanguage, "+5 control each"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(selectedCount)/4")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(orderedOptions) { option in
                        ChoiceCard(
                            model: model,
                            option: option,
                            category: category,
                            categoryColor: categoryColor,
                            appLanguage: appLanguage,
                            onSelect: { optionId in
                                pendingOptionId = optionId
                                showConfirmation = true
                            },
                            onOtherTap: EnergyDefaults.otherOptionIds.contains(option.id) ? { showCustomActivitySheet = true } : nil
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .alert(loc(appLanguage, "Confirm choice"), isPresented: $showConfirmation) {
            Button(loc(appLanguage, "Cancel"), role: .cancel) {
                pendingOptionId = nil
            }
            Button(loc(appLanguage, "Confirm")) {
                if let optionId = pendingOptionId {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        model.toggleDailySelection(optionId: optionId, category: category)
                    }
                }
                pendingOptionId = nil
            }
        } message: {
            Text(loc(appLanguage, "This choice cannot be undone today."))
        }
        .sheet(isPresented: $showCustomActivitySheet) {
            CustomActivitySheet(
                model: model,
                category: category,
                appLanguage: appLanguage,
                onSave: {
                    showCustomActivitySheet = false
                },
                onCancel: {
                    showCustomActivitySheet = false
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(.ultraThinMaterial)
        }
    }
}

// MARK: - Custom Activity Sheet (redesigned)
struct CustomActivitySheet: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @Environment(\.appTheme) private var theme
    
    private let maxCharacters = 30
    
    @State private var activityTitle: String = ""
    @State private var selectedIcon: String = ""
    @FocusState private var isFieldFocused: Bool
    
    private var availableIcons: [String] {
        CustomActivityIcons.icons(for: category)
    }
    
    private var categoryColor: Color {
        switch category {
        case .activity: return theme.activityColor
        case .recovery: return theme.recoveryColor
        case .joys: return theme.joysColor
        }
    }
    
    private var isValid: Bool {
        let trimmed = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !selectedIcon.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Preview Section
                Section {
                    previewCard
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                
                // Name Input Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(loc(appLanguage, "Activity name"), text: $activityTitle)
                            .focused($isFieldFocused)
                            .onChange(of: activityTitle) { _, newValue in
                                if newValue.count > maxCharacters {
                                    activityTitle = String(newValue.prefix(maxCharacters))
                                }
                            }
                        
                        HStack {
                            Spacer()
                            Text("\(activityTitle.count)/\(maxCharacters)")
                                .font(.caption)
                                .foregroundStyle(activityTitle.count >= maxCharacters ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text(loc(appLanguage, "Name"))
                } footer: {
                    Text(loc(appLanguage, "Keep it short and meaningful."))
                }
                
                // Icon Picker Section
                Section {
                    iconGrid
                } header: {
                    Text(loc(appLanguage, "Icon"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(loc(appLanguage, "Add activity"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Add")) {
                        saveActivity()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                selectedIcon = availableIcons.first ?? "pencil"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFieldFocused = true
                }
            }
        }
    }
    
    // MARK: - Preview Card
    private var previewCard: some View {
        HStack {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 96, height: 112)
                
                // Icon background
                Image(systemName: selectedIcon.isEmpty ? "questionmark" : selectedIcon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(categoryColor.opacity(0.2))
                
                // Title
                VStack {
                    Spacer()
                    Text(activityTitle.isEmpty ? loc(appLanguage, "Preview") : activityTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: 96, height: 112)
            
            Spacer()
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Icon Grid
    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
            ForEach(availableIcons, id: \.self) { icon in
                iconButton(icon)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func iconButton(_ icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                selectedIcon = icon
            }
        } label: {
            ZStack {
                Circle()
                    .fill(selectedIcon == icon ? categoryColor : Color(.tertiarySystemFill))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(selectedIcon == icon ? .white : .primary)
            }
            .overlay(
                Circle()
                    .stroke(selectedIcon == icon ? categoryColor : Color.clear, lineWidth: 2)
                    .scaleEffect(1.1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Save
    private func saveActivity() {
        let trimmed = activityTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedIcon.isEmpty else { return }
        
        let id = model.addCustomOption(
            category: category,
            titleEn: trimmed,
            titleRu: trimmed,
            icon: selectedIcon
        )
        
        if !id.isEmpty, model.dailySelectionsCount(for: category) < EnergyDefaults.maxSelectionsPerCategory {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                model.toggleDailySelection(optionId: id, category: category)
            }
        }
        
        onSave()
    }
}

// MARK: - Choice card: tap to select (with confirmation), no deselection until end of day
struct ChoiceCard: View {
    @ObservedObject var model: AppModel
    let option: EnergyOption
    let category: EnergyCategory
    let categoryColor: Color
    let appLanguage: String
    var onSelect: ((String) -> Void)? = nil
    var onOtherTap: (() -> Void)? = nil
    @Environment(\.appTheme) private var theme
    
    private var isOther: Bool {
        EnergyDefaults.otherOptionIds.contains(option.id)
    }
    
    private var isSelected: Bool {
        model.isDailySelected(option.id, category: category)
    }
    
    private var canSelect: Bool {
        !isSelected && model.dailySelectionsCount(for: category) < EnergyDefaults.maxSelectionsPerCategory
    }
    
    var body: some View {
        Button {
            if isOther {
                onOtherTap?()
            } else if canSelect {
                // Вызываем callback для подтверждения
                onSelect?(option.id)
            }
            // Если уже выбрано - ничего не делаем (нельзя снять до конца дня)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .opacity(isSelected ? 1.0 : (canSelect ? 1.0 : 0.5))
    }
    
    private var cardContent: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(theme == .minimal ? theme.backgroundSecondary : (isSelected ? categoryColor : Color(.secondarySystemBackground)))
            
            // Icon as background (centered, behind text)
            Image(systemName: option.icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(theme == .minimal ? theme.textSecondary.opacity(0.3) : (isSelected ? .white.opacity(0.3) : categoryColor.opacity(0.2)))
            
            // Content overlay
            VStack(spacing: 4) {
                Spacer()
                
                // Title at bottom — up to 3 lines; scales down if needed to fit
                Text(option.title(for: appLanguage))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme == .minimal ? theme.textPrimary : (isSelected ? .white : .primary))
                    .strikethrough(isSelected, color: theme == .minimal ? theme.textPrimary : (isSelected ? .white : categoryColor))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            
            // Checkmark overlay
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(theme == .minimal ? theme.textPrimary : .white)
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .frame(width: 96, height: 112)
        .opacity(canSelect ? 1 : 0.5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme == .minimal ? theme.stroke : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Day detail sheet
struct ChoiceDayDetailSheet: View {
    @ObservedObject var model: AppModel
    let dayKey: String
    let snapshot: PastDaySnapshot?
    let appLanguage: String
    let onDismiss: () -> Void
    @Environment(\.appTheme) private var theme

    private var dayLabel: String {
        guard let d = date(from: dayKey) else { return dayKey }
        let f = DateFormatter()
        f.dateStyle = .long
        f.locale = Locale.current
        return f.string(from: d)
    }

    private func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let s = snapshot {
                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            statCard(
                                icon: "figure.walk",
                                value: "\(s.steps)",
                                label: loc(appLanguage, "Steps"),
                                color: .green
                            )
                            statCard(
                                icon: "bed.double.fill",
                                value: String(format: "%.1f", s.sleepHours),
                                label: loc(appLanguage, "Sleep hours"),
                                color: .indigo
                            )
                            statCard(
                                icon: "plus.circle.fill",
                                value: "\(s.controlGained)",
                                label: loc(appLanguage, "Gained"),
                                color: .blue
                            )
                            statCard(
                                icon: "minus.circle.fill",
                                value: "\(s.controlSpent)",
                                label: loc(appLanguage, "Spent"),
                                color: .orange
                            )
                        }
                        
                        // Choices
                        choicesSection(s)
                    } else {
                        Text(loc(appLanguage, "No data for this day."))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(dayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc(appLanguage, "Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func choicesSection(_ s: PastDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            choiceRow(title: loc(appLanguage, "Activity"), ids: s.activityIds, color: theme.activityColor)
            choiceRow(title: loc(appLanguage, "Recovery"), ids: s.recoveryIds, color: theme.recoveryColor)
            choiceRow(title: loc(appLanguage, "Joys"), ids: s.joysIds, color: theme.joysColor)
        }
    }
    
    private func choiceRow(title: String, ids: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            if ids.isEmpty {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        Text(optionTitle(for: id))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(color.opacity(0.15)))
                            .foregroundColor(color)
                    }
                }
            }
        }
    }
    
    private func optionTitle(for id: String) -> String {
        EnergyDefaults.options.first(where: { $0.id == id })?.title(for: appLanguage)
            ?? model.customOptionTitle(for: id, lang: appLanguage)
            ?? id
    }
    
    private func statCard(icon: String, value: String, label: String, color: Color) -> some View {
        let displayColor = theme == .minimal ? theme.textPrimary : color
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(displayColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme == .minimal ? theme.backgroundSecondary : Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

#Preview {
    NavigationStack {
        ChoiceView(model: DIContainer.shared.makeAppModel())
    }
}
