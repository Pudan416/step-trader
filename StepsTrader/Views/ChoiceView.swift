import SwiftUI

// MARK: - GALLERY tab: today's gallery with stats header
struct GalleryView: View {
    @ObservedObject var model: AppModel
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var breakdownCategory: EnergyCategory?
    
    private var pageBackground: Color {
        theme.backgroundColor
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        // Category rows
                        CategoryCardsRow(
                            model: model,
                            category: .activity,
                            appLanguage: appLanguage
                        )
                        CategoryCardsRow(
                            model: model,
                            category: .creativity,
                            appLanguage: appLanguage
                        )
                        CategoryCardsRow(
                            model: model,
                            category: .joys,
                            appLanguage: appLanguage
                        )
                    }
                    .padding(.bottom, 140)
                }
            }
            .background(pageBackground)
            .navigationBarHidden(true)
            
            if let category = breakdownCategory {
                breakdownOverlay(category: category)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: breakdownCategory != nil)
    }
    
    private func breakdownOverlay(category: EnergyCategory) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { breakdownCategory = nil }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(breakdownTitle(for: category))
                        .font(.headline)
                    Spacer()
                    Button {
                        breakdownCategory = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text(breakdownText(for: category))
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.backgroundSecondary)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
    
    private func breakdownTitle(for category: EnergyCategory) -> String {
        switch category {
        case .activity:
            return appLanguage == "ru" ? "Активность" : "Activity"
        case .creativity:
            return appLanguage == "ru" ? "Творчество" : "Creativity"
        case .joys:
            return appLanguage == "ru" ? "Удовольствия" : "Joys"
        }
    }
    
    private func breakdownText(for category: EnergyCategory) -> String {
        switch category {
        case .activity:
            let steps = Int(model.stepsToday)
            let extras = selectionTitles(for: .activity)
            let extraText = extras.isEmpty ? "" : (appLanguage == "ru" ? " и еще занялся \(extras.joined(separator: ", "))" : ". As an activity, I was \(extras.joined(separator: ", "))")
            let total = model.activityPointsToday
            if appLanguage == "ru" {
                return "Сегодня я сделал \(steps) шагов\(extraText), что в сумме принесло мне \(total) баллов опыта."
            }
            return "Today I made \(steps) steps\(extraText). All of these brought me \(total) experience points in total."
        case .creativity:
            let extras = selectionTitles(for: .creativity)
            let total = model.creativityPointsToday
            if extras.isEmpty {
                if appLanguage == "ru" {
                    return "Сегодня я не выбирал творчество, что принесло мне \(total) баллов опыта."
                }
                return "Today I didn't choose any creativity, which brought me \(total) experience points."
            } else {
                let extraText = extras.joined(separator: ", ")
                if appLanguage == "ru" {
                    return "Сегодня я выбрал \(extraText), что принесло мне \(total) баллов опыта."
                }
                return "Today I chose \(extraText), which brought me \(total) experience points."
            }
        case .joys:
            let sleep = formatSleep(model.dailySleepHours)
            let extras = selectionTitles(for: .joys)
            let total = model.joysCategoryPointsToday
            if extras.isEmpty {
                if appLanguage == "ru" {
                    return "Сегодня я поспал \(sleep), и не выбирал удовольствия, что принесло мне \(total) баллов опыта."
                }
                return "Today I slept \(sleep) and didn't choose any joys, which brought me \(total) experience points."
            } else {
                let extraText = extras.joined(separator: ", ")
                if appLanguage == "ru" {
                    return "Сегодня я поспал \(sleep) и выбрал \(extraText), что принесло мне \(total) баллов опыта."
                }
                return "Today I slept \(sleep) and chose \(extraText), which brought me \(total) experience points."
            }
        }
    }
    
    private func selectionTitles(for category: EnergyCategory) -> [String] {
        let ids: [String]
        switch category {
        case .activity: ids = model.dailyActivitySelections
        case .creativity: ids = model.dailyRestSelections
        case .joys: ids = model.dailyJoysSelections
        }
        return ids.map { id in
            EnergyDefaults.options.first(where: { $0.id == id })?.title(for: appLanguage)
                ?? model.customOptionTitle(for: id, lang: appLanguage)
                ?? id
        }
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
        let today = AppModel.currentDayStartForDefaults(Date())
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
                            .font(.notoSerif(17, weight: .semibold))
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
        case .activity: return loc(appLanguage, "My activities")
        case .creativity: return loc(appLanguage, "My creativity")
        case .joys: return loc(appLanguage, "My joys")
        }
    }
    
    private var categoryColor: Color { .primary }
    
    private var selectedCount: Int {
        model.dailySelectionsCount(for: category)
    }
    
    /// Сначала выбранные, потом остальные; без "Something else" / "Other"
    private var orderedOptions: [EnergyOption] {
        let allOptions = model.orderedOptions(for: category)
            .filter { !EnergyDefaults.otherOptionIds.contains($0.id) }
        let selected = allOptions.filter { model.isDailySelected($0.id, category: category) }
        let notSelected = allOptions.filter { !model.isDailySelected($0.id, category: category) }
        return selected + notSelected
    }
    
    @State private var showCategoryEditSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(categoryTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(categoryColor)
                Text(loc(appLanguage, "+5 exp. each"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    showCategoryEditSheet = true
                } label: {
                    Text(loc(appLanguage, "Edit"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Text("\(selectedCount)/4")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(orderedOptions) { option in
                        GalleryCard(
                            model: model,
                            option: option,
                            category: category,
                            categoryColor: categoryColor,
                            appLanguage: appLanguage,
                            onSelect: { optionId in
                                pendingOptionId = optionId
                                showConfirmation = true
                            },
                            onOtherTap: nil
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .alert(loc(appLanguage, "Confirm selection"), isPresented: $showConfirmation) {
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
            Text(loc(appLanguage, "This selection cannot be undone today."))
        }
        .sheet(isPresented: $showCategoryEditSheet) {
            CategoryEditSheet(
                model: model,
                category: category,
                appLanguage: appLanguage,
                onDismiss: { showCategoryEditSheet = false }
            )
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
        case .creativity: return theme.restColor
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
                    .frame(width: 84, height: 100)
                
                // Icon background
                Image(systemName: selectedIcon.isEmpty ? "questionmark" : selectedIcon)
                    .font(.notoSerif(28, weight: .light))
                    .foregroundColor(categoryColor.opacity(0.2))
                
                // Title
                VStack {
                    Spacer()
                    Text(activityTitle.isEmpty ? loc(appLanguage, "Preview") : activityTitle)
                        .font(.notoSerif(10, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: 84, height: 100)
            
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    // MARK: - Icon Grid
    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(availableIcons, id: \.self) { icon in
                iconButton(icon)
            }
        }
        .padding(.vertical, 6)
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
                    .frame(width: 42, height: 42)
                
                Image(systemName: icon)
                    .font(.notoSerif(18))
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

// MARK: - Gallery card: tap to select (with confirmation), no deselection until end of day
struct GalleryCard: View {
    @ObservedObject var model: AppModel
    let option: EnergyOption
    let category: EnergyCategory
    let categoryColor: Color
    let appLanguage: String
    var onSelect: ((String) -> Void)? = nil
    var onOtherTap: (() -> Void)? = nil
    @Environment(\.appTheme) private var theme
    @State private var showUndoPrompt = false
    
    private var isOther: Bool {
        EnergyDefaults.otherOptionIds.contains(option.id)
    }
    
    private var isSelected: Bool {
        model.isDailySelected(option.id, category: category)
    }
    
    private var canSelect: Bool {
        !isSelected && model.dailySelectionsCount(for: category) < EnergyDefaults.maxSelectionsPerCategory
    }

    private let referenceImages = ["refpic1", "refpic2", "refpic3", "refpic4", "refpic5", "refpic6", "refpic7"]
    private let crossImages = ["cross1", "cross2", "cross3"]
    private let frameImages = ["frame-1", "frame-2", "frame-3", "frame-4"]
    
    /// Stable per-option frame so the same card always gets the same frame.
    private var frameImageName: String {
        let sum = option.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return frameImages[sum % frameImages.count]
    }
    
    /// Picture scale so it fills the frame opening (minimal mat visible).
    private static let pictureInsetScale: CGFloat = 0.836  // 0.88 * 0.95 (5% smaller)
    
    /// Asset name for card image: same logic as settings — option.id or option.icon if in Assets, else fallback.
    private var cardAssetName: String? {
        if UIImage(named: option.id) != nil { return option.id }
        if UIImage(named: option.icon) != nil { return option.icon }
        return nil
    }
    
    /// Fallback image name when no asset (refpic for rest/joys, refpic by hash for consistency).
    private var fallbackReferenceImageName: String {
        if category == .activity { return option.id }
        let sum = option.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return referenceImages[sum % referenceImages.count]
    }
    
    private var crossImageName: String {
        let sum = option.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let idx = sum % crossImages.count
        return crossImages[idx]
    }
    
    var body: some View {
        Button {
            if isOther {
                onOtherTap?()
            } else if isSelected {
                showUndoPrompt = true
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
        .alert(loc(appLanguage, "Undo this action?"), isPresented: $showUndoPrompt) {
            Button(loc(appLanguage, "Cancel"), role: .cancel) {}
            Button(loc(appLanguage, "Undo")) {
                model.toggleDailySelection(optionId: option.id, category: category)
            }
        } message: {
            Text(loc(appLanguage, "This will remove the completion mark."))
        }
    }
    
    private var cardContent: some View {
        ZStack {
            VStack(spacing: 5) {
                cardMainImage
                
                Text(option.title(for: appLanguage))
                    .font(.notoSerif(12, weight: .medium))
                    .foregroundColor(theme.textPrimary.opacity(isSelected ? 0.45 : 1.0))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            
            if isSelected {
                Image(crossImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
            }
        }
        .frame(width: 118, height: 180)
        .opacity(canSelect ? 1 : 0.5)
    }
    
    @ViewBuilder
    private var cardMainImage: some View {
        let imageSize: CGFloat = 110
        let innerSize = imageSize * Self.pictureInsetScale
        ZStack {
            Group {
                if let name = cardAssetName, let uiImage = UIImage(named: name) ?? UIImage(named: name.lowercased()) ?? UIImage(named: name.capitalized) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else if category == .activity {
                    Image(systemName: option.icon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                } else {
                    Image(fallbackReferenceImageName)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: innerSize, height: innerSize)
            Image(frameImageName)
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
        }
        .frame(width: imageSize, height: imageSize)
    }
}

/// Represents which option is being edited (base or custom)
private struct CategoryEditTarget: Identifiable {
    let option: EnergyOption
    var id: String { option.id }
}

// MARK: - Category Edit Sheet (create, delete, edit items)
struct CategoryEditSheet: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory
    let appLanguage: String
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    
    @State private var optionToDelete: String? = nil
    @State private var editTarget: CategoryEditTarget? = nil
    @State private var showAddEditor = false
    
    private var categoryTitle: String {
        switch category {
        case .activity: return loc(appLanguage, "My activities")
        case .creativity: return loc(appLanguage, "My creativity")
        case .joys: return loc(appLanguage, "My joys")
        }
    }
    
    private var categoryColor: Color {
        switch category {
        case .activity: return theme.activityColor
        case .creativity: return theme.restColor
        case .joys: return theme.joysColor
        }
    }
    
    private var options: [EnergyOption] {
        model.orderedOptions(for: category)
            .filter { !EnergyDefaults.otherOptionIds.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(options) { option in
                    optionRow(option: option)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc(appLanguage, "Done")) {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(loc(appLanguage, "Add")) {
                        showAddEditor = true
                    }
                }
            }
            .sheet(isPresented: $showAddEditor) {
                CustomActivityEditorView(
                    category: category,
                    appLanguage: appLanguage,
                    initialTitle: nil,
                    initialIcon: nil,
                    isEditing: false
                ) { title, icon in
                    _ = model.addCustomOption(category: category, titleEn: title, titleRu: title, icon: icon)
                    showAddEditor = false
                }
            }
            .sheet(item: $editTarget) { target in
                CustomActivityEditorView(
                    category: category,
                    appLanguage: appLanguage,
                    initialTitle: target.option.title(for: appLanguage),
                    initialIcon: target.option.icon,
                    isEditing: true
                ) { title, icon in
                    if target.option.id.hasPrefix("custom_") {
                        model.updateCustomOption(optionId: target.option.id, titleEn: title, titleRu: title, icon: icon)
                    } else {
                        model.replaceOptionWithCustom(optionId: target.option.id, category: category, titleEn: title, titleRu: title, icon: icon)
                    }
                    editTarget = nil
                }
            }
            .alert(loc(appLanguage, "Delete item?"), isPresented: Binding(
                get: { optionToDelete != nil },
                set: { if !$0 { optionToDelete = nil } }
            )) {
                Button(loc(appLanguage, "Cancel"), role: .cancel) {
                    optionToDelete = nil
                }
                Button(loc(appLanguage, "Delete"), role: .destructive) {
                    if let id = optionToDelete {
                        model.deleteOption(optionId: id)
                    }
                    optionToDelete = nil
                }
            } message: {
                Text(loc(appLanguage, "This cannot be undone."))
            }
        }
    }
    
    private func optionRow(option: EnergyOption) -> some View {
        HStack(spacing: 12) {
            optionThumbnail(option: option)
            
            Text(option.title(for: appLanguage))
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                editTarget = CategoryEditTarget(option: option)
            } label: {
                Image(systemName: "pencil")
                    .font(.body)
                    .foregroundColor(categoryColor)
            }
            .buttonStyle(.plain)
            
            Button {
                optionToDelete = option.id
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    /// Shows image from Assets (option.id or option.icon) when available, otherwise SF Symbol
    private func optionThumbnail(option: EnergyOption) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(categoryColor.opacity(0.15))
                .frame(width: 44, height: 44)
            
            if let name = assetImageName(for: option),
               let uiImage = UIImage(named: name) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundColor(categoryColor)
            }
        }
    }
    
    private func assetImageName(for option: EnergyOption) -> String? {
        if UIImage(named: option.id) != nil { return option.id }
        if UIImage(named: option.icon) != nil { return option.icon }
        return nil
    }
}

// MARK: - Day detail sheet
struct GalleryDayDetailSheet: View {
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
                        
                        // Gallery
                        gallerySection(s)
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
            .background(theme.backgroundColor)
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
    
    private func gallerySection(_ s: PastDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            galleryRow(title: loc(appLanguage, "Activity"), ids: s.activityIds, color: theme.activityColor)
            galleryRow(title: loc(appLanguage, "Creativity"), ids: s.creativityIds, color: theme.restColor)
            galleryRow(title: loc(appLanguage, "Joys"), ids: s.joysIds, color: theme.joysColor)
        }
    }
    
    private func galleryRow(title: String, ids: [String], color: Color) -> some View {
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
        GalleryView(model: DIContainer.shared.makeAppModel(), breakdownCategory: .constant(nil))
    }
}
