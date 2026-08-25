import SwiftUI

struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.gradientStyle) private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.dailyRandomThemeEnabled) private var dailyRandomThemeEnabled: Bool = false
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    /// Mirrors `SharedKeys.allowedCanvasShapes` only to trigger redraws —
    /// `CanvasShapeType.allowedByUser` stays the single source of truth, since
    /// it also seeds from the legacy keys. There is no gate: every shape is
    /// available to every user.
    @State private var allowedShapes: Set<CanvasShapeType> = []
    @State private var allowedFills: Set<TextureKind> = []

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme
    @State private var previewConfig: GradientPreviewConfig?
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

    private var isDailyRandomActive: Bool {
        dailyRandomThemeEnabled
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: String(localized: "Appearance", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    dailyRandomThemeSection
                        .padding(.horizontal, 16)

                    randomizableGroup

                    manualGroup
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
        .sheet(item: $previewConfig) { config in
            GradientPreviewSheet(
                config: config,
                onApply: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        gradientStyleRaw = config.style.rawValue
                    }
                                        mediumHapticTick &+= 1
                    previewConfig = nil
                    model.syncUserPreferencesToSupabase()
                }
            )
            .presentationBackground(.clear)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: mediumHapticTick)
    }

    // MARK: - Daily Random Theme

    private var dailyRandomThemeSection: some View {
        VStack(spacing: 0) {
            dailyRandomToggleRow
            if isDailyRandomActive {
                DetailDivider()
                rerollRow
            }
        }
        .glassCard()
    }

    private var dailyRandomToggleRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "shuffle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDailyRandomActive ? AppColors.brandAccent : theme.adaptiveSecondaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill((isDailyRandomActive ? AppColors.brandAccent : theme.adaptiveSecondaryText).opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Daily random theme"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Text(isDailyRandomActive
                     ? String(localized: "Randomizes color & gradient style each day.")
                     : String(localized: "A fresh palette + style every day."))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.adaptiveMutedText)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { dailyRandomThemeEnabled },
                set: { newValue in
                    model.setDailyRandomTheme(enabled: newValue)
                                            lightHapticTick &+= 1
                }
            ))
            .labelsHidden()
            .tint(AppColors.brandAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var rerollRow: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                model.rerollDailyTheme()
            }
                        mediumHapticTick &+= 1
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(AppColors.brandAccent.opacity(0.12)))
                Text(String(localized: "Re-roll today's theme"))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveSecondaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Re-roll today's theme"))
    }

    // MARK: - Randomizable Group (palette + gradient style)

    private var randomizableGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                sectionLabel(String(localized: "BACKGROUND COLOR", comment: "Appearance section header"))
                if isDailyRandomActive { autoTag }
            }
            .padding(.horizontal, 16)

            paletteHScroll

            HStack(spacing: 8) {
                sectionLabel(String(localized: "GRADIENT STYLE", comment: "Appearance section header"))
                if isDailyRandomActive { autoTag }
            }
            .padding(.horizontal, 16)

            gradientStyleHScroll
        }
        .opacity(isDailyRandomActive ? 0.45 : 1.0)
    }

    // MARK: - Palette (horizontal scroll)

    private var paletteHScroll: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(GradientPalette.allCases, id: \.rawValue) { scheme in
                    let isSelected = selectedPalette == scheme
                    Button {
                        guard !isDailyRandomActive else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            gradientPaletteRaw = scheme.rawValue
                        }
                        model.syncUserPreferencesToSupabase()
                                                lightHapticTick &+= 1
                    } label: {
                        paletteChip(scheme: scheme, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDailyRandomActive)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            Text(scheme.displayName)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .accessibilityLabel(scheme.displayName)
    }

    // MARK: - Gradient Style (horizontal scroll)

    private var gradientStyleHScroll: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(GradientStyle.allCases, id: \.rawValue) { style in
                    let isSelected = gradientStyleRaw == style.rawValue
                    Button {
                        guard !isDailyRandomActive else { return }
                        previewConfig = GradientPreviewConfig(style: style)
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
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        isSelected ? AppColors.brandAccent : Color.white.opacity(0.08),
                                        lineWidth: isSelected ? 2 : 0.5
                                    )
                            }

                            Text(style.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDailyRandomActive)
                    .accessibilityLabel(Text(style.displayName))
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
            if ExperimentalFeatures.richCanvasLab {
                richCanvasLabSection
            }
            if ExperimentalFeatures.generativeSceneLab {
                generativeSceneLabSection
            }
            if ExperimentalFeatures.canvasAtmosphereLab {
                canvasAtmosphereLabSection
            }
            if ExperimentalFeatures.dayRaysLab {
                dayRaysLabSection
            }
            if ExperimentalFeatures.dayObjectsLab {
                dayObjectsLabSection
            }
        }
    }

    private var richCanvasLabSection: some View {
        NavigationLink {
            RichCanvasLabView(model: model)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rich Canvas")
                    Text("Preview today's canvas with experimental figures")
                        .font(.caption)
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

    private var generativeSceneLabSection: some View {
        NavigationLink {
            GenerativeSceneLabView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Generative Scene")
                    Text("Volumetric day scene prototype with live parameters")
                        .font(.caption)
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

    private var canvasAtmosphereLabSection: some View {
        NavigationLink {
            CanvasAtmosphereLabView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.aperture")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Atmosphere")
                    Text("Today's canvas with dust and depth of field")
                        .font(.caption)
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

    private var dayRaysLabSection: some View {
        NavigationLink {
            DayRaysLabView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rays")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day Rays")
                    Text("Generated ray fans — single day or a grid of seeds")
                        .font(.caption)
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

    private var dayObjectsLabSection: some View {
        NavigationLink {
            DayObjectsLabView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wind")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day Objects")
                    Text("Large radial-gradient orbs in seeded choreography")
                        .font(.caption)
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
            sectionLabel(String(localized: "CANVAS FILLS", comment: "Appearance section header"))
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
        .onAppear { allowedFills = Set(TextureKind.allowedByUser) }
    }

    private func fillChipButton(_ fill: TextureKind) -> some View {
        let isSelected = allowedFills.contains(fill)
        let isLastSelected = isSelected && allowedFills.count == 1

        return Button {
            var next = allowedFills
            if isSelected { next.remove(fill) } else { next.insert(fill) }
            guard TextureKind.setAllowed(next) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                allowedFills = next
            }
            lightHapticTick &+= 1
            HistoryThumbnailCache.shared.invalidateAll()
            model.objectWillChange.send()
            model.syncUserPreferencesToSupabase()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: fill.iconName)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 52, height: 42)
                    .foregroundStyle(isSelected ? AppColors.brandAccent : theme.adaptiveSecondaryText)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(theme.adaptivePrimaryText.opacity(isSelected ? 0.10 : 0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(
                                isSelected ? AppColors.brandAccent : theme.adaptivePrimaryText.opacity(0.06),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                    }
                Text(fill.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? theme.adaptivePrimaryText : theme.adaptiveSecondaryText)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLastSelected)
        .opacity(isLastSelected ? 0.75 : 1)
        .accessibilityLabel(fill.displayName)
    }

    // MARK: - Canvas Shapes (compact)

    private var canvasShapesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel(String(localized: "CANVAS SHAPES", comment: "Appearance section header"))
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                shapeMultiSelectRow
            }
            .padding(.horizontal, 16)
            .glassCard()
        }
        .onAppear { allowedShapes = Set(CanvasShapeType.allowedByUser) }
    }

    /// One multi-select over `selectableCases`, replacing the three
    /// single-select per-category rows. Shape choice is no longer derived from
    /// a category, so there is nothing left to key the rows on.
    private var shapeMultiSelectRow: some View {
        return HStack(spacing: 10) {
            Text("Shapes", comment: "Canvas shapes multi-select row label")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.adaptivePrimaryText)
                .frame(width: 72, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(CanvasShapeType.selectableCases) { shape in
                    shapeChipButton(shape: shape)
                }
            }

        }
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
            guard CanvasShapeType.setAllowed(next) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                allowedShapes = next
            }
            lightHapticTick &+= 1
            model.syncUserPreferencesToSupabase()
        } label: {
            compactShapeChip(shape: shape, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isLastSelected)
        .opacity(isLastSelected ? 0.75 : 1)
    }

    private func compactShapeChip(shape: CanvasShapeType, isSelected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.adaptivePrimaryText.opacity(isSelected ? 0.1 : 0.04))
                .frame(width: 48, height: 48)

            shapeTypePreview(shape: shape)
                .frame(width: 34, height: 34)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected ? AppColors.brandAccent : theme.adaptivePrimaryText.opacity(0.06),
                    lineWidth: isSelected ? 2 : 0.5
                )
        }
        .accessibilityLabel(shape.displayName)
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
            sectionLabel(String(localized: "TEXTURE", comment: "Appearance section header"))
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                canvasTextureRaw = texture.rawValue
            }
                                lightHapticTick &+= 1
            model.syncUserPreferencesToSupabase()
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
                            .fill(theme.adaptivePrimaryText.opacity(0.06))
                            .frame(width: 56, height: 56)
                        Image(systemName: "circle.slash")
                            .font(.system(size: 18, weight: .ultraLight))
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

                Text(texture.displayName)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(SettingsLocalizedCasing.uppercase(text))
            .font(.caption2.weight(.semibold))
            .tracking(3)
            .foregroundStyle(theme.adaptiveMutedText)
    }

    private var autoTag: some View {
        Text(String(localized: "auto", comment: "Inline tag — picker disabled because daily random is on"))
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(theme.adaptiveMutedText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.adaptiveMutedText.opacity(0.12)))
    }
}

#Preview {
    NavigationStack {
        SettingsAppearancePage(model: DIContainer.shared.makeAppModel())
    }
}
