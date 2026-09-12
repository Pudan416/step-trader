import SwiftUI
import simd

/// Transparent labels and hit targets over the renderer's fixed ten actors.
struct HappeningShapeField: View {
    let happenings: [Happening]
    let assignments: [String: HappeningEditorialAssignment]
    let layout: HappeningFieldLayout.Layout
    let interaction: HappeningPaletteInteractionState
    let addedIDs: Set<String>
    let onActivate: (Happening) -> Void
    var labelInks: [String: HappeningPaletteLabelInk] = [:]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(happenings.prefix(10).enumerated()), id: \.element.id) { index, happening in
                if index < layout.sources.count {
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
        let locked = assignments[happening.id] == nil || interaction.pendingMutation != nil
        let side = max(44, source.radius * 2)
        let ink = labelInks[happening.id] ?? .dark

        return ZStack {
            Button {
                onActivate(happening)
            } label: {
                Text(happening.localizedTitle())
                    .font(.geist(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: side * 0.80, height: side * 0.76, alignment: .center)
                    // Preview actions never participate in the title's layout.
                    .overlay {
                        if state == .additionPreview || state == .removalPreview {
                            Text(state == .additionPreview ? LocalizedStringKey("Add") : LocalizedStringKey("Delete"))
                                .font(.geist(size: 12, weight: .medium))
                                .accessibilityIdentifier("happening_action_\(happening.id)")
                                .offset(y: side * 0.30)
                        }
                    }
                    .foregroundStyle(ink.color)
                    .frame(width: side, height: side)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .accessibilityLabel(happening.localizedTitle())
            .accessibilityValue(HappeningPaletteAccessibility.value(for: state))
            .accessibilityHint(hint(for: state, locked: locked))
            .accessibilityIdentifier("happening_choice_\(happening.id)")

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
        .position(source.center)
    }

    private func hint(for state: HappeningPaletteSlotVisualState, locked: Bool) -> String {
        if locked { return String(localized: "This happening is temporarily unavailable. Try again.") }
        switch state {
        case .available: return String(localized: "Activate to preview adding to Canvas")
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
