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
    @State private var retiringPreviews = HappeningPaletteRetiringPreviews()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .onChange(of: interaction.armedMutation) { old, new in
            guard let old, old != new else { return }
            let token = retiringPreviews.retire(old)
            let delay = HappeningPaletteTransitionTimeline.hitRetirementDuration(reduceMotion: reduceMotion)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                retiringPreviews.expire(id: old.id, token: token)
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
        let retiringState = retiringPreviews.state(for: happening.id)
        let hitShape = HappeningPickerHitShape.make(
            side: side, assignment: assignments[happening.id], state: state, reduceMotion: reduceMotion,
            retiringState: retiringState)
        let hitSize = hitShape.size
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
                    .modifier(HappeningFigureLabelHalo(isEnabled: state != .available || retiringState != nil, ink: ink))
                    // Preview actions are high contrast and remain outside the
                    // title's layout so the figure and caption do not jump.
                    .overlay {
                        if state.awaitsConfirmation {
                            Label(
                                state == .additionPreview ? LocalizedStringKey("Add") : LocalizedStringKey("Delete"),
                                systemImage: state == .additionPreview ? "plus" : "trash"
                            )
                                .font(.geist(size: 13, weight: .bold))
                                .frame(width: HappeningPickerHitShape.actionSize.width,
                                       height: HappeningPickerHitShape.actionSize.height)
                                .foregroundStyle(.white)
                                .background(.black.opacity(0.94), in: Capsule())
                                .overlay(Capsule().strokeBorder(.white.opacity(0.95), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                                .accessibilityIdentifier("happening_action_\(happening.id)")
                                .offset(y: HappeningPickerHitShape.actionOffset(side: side))
                        }
                    }
                    .foregroundStyle(ink.color)
                    .frame(width: hitSize.width, height: hitSize.height)
                    .contentShape(hitShape)
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
        // The current visible action owns overlaps, including a previous
        // preview's returning envelope; ordinary neighbors stay below both.
        .zIndex(hitShape.priority)
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

/// Plain circles supply a light backing. Reserve the two offscreen shadow
/// passes for labels on revealed pigments, where the halo preserves contrast.
private struct HappeningFigureLabelHalo: ViewModifier {
    let isEnabled: Bool
    let ink: HappeningPaletteLabelInk

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .shadow(color: ink == .light ? .black.opacity(0.8) : .white.opacity(0.8), radius: 2, x: 0, y: 0)
                .shadow(color: ink == .light ? .black.opacity(0.55) : .white.opacity(0.55), radius: 4, x: 0, y: 1)
        } else {
            content
        }
    }
}

/// The action is offset below the caption, so its lower corners can extend
/// beyond the figure. Keep its full visible capsule inside the same button.
struct HappeningPickerHitShape: Shape {
    static let actionSize = CGSize(width: 100, height: 44)
    let side: CGFloat
    let showsAction: Bool
    var figurePoints: [SIMD2<Float>] = []
    var figureScale: CGFloat = 1
    var retainsPreviewEnvelope = false

    var priority: Double { showsAction ? 2 : retainsPreviewEnvelope ? 1 : 0 }

    var size: CGSize {
        let base = Self.size(side: side, showsAction: showsAction)
        let reachX = figurePoints.reduce(CGFloat(0)) { max($0, abs(CGFloat($1.x))) } * side * figureScale
        let reachY = figurePoints.reduce(CGFloat(0)) { max($0, abs(CGFloat($1.y))) } * side * figureScale
        return CGSize(width: max(base.width, reachX), height: max(base.height, reachY))
    }

    static func make(side: CGFloat, assignment: HappeningEditorialAssignment?,
                     state: HappeningPaletteSlotVisualState, reduceMotion: Bool,
                     retiringState: HappeningPaletteSlotVisualState? = nil) -> Self {
        let envelopeState = state.awaitsConfirmation ? state : retiringState ?? state
        return Self(side: side, showsAction: state.awaitsConfirmation,
             figurePoints: envelopeState == .available ? [] : assignment.map(figurePoints) ?? [],
             figureScale: CGFloat(HappeningPaletteRenderControls.hitScale(for: envelopeState, reduceMotion: reduceMotion)),
             retainsPreviewEnvelope: retiringState != nil)
    }

    /// The native renderer rotates the frozen contour by its GPU direction,
    /// which is deliberately independent of the original Canvas placement.
    private static func figurePoints(_ assignment: HappeningEditorialAssignment) -> [SIMD2<Float>] {
        guard let native = assignment.nativeActor else { return [] }
        let rotation: Float = assignment.silhouette.variant == 0 ? .pi / 2 : -assignment.silhouette.rotation
        let cosine = cos(rotation), sine = sin(rotation)
        return MetalShapeContour.sample(uniforms: native.geometry).map { point in
            SIMD2(point.x * cosine - point.y * sine, point.x * sine + point.y * cosine)
        }
    }

    static func actionOffset(side: CGFloat) -> CGFloat { min(side * 0.31, 38) }

    static func size(side: CGFloat, showsAction: Bool) -> CGSize {
        guard showsAction else { return CGSize(width: side, height: side) }
        return CGSize(width: max(side, actionSize.width),
                      height: max(side, 2 * actionOffset(side: side) + actionSize.height))
    }

    func path(in rect: CGRect) -> Path {
        var path = HappeningPickerShape().path(in: CGRect(
            x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        // Keep the nominal label target as well: concave or contour artwork
        // must not punch holes through its caption. Only revealed figures add
        // their own contour; available neighbors retain the original target.
        if let first = figurePoints.first {
            var figure = Path()
            func point(_ value: SIMD2<Float>) -> CGPoint {
                CGPoint(x: rect.midX + CGFloat(value.x) * side / 2 * figureScale,
                        y: rect.midY + CGFloat(value.y) * side / 2 * figureScale)
            }
            figure.move(to: point(first))
            for value in figurePoints.dropFirst() { figure.addLine(to: point(value)) }
            figure.closeSubpath()
            path.addPath(figure)
        }
        if showsAction {
            path.addPath(Capsule().path(in: CGRect(
                x: rect.midX - Self.actionSize.width / 2,
                y: rect.midY + Self.actionOffset(side: side) - Self.actionSize.height / 2,
                width: Self.actionSize.width, height: Self.actionSize.height)))
        }
        return path
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
