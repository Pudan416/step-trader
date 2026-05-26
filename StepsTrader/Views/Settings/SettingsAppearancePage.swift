import SwiftUI

struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @AppStorage(SharedKeys.gradientStyle) private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @AppStorage(SharedKeys.dailyRandomThemeEnabled) private var dailyRandomThemeEnabled: Bool = false
    @AppStorage(SharedKeys.canvasTexture) private var canvasTextureRaw: String = CanvasTexture.grainSmall.rawValue
    @AppStorage(SharedKeys.bodyCanvasShape) private var bodyShapeRaw: String = CanvasShapeType.circle.rawValue
    @AppStorage(SharedKeys.mindCanvasShape) private var mindShapeRaw: String = CanvasShapeType.snowflake.rawValue
    @AppStorage(SharedKeys.heartCanvasShape) private var heartShapeRaw: String = CanvasShapeType.rays.rawValue

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme
    @State private var previewConfig: GradientPreviewConfig?
    @State private var showPaywall = false

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
        dailyRandomThemeEnabled && model.isPro
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
                    // TODO: Migrate to .sensoryFeedback()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    previewConfig = nil
                    model.syncUserPreferencesToSupabase()
                }
            )
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(
                model: model,
                store: model.subscriptionStore,
                source: .feature
            )
        }
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
                HStack(spacing: 6) {
                    Text(String(localized: "Daily random theme"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.adaptivePrimaryText)
                    if !model.isPro {
                        proBadge
                    }
                }
                Text(isDailyRandomActive
                     ? String(localized: "Randomizes color & gradient style each day.")
                     : String(localized: "A fresh palette + style every day."))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.adaptiveMutedText)
            }

            Spacer(minLength: 0)

            if model.isPro {
                Toggle("", isOn: Binding(
                    get: { dailyRandomThemeEnabled },
                    set: { newValue in
                        model.setDailyRandomTheme(enabled: newValue)
                        // TODO: Migrate to .sensoryFeedback()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                ))
                .labelsHidden()
                .tint(AppColors.brandAccent)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.brandAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if !model.isPro {
                showPaywall = true
                // TODO: Migrate to .sensoryFeedback()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .accessibilityAddTraits(.isButton)
    }

    private var rerollRow: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                model.rerollDailyTheme()
            }
            // TODO: Migrate to .sensoryFeedback()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                    let isUnlocked = SubscriptionGate.isGradientPaletteAvailable(
                        isPro: model.isPro,
                        paletteRaw: scheme.rawValue
                    )
                    Button {
                        guard !isDailyRandomActive else { return }
                        if isUnlocked {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                gradientPaletteRaw = scheme.rawValue
                            }
                            model.syncUserPreferencesToSupabase()
                        } else {
                            showPaywall = true
                        }
                        // TODO: Migrate to .sensoryFeedback()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        paletteChip(scheme: scheme, isSelected: isSelected, isLocked: !isUnlocked)
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

    private func paletteChip(scheme: GradientPalette, isSelected: Bool, isLocked: Bool) -> some View {
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
                    .saturation(isLocked ? 0.35 : 1.0)
                    .opacity(isLocked ? 0.7 : 1.0)

                if isSelected {
                    Circle()
                        .strokeBorder(AppColors.brandAccent, lineWidth: 2.5)
                        .frame(width: 54, height: 54)

                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }

                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .offset(x: 16, y: 16)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            Text(scheme.displayName)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .opacity(isLocked ? 0.6 : 1.0)
        }
        .accessibilityLabel(isLocked
            ? String(localized: "\(scheme.displayName), locked, requires Pro")
            : scheme.displayName)
    }

    // MARK: - Gradient Style (horizontal scroll)

    private var gradientStyleHScroll: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(GradientStyle.allCases, id: \.rawValue) { style in
                    let isSelected = gradientStyleRaw == style.rawValue
                    let isUnlocked = SubscriptionGate.isGradientStyleAvailable(
                        isPro: model.isPro,
                        styleRaw: style.rawValue
                    )
                    Button {
                        guard !isDailyRandomActive else { return }
                        if isUnlocked {
                            previewConfig = GradientPreviewConfig(style: style)
                        } else {
                            showPaywall = true
                        }
                        // TODO: Migrate to .sensoryFeedback()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                                .saturation(isUnlocked ? 1.0 : 0.3)
                                .opacity(isUnlocked ? 1.0 : 0.55)

                                if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(Circle().fill(.black.opacity(0.55)))
                                }
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
                                .opacity(isUnlocked ? 1.0 : 0.6)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDailyRandomActive)
                    .accessibilityLabel(isUnlocked
                        ? Text(style.displayName)
                        : Text(String(localized: "\(style.displayName), locked, requires Pro")))
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
            textureSection
        }
    }

    // MARK: - Canvas Shapes (compact)

    private var canvasShapesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionLabel(String(localized: "CANVAS SHAPES", comment: "Appearance section header"))
                if !model.isPro { proBadge }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                compactShapeRow(
                    categoryName: String(localized: "Body", comment: "Canvas shape category"),
                    categoryIcon: "figure.walk",
                    selectedRaw: $bodyShapeRaw,
                    defaultShape: .blob
                )
                DetailDivider()
                compactShapeRow(
                    categoryName: String(localized: "Mind", comment: "Canvas shape category"),
                    categoryIcon: "brain.head.profile",
                    selectedRaw: $mindShapeRaw,
                    defaultShape: .snowflake
                )
                DetailDivider()
                compactShapeRow(
                    categoryName: String(localized: "Heart", comment: "Canvas shape category"),
                    categoryIcon: "heart.fill",
                    selectedRaw: $heartShapeRaw,
                    defaultShape: .rays
                )
            }
            .padding(.horizontal, 16)
            .glassCard()
        }
    }

    private func compactShapeRow(
        categoryName: String,
        categoryIcon: String,
        selectedRaw: Binding<String>,
        defaultShape: CanvasShapeType
    ) -> some View {
        let selected = CanvasShapeType(rawValue: selectedRaw.wrappedValue) ?? defaultShape
        let isUnlocked = model.isPro

        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.adaptiveSecondaryText)
                Text(categoryName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.adaptivePrimaryText)
            }
            .frame(width: 72, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                ForEach(CanvasShapeType.selectableCases) { shape in
                    let isSelected = selected == shape
                    Button {
                        if isUnlocked {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedRaw.wrappedValue = shape.rawValue
                            }
                            // TODO: Migrate to .sensoryFeedback()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.syncUserPreferencesToSupabase()
                        } else {
                            showPaywall = true
                            // TODO: Migrate to .sensoryFeedback()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        compactShapeChip(shape: shape, isSelected: isSelected, isUnlocked: isUnlocked)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.brandAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func compactShapeChip(shape: CanvasShapeType, isSelected: Bool, isUnlocked: Bool) -> some View {
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
        .saturation(isUnlocked ? 1.0 : 0.4)
        .accessibilityLabel(isUnlocked
            ? shape.displayName
            : String(localized: "\(shape.displayName), locked, requires Pro"))
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
        let isUnlocked = !texture.isPro || model.isPro

        return Button {
            if isUnlocked {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    canvasTextureRaw = texture.rawValue
                }
                // TODO: Migrate to .sensoryFeedback()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                model.syncUserPreferencesToSupabase()
            } else {
                showPaywall = true
                // TODO: Migrate to .sensoryFeedback()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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

                    if !isUnlocked {
                        Color.black.opacity(0.4)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .frame(width: 56, height: 56)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(.black.opacity(0.55)))
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
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(3)
            .foregroundStyle(theme.adaptiveMutedText)
    }

    private var proBadge: some View {
        Text(String(localized: "PRO", comment: "Pro feature badge"))
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppColors.brandAccent))
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
