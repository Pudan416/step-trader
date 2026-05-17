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
    @State private var showPaywall = false

    #if DEBUG
    @EnvironmentObject private var coachMarkManager: CoachMarkManager
    @State private var sheetAnchors: [CoachMarkAnchor] = []
    #endif

    @MainActor
    private enum Haptics {
        static let light = UIImpactFeedbackGenerator(style: .light)
        static let medium = UIImpactFeedbackGenerator(style: .medium)
        static let success = UINotificationFeedbackGenerator()

        static func prepareAll() {
            light.prepare()
            medium.prepare()
            success.prepare()
        }
    }

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
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 28)

                if let category {
                    optionList(category: category)
                        .padding(.horizontal, 16)

                    addCustomSection(category: category)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 40)
                } else {
                    outerWorldContent
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .onAppear {
            refreshEntryColorCache()
            Haptics.prepareAll()
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: editingOptionId)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showAddCustom)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(
                model: model,
                store: model.subscriptionStore,
                source: .feature
            )
        }
        #if DEBUG
        .onPreferenceChange(CoachMarkAnchorKey.self) { sheetAnchors = $0 }
        .overlay {
            CoachMarkSheetOverlay(manager: coachMarkManager, anchors: sheetAnchors)
        }
        #endif
    }

    // MARK: - Hero Header

    /// Apple-style hero block: trailing close affordance, large category symbol/asset,
    /// title with rounded display font, secondary progress label. Replaces the old
    /// dense single-row header that crammed icon, title, fraction, dots, and close
    /// into one line.
    private var heroHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .accessibilityLabel(String(localized: "Close", comment: "CategoryDetail – close button VoiceOver label"))
            }

            Image(systemName: categoryIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(accent.opacity(0.6))
                .padding(.top, 2)

            VStack(spacing: 4) {
                Text(categoryTitle)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: selectionCount)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Choose up to 4" before the user picks anything, then "2 of 4 selected" once
    /// any chip is tapped. Clearer than the old "X/Y colors" fraction.
    private var headerSubtitle: String {
        let limit = EnergyDefaults.maxSelectionsPerCategory
        if selectionCount == 0 {
            return String(format: String(localized: "Choose up to %d", comment: "CategoryDetail – initial helper"), limit)
        }
        return String(format: String(localized: "%1$d of %2$d selected", comment: "CategoryDetail – selection progress"), selectionCount, limit)
    }

    // MARK: - Option List (Apple Settings/Reminders style)

    /// Single-column list of options. Built-ins first (in canonical core order), then custom.
    /// Each row is an inline-expandable card — selecting reveals description, examples,
    /// note, color palette, and Save/Remove actions in-place. Replaces the dense
    /// 2-column chip grid + bottom-overlay detail panel.
    private func optionList(category: EnergyCategory) -> some View {
        let custom = model.customOptions(for: category)
        let builtIn = EnergyDefaults.coreOptions.filter { $0.category == category }
        let hidden = model.hiddenOptionIds(for: category)
        let visible = builtIn.filter { !hidden.contains($0.id) }
        let allOptions: [(option: EnergyOption, isCustom: Bool)] =
            visible.map { ($0, false) } + custom.map { ($0, true) }

        return VStack(spacing: 0) {
            ForEach(Array(allOptions.enumerated()), id: \.element.option.id) { index, item in
                let isExpanded = editingOptionId == item.option.id
                optionRow(option: item.option, category: category, isCustom: item.isCustom)
                    #if DEBUG
                    .modifier(FocusingRowAnchor(optionId: item.option.id))
                    #endif

                if !isExpanded && index < allOptions.count - 1 {
                    let nextExpanded = editingOptionId == allOptions[index + 1].option.id
                    if !nextExpanded {
                        Divider()
                            .padding(.leading, 66)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.primary.opacity(0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func optionRow(option: EnergyOption, category: EnergyCategory, isCustom: Bool) -> some View {
        let isSelected = model.isDailySelected(option.id, category: category)
        let isDisabled = !isSelected && model.isDailyLimitReached(for: category)
        let activeColor = getEntryColor(for: option.id)
        let isExpanded = editingOptionId == option.id
        let title = option.title(for: Locale.current.language.languageCode?.identifier ?? "en")

        VStack(spacing: 0) {
            Button {
                handleRowTap(option: option, category: category)
            } label: {
                HStack(spacing: 14) {
                    shapePreviewIcon(
                        category: category,
                        optionId: option.id,
                        color: activeColor,
                        isSelected: isSelected
                    )

                    Text(title)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, activeColor)
                    } else {
                        Circle()
                            .stroke(.secondary.opacity(0.2), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDisabled && !isSelected)
            .opacity(isDisabled && !isSelected ? 0.4 : 1.0)
            .accessibilityIdentifier("category_option_\(option.id)")
            .accessibilityLabel(Text("\(title), \(isSelected ? String(localized: "selected") : String(localized: "not selected"))"))

            if isExpanded {
                expandedOptionDetail(
                    option: option,
                    category: category,
                    isCustom: isCustom,
                    activeColor: activeColor
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .background(isExpanded ? activeColor.opacity(0.05) : .clear)
    }

    /// Tap routing: collapse if expanded, expand if selected, add+expand if not.
    private func handleRowTap(option: EnergyOption, category: EnergyCategory) {
        Haptics.light.impactOccurred()
        Haptics.light.prepare()
        #if DEBUG
        if option.id == "mind_focusing" {
            CoachMarkManager.postAction(for: .spotlightFocusing)
        }
        #endif

        let isSelected = model.isDailySelected(option.id, category: category)

        if editingOptionId == option.id {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                editingOptionId = nil
            }
            isNoteFieldFocused = false
        } else if isSelected {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                openEditor(optionId: option.id, category: category)
            }
        } else {
            let color = CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
            addAndShowDetail(option: option, category: category, color: color)
        }
    }

    // MARK: - Inline Expanded Detail (replaces bottom-overlay panel)

    private func expandedOptionDetail(
        option: EnergyOption,
        category: EnergyCategory,
        isCustom: Bool,
        activeColor: Color
    ) -> some View {
        let examples = EnergyDefaults.examples(for: option.id)
        let exampleList = examples
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let description = EnergyDefaults.description(for: option.id)
        let isSelected = model.isDailySelected(option.id, category: category)

        return VStack(alignment: .leading, spacing: 12) {
            if !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !exampleList.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(exampleList, id: \.self) { example in
                        exampleChip(example: example, optionId: option.id)
                    }
                }
            }

            TextField(
                String(localized: "Add a note...", comment: "OptionEntry – note placeholder"),
                text: $editText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.subheadline)
            .lineLimit(2...4)
            .padding(10)
            .focused($isNoteFieldFocused)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.04))
            )
            .onChange(of: editText) { _, val in
                if val.count > 200 { editText = String(val.prefix(200)) }
            }

            HStack(spacing: 8) {
                if isSelected {
                    Button { removeEntry(optionId: option.id, category: category) } label: {
                        Text(String(localized: "Remove", comment: "CategoryDetail – remove selection"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 36)
                }

                if isCustom {
                    Button { deleteCustomOptionFlow(optionId: option.id) } label: {
                        Text(String(localized: "Delete", comment: "CategoryDetail – delete custom"))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 36)
                    .accessibilityLabel(String(localized: "Delete custom activity"))
                }

                Spacer()

                if isSelected {
                    Button {
                        #if DEBUG
                        if option.id == "mind_focusing" {
                            CoachMarkManager.postAction(for: .tapAddToCanvas)
                        }
                        #endif
                        commitEntry(option: option, category: category, isCustom: isCustom)
                    } label: {
                        Text(String(localized: "Save", comment: "CategoryDetail – primary save action"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(activeColor))
                    }
                    .buttonStyle(.plain)
                    #if DEBUG
                    .modifier(AddToCanvasAnchor(optionId: option.id, isSelected: isSelected))
                    #endif
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func exampleChip(example: String, optionId: String) -> some View {
        Button {
            if editText.isEmpty {
                editText = example
            } else {
                editText += ", \(example)"
            }
            Haptics.light.impactOccurred()
            Haptics.light.prepare()
            #if DEBUG
            if example.lowercased() == "reading" && optionId == "mind_focusing" {
                CoachMarkManager.postAction(for: .spotlightReading)
            }
            #endif
        } label: {
            Text(example)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().stroke(.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        #if DEBUG
        .modifier(ReadingTagAnchor(example: example, optionId: optionId))
        #endif
    }

    private func removeEntry(optionId: String, category: EnergyCategory) {
        withAnimation(.spring(response: 0.3)) {
            model.toggleDailySelection(optionId: optionId, category: category)
            deleteEntry(for: optionId)
            entryColorCache.removeValue(forKey: optionId)
            onActivityUndo?(optionId, category)
            editingOptionId = nil
        }
        isNoteFieldFocused = false
        Haptics.medium.impactOccurred()
        Haptics.medium.prepare()
    }

    private func deleteCustomOptionFlow(optionId: String) {
        withAnimation(.spring(response: 0.3)) {
            model.deleteCustomOption(optionId: optionId)
            if let category {
                onActivityUndo?(optionId, category)
            }
            editingOptionId = nil
        }
        isNoteFieldFocused = false
        Haptics.medium.impactOccurred()
        Haptics.medium.prepare()
    }

    // MARK: - Add Custom Activity

    /// "Add your own" — fourth tile per category. Shown as a dashed-outline row to
    /// hint at "create" affordance (vs. the filled rows above). Free users see a
    /// PRO badge and are routed to the paywall; Pro users open the inline editor.
    @ViewBuilder
    private func addCustomSection(category: EnergyCategory) -> some View {
        if !showAddCustom {
            let canCreate = SubscriptionGate.canCreateCustomActivity(isPro: model.isPro)
            Button {
                if canCreate {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showAddCustom = true
                        editingOptionId = nil
                    }
                } else {
                    showPaywall = true
                }
                Haptics.light.impactOccurred()
                Haptics.light.prepare()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: canCreate ? "plus" : "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(canCreate ? accent : AppColors.brandAccent)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill((canCreate ? accent : AppColors.brandAccent).opacity(0.1))
                        )

                    Text(String(localized: "Add your own", comment: "CategoryDetail – add custom activity button"))
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.6))

                    Spacer(minLength: 0)

                    if !canCreate {
                        Text(String(localized: "PRO", comment: "Pro feature badge"))
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(AppAccentInk.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(AppColors.brandAccent))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            .primary.opacity(0.08),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(canCreate
                ? String(localized: "Add your own activity")
                : String(localized: "Add your own activity, locked, requires Pro"))
        } else {
            customActivityEditor(category: category)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accent.opacity(0.15), lineWidth: 0.5)
                )
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
                    Haptics.light.impactOccurred()
                    Haptics.light.prepare()
                } label: {
                    Image(systemName: customIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(accent.opacity(0.12)))
                }
                .buttonStyle(.plain)

                TextField(
                    String(localized: "Activity name", comment: "CategoryDetail – custom activity name placeholder"),
                    text: $customName
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            }

            let icons = CustomActivityIcons.icons(for: category)
            let iconCols = Array(repeating: GridItem(.flexible(), spacing: 3), count: 10)
            LazyVGrid(columns: iconCols, spacing: 3) {
                ForEach(icons, id: \.self) { icon in
                    let isActive = icon == customIcon
                    Button {
                        customIcon = icon
                        Haptics.light.impactOccurred()
                        Haptics.light.prepare()
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isActive ? accent : .secondary.opacity(0.35))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isActive ? accent.opacity(0.1) : .clear)
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
                        .font(.system(size: 13, weight: .medium, design: .rounded))
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
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
        case .heart: return "heart.fill"
        case nil: return "battery.100.bolt"
        }
    }

    // MARK: - Shape Preview Icon

    /// Deterministic seed from optionId (FNV-1a 64-bit).
    private func stablePreviewSeed(for optionId: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for byte in optionId.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }

    @ViewBuilder
    private func shapePreviewIcon(
        category: EnergyCategory,
        optionId: String,
        color: Color,
        isSelected: Bool
    ) -> some View {
        let seed = stablePreviewSeed(for: optionId)
        let size: CGFloat = 34
        let shape = CanvasShapeType.resolved(for: category)

        Group {
            switch shape {
            case .blob:
                BodyBlobPreview(
                    seed: seed,
                    colors: isSelected
                        ? [color, color.opacity(0.5)]
                        : [.primary.opacity(0.25), .primary.opacity(0.1)]
                )
            case .snowflake:
                RectMorphPreview(
                    seed: seed,
                    color: isSelected ? color : nil
                )
                .opacity(isSelected ? 1.0 : 0.3)
            case .rays:
                SpotlightPreview(
                    seed: seed,
                    overrideColor: isSelected ? color : nil
                )
                .opacity(isSelected ? 1.0 : 0.35)
            case .circle:
                Circle()
                    .fill(
                        RadialGradient(
                            colors: isSelected
                                ? [color, color.opacity(0.3)]
                                : [.primary.opacity(0.25), .primary.opacity(0.08)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.5
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - State Management

    private func openEditor(optionId: String, category: EnergyCategory) {
        showAddCustom = false
        editingOptionId = optionId
        if let entry = loadEntry(for: optionId) {
            editColorHex = entry.colorHex
            editText = entry.text
        } else {
            editColorHex = CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
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
        Haptics.success.notificationOccurred(.success)
        Haptics.success.prepare()
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
        Haptics.success.notificationOccurred(.success)
        Haptics.success.prepare()
        dismiss()
    }

    private func createCustomActivity(category: EnergyCategory) {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let color = CanvasColorPalette.paletteHex.randomElement() ?? AppColors.goldFallbackHex
        let newId = model.addCustomOption(category: category, titleEn: name, titleRu: name, icon: customIcon)
        saveLastUsedPreferences(optionId: newId, colorHex: color)

        let dayKey = AppModel.dayKey(for: Date())
        let entry = OptionEntry(
            id: "\(newId)_\(dayKey)", dayKey: dayKey, optionId: newId,
            category: category, colorHex: color, text: "", timestamp: Date(), assetVariant: nil
        )
        let opt = EnergyOption(id: newId, titleEn: name, titleRu: name, category: category, icon: customIcon)
        saveEntry(entry, for: opt)
        entryColorCache[newId] = Color(hex: color)

        withAnimation(.spring(response: 0.25)) {
            showAddCustom = false
            customName = ""
            customIcon = "pencil"
        }
        Haptics.success.notificationOccurred(.success)
        Haptics.success.prepare()
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
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
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
