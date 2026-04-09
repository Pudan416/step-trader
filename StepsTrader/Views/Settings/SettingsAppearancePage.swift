import SwiftUI

struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage(SharedKeys.gradientStyle) private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    @State private var previewConfig: GradientPreviewConfig?

    private var selectedPalette: GradientPalette {
        GradientPalette.normalized(rawValue: gradientPaletteRaw)
    }

    private var selectedStyle: GradientStyle {
        GradientStyle(rawValue: gradientStyleRaw) ?? .radial
    }

    private var activePalette: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: selectedPalette)
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: String(localized: "Appearance", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    livePreviewCard
                        .padding(.horizontal, 16)

                    themeSection
                        .padding(.horizontal, 16)

                    paletteSection
                        .padding(.horizontal, 16)

                    gradientStyleSection
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $previewConfig) { config in
            GradientPreviewSheet(
                config: config,
                onApply: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        gradientStyleRaw = config.style.rawValue
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    previewConfig = nil
                }
            )
            .presentationBackground(.clear)
        }
    }

    // MARK: - Live Preview

    private var livePreviewCard: some View {
        Canvas { context, size in
            let pal = activePalette
            let opacities = EnergyGradientRenderer.computeOpacities(
                smoothedS: 0.75,
                smoothedL: 0.55,
                hasStepsData: true,
                hasSleepData: true,
                isDaylight: theme.isLightTheme
            )
            EnergyGradientRenderer.draw(
                context: &context,
                size: size,
                opacities: opacities,
                baseColor: theme.isLightTheme ? pal.daylightBase : pal.dark,
                gradientStyle: selectedStyle,
                colorPalette: pal
            )
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedPalette.displayName)
                    .font(.caption.weight(.semibold))
                Text(selectedStyle.displayName)
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(12)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.5), value: gradientPaletteRaw)
        .animation(.easeInOut(duration: 0.5), value: gradientStyleRaw)
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "THEME", comment: "Appearance section header"))

            HStack(spacing: 0) {
                ForEach(AppTheme.selectableThemes, id: \.rawValue) { option in
                    let isSelected = appThemeRaw == option.rawValue
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            appThemeRaw = option.rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(option.displayNameEn)
                            .font(.caption.weight(isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(Color.primary.opacity(0.1))
                                    : AnyShapeStyle(Color.clear)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.04)))
        }
    }

    // MARK: - Palette

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "PALETTE", comment: "Appearance section header"))

            HStack(spacing: 0) {
                ForEach(GradientPalette.allCases, id: \.rawValue) { scheme in
                    let isSelected = selectedPalette == scheme
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            gradientPaletteRaw = scheme.rawValue
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        paletteChip(scheme: scheme, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func paletteChip(scheme: GradientPalette, isSelected: Bool) -> some View {
        let pal = EnergyGradientRenderer.palette(for: scheme)
        return VStack(spacing: 8) {
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
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

            Text(scheme.displayName)
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .primary : .secondary)
        }
    }

    // MARK: - Gradient Style

    private var gradientStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "STYLE", comment: "Appearance section header"))

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GradientStyle.allCases, id: \.rawValue) { style in
                    let isSelected = gradientStyleRaw == style.rawValue
                    Button {
                        previewConfig = GradientPreviewConfig(style: style)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            Canvas { context, size in
                                let pal = activePalette
                                let opacities = EnergyGradientRenderer.computeOpacities(
                                    smoothedS: 0.8,
                                    smoothedL: 0.6,
                                    hasStepsData: true,
                                    hasSleepData: true,
                                    isDaylight: false
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
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        isSelected ? AppColors.brandAccent : Color.white.opacity(0.08),
                                        lineWidth: isSelected ? 2 : 0.5
                                    )
                            )

                            Text(style.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(theme.adaptiveMutedText)
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}
