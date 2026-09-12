import SwiftUI

struct GradientPreviewSheet: View {
    let config: GradientPreviewConfig
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @State private var selectedState = 0

    private let states: [(steps: Double, sleep: Double, label: String)] = [
        (1.0, 1.0, String(localized: "Full", comment: "GradientPreview – preview mode showing all data")),
        (0.0, 1.0, String(localized: "Sleep only", comment: "GradientPreview – preview mode sleep data only")),
        (1.0, 0.0, String(localized: "Steps only", comment: "GradientPreview – preview mode steps data only")),
        (0.0, 0.0, String(localized: "No data", comment: "GradientPreview – preview mode empty state")),
    ]

    private var pal: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: GradientPalette(rawValue: gradientPaletteRaw) ?? .warmSunset)
    }

    private var baseColor: Color {
        pal.dark
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let st = states[selectedState]
                let Ss = EnergyGradientRenderer.smoothstep(st.steps)
                let Ls = EnergyGradientRenderer.smoothstep(st.sleep)
                let opacities = EnergyGradientRenderer.computeOpacities(
                    smoothedS: Ss,
                    smoothedL: Ls,
                    hasStepsData: st.steps > 0,
                    hasSleepData: st.sleep > 0
                )
                EnergyGradientRenderer.draw(
                    context: &context,
                    size: size,
                    opacities: opacities,
                    baseColor: baseColor,
                    gradientStyle: config.style,
                    colorPalette: pal
                )
            }
            .ignoresSafeArea()
            .overlay {
                Image("grain (small)")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.4)
                    .blendMode(.overlay)
            }

            VStack(spacing: 0) {
                HStack {
                    Text(config.style.displayName)
                        .font(.geist(.headline).weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.geist(.title2))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Close preview", comment: "Gradient preview close button"))
                    .accessibilityIdentifier("settings.appearance.preview.close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                        Button {
                            withMotionAnimation(
                                .easeInOut(duration: 0.4),
                                reduceMotion: reduceMotion
                            ) {
                                selectedState = index
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Canvas { context, size in
                                    let Ss = EnergyGradientRenderer.smoothstep(state.steps)
                                    let Ls = EnergyGradientRenderer.smoothstep(state.sleep)
                                    let opacities = EnergyGradientRenderer.computeOpacities(
                                        smoothedS: Ss,
                                        smoothedL: Ls,
                                        hasStepsData: state.steps > 0,
                                        hasSleepData: state.sleep > 0
                                    )
                                    EnergyGradientRenderer.draw(
                                        context: &context,
                                        size: size,
                                        opacities: opacities,
                                        baseColor: baseColor,
                                        gradientStyle: config.style,
                                        colorPalette: pal
                                    )
                                }
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    ZStack(alignment: .topTrailing) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                selectedState == index ? Color.white : Color.white.opacity(0.15),
                                                lineWidth: selectedState == index ? 2 : 0.5
                                            )
                                        if selectedState == index {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.geist(size: 15, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(6)
                                        }
                                    }
                                }

                                Text(state.label)
                                    .font(.geist(.caption2).weight(selectedState == index ? .bold : .medium))
                                    .foregroundStyle(selectedState == index ? .white : .white.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .settingsSelectable(
                            label: state.label,
                            isSelected: selectedState == index
                        )
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    onApply()
                } label: {
                    Text(String(localized: "Apply", comment: "GradientPreview – apply gradient button"))
                        .font(.geist(.subheadline).weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(AppColors.brandAccent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

}

#Preview {
    GradientPreviewSheet(
        config: GradientPreviewConfig(style: .radial),
        onApply: {}
    )
    .presentationBackground(.clear)
}
