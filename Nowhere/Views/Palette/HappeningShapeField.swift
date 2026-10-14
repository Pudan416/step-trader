import SwiftUI
import simd

/// Transparent labels and hit targets over the renderer's scrollable actors.
struct HappeningShapeField: View {
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let layout: HappeningFieldLayout.Layout
    let interaction: HappeningPaletteInteractionState
    let addedIDs: Set<String>
    let onActivate: (Happening) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var labelInks: [String: HappeningPaletteLabelInk] = [:]
    var fitsTreeLabels = false
    var isSurvey = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(happenings.enumerated()), id: \.element.id) { index, happening in
                if index < layout.sources.count, layout.sources[index].appearanceScale > 0.001 {
                    happeningButton(happening, source: layout.sources[index])
                }
            }
        }
    }

    private func happeningButton(
        _ happening: Happening,
        source: HappeningFieldLayout.Source
    ) -> some View {
        let state = interaction.visualState(for: happening.id, addedIDs: addedIDs)
        let existingTourMoment = !isSurvey && CanvasTour.shared.isActive
            && CanvasTour.shared.step == .happening && addedIDs.contains(happening.id)
        let locked = assignments[happening.id] == nil || interaction.pendingMutation != nil
        let side = max(44, source.radius * 2 / max(0.001, source.appearanceScale))
        let ink = labelInks[happening.id] ?? .dark

        return ZStack {
            Button { onActivate(happening) } label: {
                Text(happening.localizedTitle())
                    .font(.onest(size: min(26, HappeningFieldLabelTypography.scaledUIFont(for: dynamicTypeSize).pointSize), weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(fitsTreeLabels && !happening.localizedTitle().contains(" ") ? 1 : 3)
                    .minimumScaleFactor(fitsTreeLabels ? 0.75 : tourLabelScale)
                    .frame(width: max(30, side * 0.80 - 12), alignment: .center)
                    .padding(.horizontal, 4)
                    // Keep selected labels directly on the figure. A small
                    // contrasting halo preserves legibility without the old
                    // opaque rounded rectangle behind the text.
                    .shadow(color: ink == .light ? .black.opacity(0.8) : .white.opacity(0.8), radius: 2, x: 0, y: 0)
                    .shadow(color: ink == .light ? .black.opacity(0.55) : .white.opacity(0.55), radius: 4, x: 0, y: 1)
                    // Preview actions are high contrast and remain outside the
                    // title's layout so the figure and caption do not jump.
                    .overlay {
                        if state.awaitsConfirmation {
                            Label(
                                state == .additionPreview ? LocalizedStringKey("Add") : LocalizedStringKey("Delete"),
                                systemImage: state == .additionPreview ? "plus" : "trash"
                            )
                                .font(.geist(size: 13, weight: .bold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.94), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityIdentifier("happening_action_\(happening.id)")
                                .offset(y: min(side * 0.31, 38))
                        }
                    }
                    .foregroundStyle(ink.color)
                    .frame(width: side, height: side)
                    .contentShape(HappeningPickerShape())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .allowsHitTesting(!locked)
            .accessibilityLabel(happening.localizedTitle())
            .accessibilityValue(isSurvey ? surveyValue(for: state) : HappeningPaletteAccessibility.value(for: state))
            .accessibilityHint(isSurvey ? surveyHint(for: state) : existingTourMoment
                ? String(localized: "Already in your day. Tap to continue the tour.")
                : hint(for: state, locked: locked))
            .accessibilityIdentifier(!isSurvey ? "happening_choice_\(happening.id)" : "happenings.onboarding.\(happening.id.replacingOccurrences(of: "survey:", with: "").replacingOccurrences(of: ":", with: "."))")

            if state == .added {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.88), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("happening_status_added_\(happening.id)")
                    .allowsHitTesting(false)
                    .offset(x: side * 0.30, y: -side * 0.30)
            }
        }
        .frame(width: side, height: side)
        .scaleEffect(source.appearanceScale)
        .canvasTourAnchor("canvas.happening.\(happening.id)")
        .position(source.center)
    }

    private func surveyValue(for state: HappeningPaletteSlotVisualState) -> String {
        switch state {
        case .available: "Not selected"
        case .added: "Selected"
        case .removalPreview: "Previewing deselection"
        case .additionPreview: "Previewing selection"
        }
    }

    private func surveyHint(for state: HappeningPaletteSlotVisualState) -> String {
        switch state {
        case .available, .additionPreview: "Tap to select."
        case .added: "Tap to preview deselection."
        case .removalPreview: "Tap again to deselect."
        }
    }

    private var tourLabelScale: CGFloat {
        CanvasTour.shared.isActive ? 0.80 : 1
    }

    private func hint(for state: HappeningPaletteSlotVisualState, locked: Bool) -> String {
        if locked { return String(localized: "This happening is temporarily unavailable. Try again.") }
        switch state {
        case .available: return String(localized: "Activate to add to Canvas")
        case .additionPreview: return String(localized: "Activate again to add to Canvas")
        case .added: return String(localized: "Activate to preview removing from Canvas")
        case .removalPreview: return String(localized: "Activate again to remove from Canvas")
        }
    }
}

/// Choose readable ink from the Canvas or the selected figure's saved pigment.
/// Transparent contours keep the Canvas ink; they do not supply a text backing.
enum HappeningPaletteLabelInk: Equatable {
    case dark, light

    var color: Color { self == .dark ? .black : .white }

    static func contrasting(with linearColors: [SIMD3<Float>]) -> Self {
        guard !linearColors.isEmpty else { return .dark }
        let luminances = linearColors.map {
            max(0, min(1, simd_dot($0, SIMD3<Float>(0.2126, 0.7152, 0.0722))))
        }
        let darkContrast = luminances.map { ($0 + 0.05) / 0.05 }.min() ?? 1
        let lightContrast = luminances.map { 1.05 / ($0 + 0.05) }.min() ?? 1
        return darkContrast >= lightContrast ? .dark : .light
    }

    static func resolve(
        state: HappeningPaletteSlotVisualState,
        background: [SIMD3<Float>],
        material: MetalShapeMaterialUniforms?
    ) -> Self {
        // The circle supplies its own light backing, regardless of the theme
        // or gradient. Only revealed figures need their pigment considered.
        guard state != .available else { return .dark }
        guard let material else { return contrasting(with: background) }
        let colors: [SIMD4<Float>]
        switch material.materialIndex {
        case 2, 3, 8, 9: return contrasting(with: background)
        case 0: colors = [material.color0]
        case 1, 4: colors = [material.color0, material.color1]
        default: colors = [material.color0, material.color1, material.color2]
        }
        let opacity: Float = state == .removalPreview ? 0.88 : 1
        let backing = background.isEmpty ? [SIMD3<Float>(repeating: 0.5)] : background
        return contrasting(with: colors.flatMap { color in
            backing.map { bg in
                SIMD3(color.x, color.y, color.z) * opacity + bg * (1 - opacity)
            }
        })
    }
}

/// Matches the subtle superellipse used by both Metal picker renderers.
struct HappeningPickerShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            for step in 0...128 {
                let angle = Double(step) / 128 * 2 * Double.pi
                func coordinate(_ value: Double) -> CGFloat {
                    CGFloat((value < 0 ? -1 : 1) * pow(abs(value), 2 / 2.2))
                }
                let point = CGPoint(
                    x: rect.midX + rect.width / 2 * coordinate(cos(angle)),
                    y: rect.midY + rect.height / 2 * coordinate(sin(angle))
                )
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
    }
}
