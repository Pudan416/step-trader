import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var model: AppModel
    let category: EnergyCategory?
    let outerWorldSteps: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var onActivityConfirmed: ((String, EnergyCategory, String, Int?) -> Void)? = nil
    var onActivityUndo: ((String, EnergyCategory) -> Void)? = nil
    var onReroll: ((String, EnergyCategory) -> Void)? = nil

    @State private var entryColorCache: [String: Color] = [:]
    @State private var showAddCustom = false

    @State private var editingOptionId: String? = nil
    @State private var editColorHex: String = CanvasColorPalette.paletteHex[0]
    @State private var editText: String = ""
    @State private var editSaveForFuture: Bool = false
    @FocusState private var isNoteFieldFocused: Bool

    @State private var customName: String = ""
    @State private var customIcon: String = "pencil"
    @State private var customColorHex: String = CanvasColorPalette.paletteHex[0]

    #if DEBUG
    @EnvironmentObject private var coachMarkManager: CoachMarkManager
    @State private var sheetAnchors: [CoachMarkAnchor] = []
    #endif

    private var accent: Color { category?.color ?? .cyan }

    private var selectionCount: Int {
        guard let category else { return 0 }
        switch category {
        case .body:  return model.dailyActivitySelections.count
        case .mind:  return model.dailyRestSelections.count
        case .heart: return model.dailyJoysSelections.count
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                compactHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 20)

                ScrollView {
                    if let category {
                        chipGrid(category: category)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)

                        addCustomRow(category: category)
                            .padding(.horizontal, 16)
                            .padding(.bottom, editingOptionId != nil ? 280 : 48)
                    } else {
                        outerWorldContent
                            .padding(.horizontal, 16)
                            .padding(.bottom, 48)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if let optionId = editingOptionId, let category {
                detailPanel(optionId: optionId, category: category)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            if #available(iOS 26.0, *) {
                Rectangle().glassEffect(.regular)
            } else {
                Color(.systemBackground).opacity(0.97)
            }
        }
        .onAppear { refreshEntryColorCache() }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: editingOptionId)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showAddCustom)
        #if DEBUG
        .onPreferenceChange(CoachMarkAnchorKey.self) { sheetAnchors = $0 }
        .overlay {
            CoachMarkSheetOverlay(manager: coachMarkManager, anchors: sheetAnchors)
        }
        #endif
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(spacing: 12) {
            categoryAssetImage
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text("\(currentPoints)/\(maxPoints)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(String(localized: "colors", comment: "CategoryDetail – points unit"))
                        .font(.caption.weight(.regular))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            selectionIndicator

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var selectionIndicator: some View {
        let max = EnergyDefaults.maxSelectionsPerCategory
        return HStack(spacing: 3) {
            ForEach(0..<max, id: \.self) { i in
                Circle()
                    .fill(i < selectionCount ? accent : .primary.opacity(0.08))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Chip Grid

    private func chipGrid(category: EnergyCategory) -> some View {
        let custom = model.customOptions(for: category)
        let builtIn = EnergyDefaults.options.filter { $0.category == category }
        let hidden = model.hiddenOptionIds(for: category)
        let visible = builtIn.filter { !hidden.contains($0.id) }
        let allOptions: [(option: EnergyOption, isCustom: Bool)] =
            custom.map { ($0, true) } + visible.map { ($0, false) }

        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(allOptions, id: \.option.id) { item in
                chipView(option: item.option, category: category, isCustom: item.isCustom)
                    #if DEBUG
                    .modifier(FocusingRowAnchor(optionId: item.option.id))
                    #endif
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 20)
    }

    private func chipView(option: EnergyOption, category: EnergyCategory, isCustom: Bool) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let isDisabled = !isSelected && model.isDailyLimitReached(for: category)
        let activeColor = getEntryColor(for: option.id)
        let isEditing = editingOptionId == option.id

        return Button {
            if isSelected {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    if editingOptionId == option.id {
                        editingOptionId = nil
                    } else {
                        openEditor(optionId: option.id, category: category)
                    }
                }
            } else {
                let color = CanvasColorPalette.paletteHex.randomElement()!
                addAndShowDetail(option: option, category: category, color: color)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #if DEBUG
            if option.id == "mind_focusing" {
                CoachMarkManager.postAction(for: .spotlightFocusing)
            }
            #endif
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isSelected ? activeColor : .primary.opacity(0.06))
                    )

                Text(option.title(for: Locale.current.language.languageCode?.identifier ?? "en"))
                    .font(.footnote.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(activeColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? activeColor.opacity(0.18) : .primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isEditing ? activeColor.opacity(0.6) :
                            (isSelected ? activeColor.opacity(0.3) : .primary.opacity(0.1)),
                        lineWidth: isEditing ? 1.5 : 0.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isSelected)
        .opacity(isDisabled && !isSelected ? 0.35 : 1.0)
        .accessibilityIdentifier("category_option_\(option.id)")
        .accessibilityLabel(Text("\(option.title(for: Locale.current.language.languageCode?.identifier ?? "en")), \(isSelected ? String(localized: "selected") : String(localized: "not selected"))"))
    }

    // MARK: - Detail Panel (bottom overlay)

    private func detailPanel(optionId: String, category: EnergyCategory) -> some View {
        let isSelected = model.isDailySelected(optionId, category: category)
        let option = resolveOption(optionId: optionId, category: category)
        let examples = EnergyDefaults.optionDescriptions[optionId]?.examples ?? ""
        let exampleList = examples.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let isCustom = model.customOptions(for: category).contains(where: { $0.id == optionId })

        return VStack(alignment: .leading, spacing: 14) {
            // Drag handle + title
            HStack {
                Capsule()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            HStack {
                if let option {
                    Image(systemName: option.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(option.title(for: Locale.current.language.languageCode?.identifier ?? "en"))
                        .font(.body.weight(.semibold))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25)) { editingOptionId = nil }
                    isNoteFieldFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            // Examples
            if !exampleList.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(exampleList, id: \.self) { example in
                        Button {
                            if editText.isEmpty { editText = example } else { editText += ", \(example)" }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #if DEBUG
                            if example.lowercased() == "reading" && optionId == "mind_focusing" {
                                CoachMarkManager.postAction(for: .spotlightReading)
                            }
                            #endif
                        } label: {
                            Text(example)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        #if DEBUG
                        .modifier(ReadingTagAnchor(example: example, optionId: optionId))
                        #endif
                    }
                }
            }

            // Note field
            TextField(
                String(localized: "Add a note...", comment: "OptionEntry – note placeholder"),
                text: $editText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .padding(10)
            .lineLimit(1...2)
            .frame(minHeight: 36)
            .focused($isNoteFieldFocused)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isNoteFieldFocused ? accent.opacity(0.35) : .clear, lineWidth: 1)
                    )
            )
            .onChange(of: editText) { _, val in
                if val.count > 200 { editText = String(val.prefix(200)) }
            }

            // Actions
            HStack(spacing: 8) {
                if isSelected {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            model.toggleDailySelection(optionId: optionId, category: category)
                            deleteEntry(for: optionId)
                            entryColorCache.removeValue(forKey: optionId)
                            onActivityUndo?(optionId, category)
                            editingOptionId = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.red.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onReroll?(optionId, category)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "dice")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(accent.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }

                if isCustom {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            model.deleteCustomOption(optionId: optionId)
                            onActivityUndo?(optionId, category)
                            editingOptionId = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if isSelected, let option {
                    Button {
                        #if DEBUG
                        if optionId == "mind_focusing" {
                            CoachMarkManager.postAction(for: .tapAddToCanvas)
                        }
                        #endif
                        commitEntry(option: option, category: category, isCustom: isCustom)
                    } label: {
                        Text(String(localized: "Done", comment: "OptionEntry – done button"))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(accent))
                            .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    #if DEBUG
                    .modifier(AddToCanvasAnchor(optionId: optionId, isSelected: isSelected))
                    #endif
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .glassCard(cornerRadius: 20)
        .shadow(color: .black.opacity(0.08), radius: 16, y: -4)
    }

    // MARK: - Add Custom Activity

    @ViewBuilder
    private func addCustomRow(category: EnergyCategory) -> some View {
        if !showAddCustom {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showAddCustom = true
                    editingOptionId = nil
                    customColorHex = CanvasColorPalette.paletteHex.randomElement()!
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(accent.opacity(0.1)))
                    Text(String(localized: "Add your own", comment: "CategoryDetail – add custom activity button"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .glassCard()
        } else {
            customActivityEditor(category: category)
                .glassCard()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func customActivityEditor(category: EnergyCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    let icons = CustomActivityIcons.icons(for: category)
                    if let idx = icons.firstIndex(of: customIcon) {
                        customIcon = icons[(idx + 1) % icons.count]
                    } else {
                        customIcon = icons.first ?? "pencil"
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: customIcon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(hex: customColorHex))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(hex: customColorHex).opacity(0.12)))
                }
                .buttonStyle(.plain)

                TextField(
                    String(localized: "Activity name", comment: "CategoryDetail – custom activity name placeholder"),
                    text: $customName
                )
                .textFieldStyle(.plain)
                .font(.footnote.weight(.medium))
            }

            let icons = CustomActivityIcons.icons(for: category)
            let iconCols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 10)
            LazyVGrid(columns: iconCols, spacing: 3) {
                ForEach(icons, id: \.self) { icon in
                    let isActive = icon == customIcon
                    Button {
                        customIcon = icon
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: icon)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(isActive ? Color(hex: customColorHex) : .secondary.opacity(0.35))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? Color(hex: customColorHex).opacity(0.1) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        showAddCustom = false
                        customName = ""
                    }
                } label: {
                    Text(String(localized: "Cancel", comment: "OptionEntry – dismiss button"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    createCustomActivity(category: category)
                } label: {
                    Text(String(localized: "Create", comment: "CategoryDetail – create custom activity button"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(accent))
                        .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
            }
        }
        .padding(14)
    }

    // MARK: - Outer World

    private var outerWorldContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Collect energy drops by exploring the Outer World", comment: "CategoryDetail – outer world hint text"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    // MARK: - Helpers

    @ViewBuilder
    private var categoryAssetImage: some View {
        let assetName = categoryAssetName
        if let uiImage = UIImage(named: assetName) {
            Image(uiImage: uiImage)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.primary.opacity(0.25))
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: categoryIcon)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary.opacity(0.25))
        }
    }

    private var categoryTitle: String {
        switch category {
        case .body: return String(localized: "Body", comment: "CategoryDetail – energy category name")
        case .mind: return String(localized: "Mind", comment: "CategoryDetail – energy category name")
        case .heart: return String(localized: "Heart", comment: "CategoryDetail – energy category name")
        case nil: return String(localized: "Outer World", comment: "CategoryDetail – location-based category name")
        }
    }

    private var categoryIcon: String {
        switch category {
        case .body: return "figure.run"
        case .mind: return "sparkles"
        case .heart: return "heart"
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

    private func resolveOption(optionId: String, category: EnergyCategory) -> EnergyOption? {
        if let opt = EnergyDefaults.options.first(where: { $0.id == optionId }) { return opt }
        if let custom = model.customOptions(for: category).first(where: { $0.id == optionId }) {
            return EnergyOption(id: custom.id, titleEn: custom.titleEn, titleRu: custom.titleRu, category: custom.category, icon: custom.icon)
        }
        return nil
    }

    // MARK: - State Management

    private func openEditor(optionId: String, category: EnergyCategory) {
        showAddCustom = false
        editingOptionId = optionId
        if let entry = loadEntry(for: optionId) {
            editColorHex = entry.colorHex
            editText = entry.text
        } else {
            editColorHex = CanvasColorPalette.paletteHex.randomElement()!
            editText = ""
        }
        editSaveForFuture = false
    }

    private func addAndShowDetail(option: EnergyOption, category: EnergyCategory, color: String) {
        let dayKey = AppModel.dayKey(for: Date())
        let entry = OptionEntry(
            id: "\(option.id)_\(dayKey)", dayKey: dayKey, optionId: option.id,
            category: category, colorHex: color, text: "", timestamp: Date(), assetVariant: nil
        )
        saveEntry(entry, for: option)
        entryColorCache[option.id] = Color(hex: color)
        saveLastUsedPreferences(optionId: option.id, colorHex: color)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #if DEBUG
        if option.id == "mind_focusing" {
            CoachMarkManager.postAction(for: .tapAddToCanvas)
        }
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            editColorHex = color
            editText = ""
            editSaveForFuture = false
            editingOptionId = option.id
        }
    }

    private func commitEntry(option: EnergyOption, category: EnergyCategory, isCustom: Bool) {
        let dayKey = AppModel.dayKey(for: Date())
        let newEntry = OptionEntry(
            id: "\(option.id)_\(dayKey)", dayKey: dayKey, optionId: option.id,
            category: category, colorHex: editColorHex,
            text: editText.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date(), assetVariant: nil
        )
        saveEntry(newEntry, for: option)
        entryColorCache[option.id] = Color(hex: editColorHex)
        saveLastUsedPreferences(optionId: option.id, colorHex: editColorHex)

        if editSaveForFuture && !isCustom {
            let cleanName = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespacesAndNewlines).capitalized ?? ""
            if !cleanName.isEmpty {
                let newId = model.addCustomOption(category: category, titleEn: cleanName, titleRu: cleanName, icon: option.icon)
                saveLastUsedPreferences(optionId: newId, colorHex: editColorHex)
            }
        }

        withAnimation(.spring(response: 0.25)) { editingOptionId = nil }
        isNoteFieldFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func createCustomActivity(category: EnergyCategory) {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let newId = model.addCustomOption(category: category, titleEn: name, titleRu: name, icon: customIcon)
        saveLastUsedPreferences(optionId: newId, colorHex: customColorHex)

        let dayKey = AppModel.dayKey(for: Date())
        let entry = OptionEntry(
            id: "\(newId)_\(dayKey)", dayKey: dayKey, optionId: newId,
            category: category, colorHex: customColorHex, text: "", timestamp: Date(), assetVariant: nil
        )
        let opt = EnergyOption(id: newId, titleEn: name, titleRu: name, category: category, icon: customIcon)
        saveEntry(entry, for: opt)
        entryColorCache[newId] = Color(hex: customColorHex)

        withAnimation(.spring(response: 0.25)) {
            showAddCustom = false
            customName = ""
            customIcon = "pencil"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: - Entry Persistence

    private func loadEntry(for optionId: String) -> OptionEntry? {
        let dayKey = AppModel.dayKey(for: Date())
        let entryId = "\(optionId)_\(dayKey)"
        let g = UserDefaults.stepsTrader()
        guard let data = g.data(forKey: "option_entry_\(entryId)"),
              let entry = try? JSONDecoder().decode(OptionEntry.self, from: data) else { return nil }
        return entry
    }

    private func saveEntry(_ entry: OptionEntry, for option: EnergyOption) {
        guard let category else { return }
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.stepsTrader().set(data, forKey: "option_entry_\(entry.id)")
        }
        if !model.isDailySelected(option.id, category: category) {
            model.toggleDailySelection(optionId: option.id, category: category)
        }
        onActivityConfirmed?(option.id, category, entry.colorHex, entry.assetVariant)
        syncTodayEntriesToSupabase()
    }

    private func syncTodayEntriesToSupabase() {
        guard let cat = category else { return }
        let allOpts = model.orderedOptions(for: cat)
        let dayKey = AppModel.dayKey(for: Date())
        var entries: [OptionEntry] = []
        let g = UserDefaults.stepsTrader()
        for opt in allOpts {
            let entryId = "\(opt.id)_\(dayKey)"
            if let data = g.data(forKey: "option_entry_\(entryId)"),
               let entry = try? JSONDecoder().decode(OptionEntry.self, from: data) {
                entries.append(entry)
            }
        }
        guard !entries.isEmpty else { return }
        Task { await SupabaseSyncService.shared.syncOptionEntries(entries) }
    }

    private func deleteEntry(for optionId: String) {
        let dayKey = AppModel.dayKey(for: Date())
        let entryId = "\(optionId)_\(dayKey)"
        UserDefaults.stepsTrader().removeObject(forKey: "option_entry_\(entryId)")
    }

    private func getEntryColor(for optionId: String) -> Color {
        if let cached = entryColorCache[optionId] { return cached }
        if let entry = loadEntry(for: optionId) { return Color(hex: entry.colorHex) }
        return lastUsedColor(for: optionId) ?? accent
    }

    private func refreshEntryColorCache() {
        guard let cat = category else { return }
        var cache: [String: Color] = [:]
        let allOpts = model.orderedOptions(for: cat)
        for option in allOpts {
            if let entry = loadEntry(for: option.id) {
                cache[option.id] = Color(hex: entry.colorHex)
            } else if let saved = lastUsedColor(for: option.id) {
                cache[option.id] = saved
            } else {
                cache[option.id] = cat.color
            }
        }
        entryColorCache = cache
    }

    // MARK: - Last-Used Preferences

    private func saveLastUsedPreferences(optionId: String, colorHex: String) {
        UserDefaults.stepsTrader().set(colorHex, forKey: "lastColor_\(optionId)")
    }

    private func lastUsedColor(for optionId: String) -> Color? {
        guard let hex = UserDefaults.stepsTrader().string(forKey: "lastColor_\(optionId)") else { return nil }
        return Color(hex: hex)
    }

}

// MARK: - Checkbox Toggle Style

private struct CheckboxToggleStyle: ToggleStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(configuration.isOn ? tint : .secondary.opacity(0.35))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coach Mark Anchors (DEBUG)

#if DEBUG
private struct FocusingRowAnchor: ViewModifier {
    let optionId: String
    func body(content: Content) -> some View {
        if optionId == "mind_focusing" {
            content.coachMarkAnchor(.spotlightFocusing)
        } else {
            content
        }
    }
}

private struct ReadingTagAnchor: ViewModifier {
    let example: String
    let optionId: String
    func body(content: Content) -> some View {
        if example.lowercased() == "reading" && optionId == "mind_focusing" {
            content.coachMarkAnchor(.spotlightReading)
        } else {
            content
        }
    }
}

private struct AddToCanvasAnchor: ViewModifier {
    let optionId: String
    let isSelected: Bool
    func body(content: Content) -> some View {
        if optionId == "mind_focusing" {
            content.coachMarkAnchor(.tapAddToCanvas)
        } else {
            content
        }
    }
}
#endif
