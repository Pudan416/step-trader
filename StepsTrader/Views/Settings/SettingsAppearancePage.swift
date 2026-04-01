import SwiftUI

struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage(SharedKeys.gradientStyle) private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    @State private var previewConfig: GradientPreviewConfig?

    private var activePalette: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: GradientPalette(rawValue: gradientPaletteRaw) ?? .warmSunset)
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailHeader(title: String(localized: "Appearance", comment: "Settings section title"))
                        .padding(.horizontal, 16)

                    // MARK: Theme — segmented pill
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
                    .padding(.horizontal, 16)

                    // MARK: Palette — horizontal color row
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel(String(localized: "COLORS", comment: "Appearance section header"))

                        HStack(spacing: 12) {
                            ForEach(GradientPalette.allCases, id: \.rawValue) { scheme in
                                let isSelected = gradientPaletteRaw == scheme.rawValue
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        gradientPaletteRaw = scheme.rawValue
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    VStack(spacing: 6) {
                                        let pal = EnergyGradientRenderer.palette(for: scheme)
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(LinearGradient(
                                                colors: [pal.bright, pal.warm, pal.cool, pal.dark],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(height: 44)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(
                                                        isSelected ? AppColors.brandAccent : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )

                                        Text(scheme.displayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: Gradient — visual swatch grid
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel(String(localized: "GRADIENT", comment: "Appearance section header"))

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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(theme.adaptiveMutedText)
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    }
}
