import SwiftUI

struct CanvasAppearancePresentation: Equatable {
    let showsModernPalettes: Bool
    let showsLegacyControls: Bool

    init(style: CanvasVisualStyle) {
        showsModernPalettes = style == .editorial
        showsLegacyControls = style == .legacy
    }
}

struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @State private var draft = SettingsAppearanceDraft.load()
    @State private var original = SettingsAppearanceDraft.load()
    @State private var showDiscard = false
    @Environment(\.dismiss) private var dismiss
    private var gradientStyleRaw: String {
        get { draft.style }
        nonmutating set { draft.style = newValue }
    }
    private var gradientPaletteRaw: String {
        get { draft.palette }
        nonmutating set { draft.palette = newValue }
    }
    private var dailyRandomThemeEnabled: Bool {
        get { draft.automatic }
        nonmutating set { draft.automatic = newValue }
    }
    private var canvasTextureRaw: String {
        get { draft.texture }
        nonmutating set { draft.texture = newValue }
    }
    private var modernPaletteCategoriesRaw: String {
        get { draft.categories }
        nonmutating set { draft.categories = newValue }
    }
    private var canvasVisualStyleRaw: String {
        get { draft.canvasStyle }
        nonmutating set { draft.canvasStyle = newValue }
    }
    private var allowedShapes: Set<CanvasShapeType> {
        get { draft.shapes }
        nonmutating set { draft.shapes = newValue }
    }
    private var allowedFills: Set<TextureKind> {
        get { draft.fills }
        nonmutating set { draft.fills = newValue }
    }

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCanvasIngredientsExpanded = false
    @State private var lightHapticTick = 0
    @State private var mediumHapticTick = 0

    private var selectedPalette: GradientPalette {
        GradientPalette.normalized(rawValue: gradientPaletteRaw)
    }

    private var selectedStyle: GradientStyle {
        GradientStyle(rawValue: gradientStyleRaw) ?? .radial
    }

    private var activePalette: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: selectedPalette)
    }

    private var appearanceMode: SettingsAppearanceMode {
        SettingsAppearanceMode(dailyRandomEnabled: dailyRandomThemeEnabled)
    }

    private var appearanceModeBinding: Binding<SettingsAppearanceMode> {
        Binding(
            get: { appearanceMode },
            set: { mode in
                guard mode.dailyRandomEnabled != dailyRandomThemeEnabled else { return }
                withMotionAnimation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    reduceMotion: reduceMotion
                ) {
                    draft.setAutomatic(mode.dailyRandomEnabled)
                }
                lightHapticTick &+= 1
            }
        )
    }

    private var canvasIngredientsBinding: Binding<Bool> {
        Binding(
            get: { isCanvasIngredientsExpanded },
            set: { isExpanded in
                withMotionAnimation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    reduceMotion: reduceMotion,
                    reducedMotionFallback: nil
                ) {
                    isCanvasIngredientsExpanded = isExpanded
                }
            }
        )
    }

    private var selectedModernPaletteCategories: Set<ModernPaletteCategory> {
        ModernPaletteSelection.decode(modernPaletteCategoriesRaw)
    }

    private var selectedCanvasStyle: CanvasVisualStyle {
        CanvasVisualStyle(rawValue: canvasVisualStyleRaw) ?? .editorial
    }

    private var canvasStyleBinding: Binding<CanvasVisualStyle> {
        Binding(
            get: { selectedCanvasStyle },
            set: { style in
                guard style != selectedCanvasStyle else { return }
                canvasVisualStyleRaw = style.rawValue
                lightHapticTick &+= 1
            }
        )
    }

    var body: some View {
        ZStack {
            SettingsDetailBackground(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Appearance", selection: $draft.interfaceTheme) {
                        Text("System").tag(AppTheme.system.rawValue)
                        Text("Light").tag(AppTheme.daylight.rawValue)
                        Text("Dark").tag(AppTheme.night.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("settings.appearance.interfaceTheme")

                    canvasStylePicker
                        .padding(.horizontal, 16)

                    if selectedCanvasStyle == .editorial {
                        modernPaletteCategoriesSection
                            .transition(.opacity)
                        if ExperimentalFeatures.dayObjectsLab {
                            dayObjectsLabSection
                        }
                    } else {
                        appearanceModePicker
                            .padding(.horizontal, 16)

                        if appearanceMode == .automatic {
                            automaticThemeSection
                                .padding(.horizontal, 16)
                                .transition(.opacity)
                        } else {
                            VStack(alignment: .leading, spacing: 24) {
                                backgroundGroup
                                canvasIngredientsDisclosure
                            }
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.bottom, 80)
                .motionAnimation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: appearanceMode,
                    reducedMotionFallback: .easeInOut(duration: 0.15)
                )
                .motionAnimation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: selectedCanvasStyle,
                    reducedMotionFallback: .easeInOut(duration: 0.15)
                )
            }
        }
        .overlay { }
        .settingsDetailPage(title: String(localized: "Appearance", comment: "Settings section title"))
        .tint(theme.adaptivePrimaryText)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(draft != original)
        .toolbar {
            if draft != original {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 0) {
                        Button { showDiscard = true } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(theme.adaptivePrimaryText)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("settings.appearance.cancel")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(theme.adaptivePrimaryText)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("BackButton")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                Text(draft == original ? String(localized: "Preview") : String(localized: "Unsaved changes"))
                    .font(.geist(.caption))
                    .foregroundStyle(theme.textSecondary)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Apply") { applyAppearance() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(AppColors.brandAccent)
                    .foregroundStyle(AppAccentInk.primary)
                    .disabled(draft == original)
                    .accessibilityIdentifier("settings.appearance.apply")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(theme.backgroundColor)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.appearance.actions")
        }
        .confirmationDialog("Discard appearance changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: mediumHapticTick)
    }

    // MARK: - Appearance Mode

    private var canvasStylePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionLabel(text: String(localized: "Canvas style"))
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { styleCards }
            } else {
                HStack(alignment: .top, spacing: 12) { styleCards }

            }
            SettingsAppearancePreview(draft: draft)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Canvas appearance preview")
                .accessibilityIdentifier("settings.appearance.preview")
            Text("Applies to today and future days.")
                .font(.geist(.caption))
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appearance.canvasStyle")
    }

    @ViewBuilder private var styleCards: some View {
        styleCard(.editorial, title: String(localized: "Objects"), detail: String(localized: "Soft forms, arranged by your day"))
        styleCard(.legacy, title: String(localized: "Gradients"), detail: String(localized: "Flowing color and drawn shapes"))
    }

    private func styleCard(_ style: CanvasVisualStyle, title: String, detail: String) -> some View {
        let selected = selectedCanvasStyle == style
        return Button { canvasStyleBinding.wrappedValue = style } label: {
            VStack(alignment: .leading, spacing: 6) {
                SettingsAppearancePreview(draft: draft, styleOverride: style, thumbnail: true)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                HStack {
                    Text(title).font(.geist(.subheadline).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.brandAccent) }
                }
            }
            .foregroundStyle(theme.adaptivePrimaryText)
            .padding(12)
            .frame(minWidth: 138, maxWidth: .infinity, alignment: .leading)
            .background(theme.adaptivePrimaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? AppColors.brandAccent : theme.adaptiveDividerColor, lineWidth: selected ? 2 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("settings.appearance.style.\(style.rawValue)")
    }

    private func applyAppearance() {
        draft.apply(shared: UserDefaults(suiteName: SharedKeys.appGroupId), dayKey: AppModel.dayKey(for: .now))
        original = draft
        HistoryThumbnailCache.shared.invalidateAll()
        model.objectWillChange.send()
        model.syncUserPreferencesToSupabase()
        mediumHapticTick &+= 1
        dismiss()
    }

    private var appearanceModePicker: some View {
        Picker(
            String(localized: "Appearance mode", comment: "Appearance mode picker label"),
            selection: appearanceModeBinding
        ) {
            Text(String(localized: "Automatic", comment: "Appearance mode option"))
                .font(.geist(.subheadline))
                .tag(SettingsAppearanceMode.automatic)
            Text(String(localized: "Manual", comment: "Appearance mode option"))
                .font(.geist(.subheadline))
                .tag(SettingsAppearanceMode.manual)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .accessibilityIdentifier("settings.appearance.mode")
    }

    private var automaticThemeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "Current theme", comment: "Automatic Appearance summary heading"))

            SettingsGroupedSurface {
                DetailInfoRow(
                    label: String(localized: "Palette", comment: "Appearance current palette label"),
                    value: selectedPalette.displayName
                )
                DetailDivider()
                DetailInfoRow(
                    label: String(localized: "Gradient style", comment: "Appearance current gradient style label"),
                    value: selectedStyle.displayName
                )
                DetailDivider()
                rerollRow
            }
        }
    }

    private var rerollRow: some View {
        Button {
            withMotionAnimation(
                .spring(response: 0.4, dampingFraction: 0.75),
                reduceMotion: reduceMotion
            ) {
                draft.reroll()
            }
            mediumHapticTick &+= 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice")
                    .font(.geist(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppColors.brandAccent.opacity(0.12)))
                Text(String(localized: "Re-roll today's theme"))
                    .font(.geist(.subheadline).weight(.medium))
                    .foregroundStyle(SettingsCardAppearance.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.geist(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Re-roll today's theme"))
    }

    // MARK: - Background (palette + gradient style)

    private var backgroundGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionLabel(String(localized: "Palette", comment: "Appearance palette heading"))
                .padding(.horizontal, 16)

            paletteHScroll

            sectionLabel(String(localized: "Gradient style", comment: "Appearance gradient style heading"))
                .padding(.horizontal, 16)

            gradientStyleHScroll
        }
    }

    private var canvasIngredientsDisclosure: some View {
        SettingsGroupedSurface {
            DisclosureGroup(isExpanded: canvasIngredientsBinding) {
                manualGroup
                    .padding(.top, 18)
                    .padding(.bottom, 4)
            } label: {
                Text(String(localized: "Canvas ingredients", comment: "Appearance manual disclosure label"))
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(SettingsCardAppearance.primaryText)
            }
            .tint(.white)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Palette (horizontal scroll)

    private var paletteHScroll: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(GradientPalette.allCases, id: \.rawValue) { scheme in
                        let isSelected = selectedPalette == scheme
                        Button {
                            withMotionAnimation(
                                .spring(response: 0.3, dampingFraction: 0.7),
                                reduceMotion: reduceMotion
                            ) {
                                gradientPaletteRaw = scheme.rawValue
                            }
                                        lightHapticTick &+= 1
                        } label: {
                            paletteChip(scheme: scheme, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .settingsSelectable(label: scheme.displayName, isSelected: isSelected)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.appearance.paletteCarousel")
    }

    private func paletteChip(scheme: GradientPalette, isSelected: Bool) -> some View {
        let pal = EnergyGradientRenderer.palette(for: scheme)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [pal.bright, pal.warm, pal.cool, pal.dark, pal.bright],
                            center: .center
                        )
                    )
                    .frame(width: 48, height: 48)

                if isSelected {
                    Circle()
                        .strokeBorder(AppColors.brandAccent, lineWidth: 2.5)
                        .frame(width: 54, height: 54)

                    Image(systemName: "checkmark")
                        .font(.geist(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
            .motionAnimation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            Text(scheme.displayName)
                .font(.geist(.caption2).weight(isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }

    // MARK: - Gradient Style (horizontal scroll)

    private var gradientStyleHScroll: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(GradientStyle.allCases, id: \.rawValue) { style in
                    let isSelected = gradientStyleRaw == style.rawValue
                    Button {
                        gradientStyleRaw = style.rawValue
                        lightHapticTick &+= 1
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Canvas { context, size in
                                    let pal = activePalette
                                    let opacities = EnergyGradientRenderer.computeOpacities(
                                        smoothedS: 0.8,
                                        smoothedL: 0.6,
                                        hasStepsData: true,
                                        hasSleepData: true
                                    )
                                    EnergyGradientRenderer.draw(
                                        context: &context,
                                        size: size,
                                        opacities: opacities,
                                        baseColor: pal.dark,
                                        gradientStyle: style,
                                        colorPalette: pal
                                    )
                                }
                                .frame(width: 100, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .overlay {
                                ZStack(alignment: .topTrailing) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            isSelected ? AppColors.brandAccent : Color.white.opacity(0.08),
                                            lineWidth: isSelected ? 2 : 0.5
                                        )
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.geist(size: 15, weight: .bold))
                                            .foregroundStyle(.white, AppColors.brandAccent)
                                            .padding(6)
                                    }
                                }
                            }

                            Text(style.displayName)
                                .font(.geist(.caption2).weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .settingsSelectable(label: style.displayName, isSelected: isSelected)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Manual Group (shapes + textures)

    private var manualGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            canvasShapesSection
            canvasFillsSection
            textureSection
            if ExperimentalFeatures.dayObjectsLab {
                dayObjectsLabSection
            }
        }
    }

    // MARK: - Modern Palettes

    private var modernPaletteCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "Color families"))
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    modernPaletteAllChip
                    ForEach(ModernPaletteCategory.allCases, id: \.rawValue) { category in
                        modernPaletteCategoryChip(category)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)

            Text("A new palette each day.")
                .font(.geist(.caption))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 16)
        }
    }

    private var modernPaletteAllChip: some View {
        let isSelected = selectedModernPaletteCategories == ModernPaletteSelection.all
        let title = String(localized: "All", comment: "All modern palette categories")

        return Button {
            updateModernPaletteCategories(ModernPaletteSelection.all)
        } label: {
            modernPaletteChipLabel(title: title, isSelected: isSelected, colors: [])
        }
        .buttonStyle(.plain)
        .settingsSelectable(label: title, isSelected: isSelected)
        .accessibilityIdentifier("modernPalette.all")
    }

    private func modernPaletteCategoryChip(_ category: ModernPaletteCategory) -> some View {
        let isSelected = selectedModernPaletteCategories != ModernPaletteSelection.all
            && selectedModernPaletteCategories.contains(category)
        let colors = ModernPaletteCatalog.palettes(matching: [category]).first?.hexes ?? []

        return Button {
            updateModernPaletteCategories(
                ModernPaletteSelection.toggling(category, in: selectedModernPaletteCategories)
            )
        } label: {
            modernPaletteChipLabel(
                title: category.displayName,
                isSelected: isSelected,
                colors: colors
            )
        }
        .buttonStyle(.plain)
        .settingsSelectable(label: category.displayName, isSelected: isSelected)
        .accessibilityIdentifier("modernPalette.\(category.rawValue)")
    }

    private func modernPaletteChipLabel(
        title: String,
        isSelected: Bool,
        colors: [String]
    ) -> some View {
        HStack(spacing: 6) {
            if colors.isEmpty {
                Image(systemName: "circle.grid.2x2.fill")
                    .font(.geist(size: 10, weight: .semibold))
            } else {
                HStack(spacing: -3) {
                    ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                    }
                }
            }

            Text(title)
                .font(.geist(.caption).weight(isSelected ? .bold : .medium))

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.geist(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(isSelected ? theme.accentColor : theme.textSecondary)
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill(isSelected ? AppColors.brandAccent.opacity(0.12) : theme.adaptivePrimaryText.opacity(0.05))
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    isSelected ? AppColors.brandAccent : theme.adaptivePrimaryText.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        }
    }

    private func updateModernPaletteCategories(_ categories: Set<ModernPaletteCategory>) {
        withMotionAnimation(
            .spring(response: 0.3, dampingFraction: 0.7),
            reduceMotion: reduceMotion
        ) {
            modernPaletteCategoriesRaw = ModernPaletteSelection.encode(categories)
        }
        lightHapticTick &+= 1
    }

    private var dayObjectsLabSection: some View {
        NavigationLink {
            DayObjectsLabView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wind")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day Objects")
                        .font(.geist(.subheadline))
                    Text("Large radial-gradient orbs in seeded choreography")
                        .font(.geist(.caption))
                        .foregroundStyle(theme.adaptiveSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canvasFillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardSectionLabel(String(localized: "CANVAS FILLS", comment: "Appearance section header"))
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(TextureKind.allCases) { fill in
                        fillChipButton(fill)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }

    }

    private func fillChipButton(_ fill: TextureKind) -> some View {
        let isSelected = allowedFills.contains(fill)
        let isLastSelected = isSelected && allowedFills.count == 1

        return Button {
            var next = allowedFills
            if isSelected { next.remove(fill) } else { next.insert(fill) }
            guard !next.isEmpty else { return }
            withMotionAnimation(
                .spring(response: 0.3, dampingFraction: 0.7),
                reduceMotion: reduceMotion
            ) {
                allowedFills = next
            }
            lightHapticTick &+= 1
        } label: {
            VStack(spacing: 6) {
                Image(systemName: fill.iconName)
                    .font(.geist(size: 20, weight: .medium))
                    .frame(width: 52, height: 42)
                    .foregroundStyle(isSelected ? AppColors.brandAccent : AppTheme.night.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(SettingsCardAppearance.primaryText.opacity(isSelected ? 0.10 : 0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isSelected ? AppColors.brandAccent : SettingsCardAppearance.primaryText.opacity(0.06),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.geist(size: 14, weight: .bold))
                                .foregroundStyle(SettingsCardAppearance.primaryText, AppColors.brandAccent)
                                .offset(x: 5, y: -5)
                        }
                    }
                Text(fill.displayName)
                    .font(.geist(.caption2).weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? SettingsCardAppearance.primaryText : theme.adaptiveSecondaryText)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLastSelected)
        .opacity(isLastSelected ? 0.75 : 1)
        .settingsSelectable(label: fill.displayName, isSelected: isSelected)
    }

    // MARK: - Canvas Shapes (compact)

    private var canvasShapesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                cardSectionLabel(String(localized: "CANVAS SHAPES", comment: "Appearance section header"))
            }
            .padding(.horizontal, 16)

            SettingsGroupedSurface {
                shapeMultiSelectRow
            }
            .padding(.horizontal, 16)
        }

    }

    /// One multi-select over `selectableCases`, replacing the three
    /// single-select per-category rows. Shape choice is no longer derived from
    /// a category, so there is nothing left to key the rows on.
    private var shapeMultiSelectRow: some View {
        HStack(spacing: 6) {
            ForEach(CanvasShapeType.selectableCases) { shape in
                shapeChipButton(shape: shape)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func shapeChipButton(shape: CanvasShapeType) -> some View {
        let isSelected = allowedShapes.contains(shape)
        // The set may never be empty. Disable the last selected chip rather
        // than letting the tap fail silently — a dead tap reads as a bug.
        let isLastSelected = isSelected && allowedShapes.count == 1

        return Button {
            var next = allowedShapes
            if isSelected { next.remove(shape) } else { next.insert(shape) }
            guard !next.isEmpty else { return }
            withMotionAnimation(
                .spring(response: 0.3, dampingFraction: 0.7),
                reduceMotion: reduceMotion
            ) {
                allowedShapes = next
            }
            lightHapticTick &+= 1
        } label: {
            compactShapeChip(shape: shape, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isLastSelected)
        .opacity(isLastSelected ? 0.75 : 1)
        .settingsSelectable(label: shape.displayName, isSelected: isSelected)
    }

    private func compactShapeChip(shape: CanvasShapeType, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsCardAppearance.primaryText.opacity(isSelected ? 0.1 : 0.04))
                .frame(width: 48, height: 48)

            shapeTypePreview(shape: shape)
                .frame(width: 34, height: 34)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? AppColors.brandAccent : SettingsCardAppearance.primaryText.opacity(0.06),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.geist(size: 14, weight: .bold))
                    .foregroundStyle(SettingsCardAppearance.primaryText, AppColors.brandAccent)
                    .offset(x: 4, y: -4)
            }
        }
    }

    @ViewBuilder
    private func shapeTypePreview(shape: CanvasShapeType) -> some View {
        let brandYellow = AppColors.brandAccent
        let previewSeed: UInt64 = 42_091

        switch shape {
        case .circle, .spirograph:
            Circle()
                .fill(
                    RadialGradient(
                        colors: [brandYellow, brandYellow.opacity(0.3)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 17
                    )
                )
        case .snowflake:
            RectMorphPreview(
                seed: previewSeed,
                color: brandYellow
            )
        case .rays:
            SpotlightPreview(
                seed: previewSeed,
                overrideColor: brandYellow
            )
        case .organicBlob:
            OrganicBlobPreview(
                seed: previewSeed,
                colors: [brandYellow, brandYellow.opacity(0.5)]
            )
        case .blob:
            BodyBlobPreview(
                seed: previewSeed,
                colors: [brandYellow, brandYellow.opacity(0.5)]
            )
        }
    }

    // MARK: - Texture Overlay (horizontal scroll)

    private var selectedTexture: CanvasTexture {
        CanvasTexture.fromStored(canvasTextureRaw)
    }

    private var textureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardSectionLabel(String(localized: "TEXTURE", comment: "Appearance section header"))
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    textureChip(texture: .none)
                    ForEach(CanvasTexture.textures) { texture in
                        textureChip(texture: texture)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func textureChip(texture: CanvasTexture) -> some View {
        let isSelected = selectedTexture == texture

        return Button {
            withMotionAnimation(
                .spring(response: 0.3, dampingFraction: 0.7),
                reduceMotion: reduceMotion
            ) {
                canvasTextureRaw = texture.rawValue
            }
            lightHapticTick &+= 1
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let name = texture.assetName {
                        Image(name)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SettingsCardAppearance.primaryText.opacity(0.06))
                            .frame(width: 56, height: 56)
                        Image(systemName: "circle.slash")
                            .font(.geist(size: 18, weight: .ultraLight))
                            .foregroundStyle(theme.adaptiveMutedText)
                    }
                }
                .frame(width: 56, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? AppColors.brandAccent : Color.white.opacity(0.08),
                            lineWidth: isSelected ? 2 : 0.5
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.geist(size: 15, weight: .bold))
                            .foregroundStyle(SettingsCardAppearance.primaryText, AppColors.brandAccent)
                            .offset(x: 5, y: -5)
                    }
                }

                Text(texture.displayName)
                    .font(.geist(.caption2).weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .settingsSelectable(label: texture.displayName, isSelected: isSelected)
    }

    // MARK: - Shared Helpers

    private func cardSectionLabel(_ text: String) -> some View {
        Text(SettingsLocalizedCasing.uppercase(text))
            .font(.geist(.caption2).weight(.semibold))
            .tracking(2)
            .foregroundStyle(SettingsCardAppearance.primaryText.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(SettingsLocalizedCasing.uppercase(text))
            .font(.geist(.caption2).weight(.semibold))
            .tracking(2)
            .foregroundStyle(theme.adaptivePrimaryText.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
    }

}

#Preview {
    NavigationStack {
        SettingsAppearancePage(model: DIContainer.shared.makeAppModel())
    }
}
