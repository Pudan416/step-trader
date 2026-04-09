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

    @State private var expandedOptionId: String? = nil
    @State private var entryColorCache: [String: Color] = [:]
    @State private var showAddCustom = false

    @State private var editColorHex: String = CanvasColorPalette.paletteHex[0]
    @State private var editText: String = ""
    @State private var editSaveForFuture: Bool = false
    @FocusState private var isNoteFieldFocused: Bool

    @State private var customName: String = ""
    @State private var customIcon: String = "pencil"
    @State private var customColorHex: String = CanvasColorPalette.paletteHex[0]

    private var accent: Color { category?.color ?? .cyan }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection

                    if let category {
                        activityList(category: category)
                        addCustomRow(category: category)
                    } else {
                        outerWorldContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
            .energyGradientBackground(model: model)
            .navigationTitle(categoryTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .onAppear { refreshEntryColorCache() }
    }

    // MARK: - Title

    private var categoryTitle: String {
        switch category {
        case .body: return String(localized: "Body", comment: "CategoryDetail – energy category name")
        case .mind: return String(localized: "Mind", comment: "CategoryDetail – energy category name")
        case .heart: return String(localized: "Heart", comment: "CategoryDetail – energy category name")
        case nil: return String(localized: "Outer World", comment: "CategoryDetail – location-based category name")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 16) {
            categoryAssetImage
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(currentPoints)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text("/\(maxPoints)")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(String(localized: "colors earned", comment: "CategoryDetail – points subtitle"))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.7))
            }

            Spacer()
        }
        .padding(16)
        .glassCard()
    }

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
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.primary.opacity(0.25))
        }
    }

    // MARK: - Activity List (unified: personal + built-in)

    @ViewBuilder
    private func activityList(category: EnergyCategory) -> some View {
        let custom = model.customOptions(for: category)
        let builtIn = EnergyDefaults.options.filter { $0.category == category }
        let hidden = model.hiddenOptionIds(for: category)
        let visible = builtIn.filter { !hidden.contains($0.id) }

        VStack(spacing: 0) {
            // Personal activities
            if !custom.isEmpty {
                ForEach(Array(custom.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { divider }
                    activityRow(option: option, category: category, isCustom: true)
                    if expandedOptionId == option.id {
                        inlineEditor(option: option, category: category, isCustom: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Separator between personal and built-in
                HStack {
                    Rectangle().fill(.secondary.opacity(0.15)).frame(height: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            // Built-in activities
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, option in
                if index > 0 { divider }
                activityRow(option: option, category: category, isCustom: false)
                if expandedOptionId == option.id {
                    inlineEditor(option: option, category: category, isCustom: false)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .glassCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    // MARK: - Activity Row

    private func activityRow(option: EnergyOption, category: EnergyCategory, isCustom: Bool) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let isDisabled = !isSelected && model.isDailyLimitReached(for: category)
        let activeColor = getEntryColor(for: option.id)

        return Button {
            if isCustom && !isSelected {
                quickAdd(option: option, category: category, color: CanvasColorPalette.paletteHex.randomElement()!)
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    toggleExpand(option.id, category: category)
                }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(isSelected ? activeColor : .primary.opacity(0.07))
                    )

                Text(option.title(for: Locale.current.language.languageCode?.identifier ?? "en"))
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(activeColor)
                } else if expandedOptionId == option.id {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.35))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isSelected)
        .opacity(isDisabled && !isSelected ? 0.3 : 1.0)
        .accessibilityLabel(Text("\(option.title(for: Locale.current.language.languageCode?.identifier ?? "en")), \(isSelected ? String(localized: "selected") : String(localized: "not selected"))"))
    }

    // MARK: - Inline Editor

    @ViewBuilder
    private func inlineEditor(option: EnergyOption, category: EnergyCategory, isCustom: Bool) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let examples = EnergyDefaults.optionDescriptions[option.id]?.examples ?? ""
        let exampleList = examples.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        VStack(alignment: .leading, spacing: 16) {
            // Examples
            if !exampleList.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(exampleList, id: \.self) { example in
                        Button {
                            if editText.isEmpty { editText = example } else { editText += ", \(example)" }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Text(example)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
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
            .padding(12)
            .lineLimit(1...3)
            .frame(minHeight: 40)
            .focused($isNoteFieldFocused)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isNoteFieldFocused ? Color(hex: editColorHex).opacity(0.35) : .clear, lineWidth: 1)
                    )
            )
            .onChange(of: editText) { _, val in
                if val.count > 200 { editText = String(val.prefix(200)) }
            }

            // Save for future
            if !isCustom {
                let cleanName = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: ",").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if cleanName.count >= 2 && cleanName.count <= 40 {
                    Toggle(isOn: $editSaveForFuture) {
                        Text(String(localized: "Save \"\(cleanName.capitalized)\" for later", comment: "CategoryDetail – save custom activity toggle"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .toggleStyle(CheckboxToggleStyle(tint: Color(hex: editColorHex)))
                }
            }

            // Color grid only for editing an already-added entry (not for initial add)
            if isSelected {
                colorGrid(binding: $editColorHex)
            }

            // Actions
            HStack(spacing: 10) {
                if isSelected {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            model.toggleDailySelection(optionId: option.id, category: category)
                            deleteEntry(for: option.id)
                            entryColorCache.removeValue(forKey: option.id)
                            onActivityUndo?(option.id, category)
                            expandedOptionId = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.red.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onReroll?(option.id, category)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "dice")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                if isCustom {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            model.deleteCustomOption(optionId: option.id)
                            onActivityUndo?(option.id, category)
                            expandedOptionId = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    commitEntry(option: option, category: category, isCustom: isCustom)
                } label: {
                    let buttonColor = isSelected ? Color(hex: editColorHex) : accent
                    Text(isSelected
                         ? String(localized: "Save", comment: "OptionEntry – save/add button")
                         : String(localized: "Add to canvas", comment: "OptionEntry – add to canvas button"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(buttonColor))
                        .shadow(color: buttonColor.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.primary.opacity(0.02))
    }

    // MARK: - Color Grid (reusable)

    private func colorGrid(binding: Binding<String>) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(CanvasColorPalette.paletteHex.enumerated()), id: \.offset) { _, hex in
                let isActive = hex == binding.wrappedValue
                Button {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) { binding.wrappedValue = hex }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle().stroke(.white.opacity(isActive ? 0.9 : 0), lineWidth: 2)
                                .padding(-1)
                        )
                        .overlay(
                            Circle().stroke(Color(hex: hex).opacity(isActive ? 0.5 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                        .scaleEffect(isActive ? 1.1 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Add Custom Activity

    @ViewBuilder
    private func addCustomRow(category: EnergyCategory) -> some View {
        if !showAddCustom {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    showAddCustom = true
                    expandedOptionId = nil
                    customColorHex = CanvasColorPalette.paletteHex.randomElement()!
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(accent.opacity(0.1)))
                    Text(String(localized: "Add your own", comment: "CategoryDetail – add custom activity button"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 16) {
            // Name field
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: customColorHex))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(hex: customColorHex).opacity(0.12)))
                }
                .buttonStyle(.plain)

                TextField(
                    String(localized: "Activity name", comment: "CategoryDetail – custom activity name placeholder"),
                    text: $customName
                )
                .textFieldStyle(.plain)
                .font(.subheadline.weight(.medium))
            }

            // Icon grid
            let icons = CustomActivityIcons.icons(for: category)
            let iconCols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)
            LazyVGrid(columns: iconCols, spacing: 4) {
                ForEach(icons, id: \.self) { icon in
                    let isActive = icon == customIcon
                    Button {
                        customIcon = icon
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isActive ? Color(hex: customColorHex) : .secondary.opacity(0.4))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? Color(hex: customColorHex).opacity(0.1) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Actions
            HStack {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        showAddCustom = false
                        customName = ""
                    }
                } label: {
                    Text(String(localized: "Cancel", comment: "OptionEntry – dismiss button"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    createCustomActivity(category: category)
                } label: {
                    Text(String(localized: "Create", comment: "CategoryDetail – create custom activity button"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(accent))
                        .shadow(color: accent.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0)
            }
        }
        .padding(16)
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

    // MARK: - State Management

    private func toggleExpand(_ optionId: String, category: EnergyCategory) {
        if expandedOptionId == optionId {
            expandedOptionId = nil
            isNoteFieldFocused = false
        } else {
            showAddCustom = false
            expandedOptionId = optionId
            if let entry = loadEntry(for: optionId) {
                editColorHex = entry.colorHex
                editText = entry.text
            } else {
                editColorHex = CanvasColorPalette.paletteHex.randomElement()!
                editText = ""
            }
            editSaveForFuture = false
        }
    }

    private func quickAdd(option: EnergyOption, category: EnergyCategory, color: String) {
        let dayKey = AppModel.dayKey(for: Date())
        let entry = OptionEntry(
            id: "\(option.id)_\(dayKey)", dayKey: dayKey, optionId: option.id,
            category: category, colorHex: color, text: "", timestamp: Date(), assetVariant: nil
        )
        saveEntry(entry, for: option)
        entryColorCache[option.id] = Color(hex: color)
        saveLastUsedPreferences(optionId: option.id, colorHex: color)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

        withAnimation(.spring(response: 0.25)) { expandedOptionId = nil }
        isNoteFieldFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(configuration.isOn ? tint : .secondary.opacity(0.35))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
