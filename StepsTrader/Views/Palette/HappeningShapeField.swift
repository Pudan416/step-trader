import SwiftUI

/// The day's remaining happenings as a loose constellation of colored circles.
/// A first tap previews the assigned canvas figure in place; a second tap adds it.
struct HappeningWordField: View {
    @Binding var presentation: HappeningFieldPresentationState
    let happenings: [Happening]
    let figures: [String: HappeningShapeAssignment]
    let dayPalette: [String]
    let dayKey: String
    let morphNamespace: Namespace.ID
    let contentTopInset: CGFloat?
    let dockCenterY: CGFloat?
    let highlightedID: String?
    let onPick: (Happening, CGPoint) -> Bool

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var labelPointSize: CGFloat =
        HappeningFieldLabelTypography.pointSize

    @Namespace private var itemMorphNamespace
    @State private var transition = HappeningFieldTransitionState()
    @State private var commitScale: CGFloat = 1
    @State private var commitOpacity: CGFloat = 1
    @State private var feedbackTick = 0
    @State private var commitTask: Task<Void, Never>?

    private static let commitDuration = 0.30
    private static let reflowDuration = 0.44

    init(
        presentation: Binding<HappeningFieldPresentationState>,
        happenings: [Happening],
        figures: [String: HappeningShapeAssignment] = [:],
        dayPalette: [String],
        dayKey: String,
        morphNamespace: Namespace.ID,
        contentTopInset: CGFloat? = nil,
        dockCenterY: CGFloat? = nil,
        reduceMotionOverride: Bool? = nil,
        highlightedID: String? = nil,
        onPick: @escaping (Happening, CGPoint) -> Bool
    ) {
        _presentation = presentation
        self.happenings = happenings
        self.figures = figures
        self.dayPalette = dayPalette
        self.dayKey = dayKey
        self.morphNamespace = morphNamespace
        self.contentTopInset = contentTopInset
        self.dockCenterY = dockCenterY
        self.reduceMotionOverride = reduceMotionOverride
        self.highlightedID = highlightedID
        self.onPick = onPick
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = presentation.layout(
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets,
                dynamicTypeSize: dynamicTypeSize,
                contentTopInset: contentTopInset,
                dockCenterY: dockCenterY
            )

            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(presentation.presentedHappenings.enumerated()),
                    id: \.element.id
                ) { index, happening in
                    if index < layout.sources.count {
                        happeningButton(
                            happening,
                            source: layout.sources[index],
                            style: style(for: happening, index: index)
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .sensoryFeedback(.selection, trigger: feedbackTick)
        .onChange(of: happenings) { _, next in
            receiveParentHappenings(next)
        }
        .onDisappear(perform: cancelTransition)
    }

    private var motionIsReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private var resolvedPalette: [String] {
        dayPalette.isEmpty ? [AppColors.goldFallbackHex] : dayPalette
    }

    private func style(for happening: Happening, index: Int) -> HappeningCircleStyle {
        let palette = resolvedPalette
        let assignment = figures[happening.id]
        let primaryHex = assignment?.colorHex ?? palette[index % palette.count]
        let accentHex = assignment.map {
            CanvasColorPalette.happeningGradientSecondColor(
                seed: $0.seed,
                primary: $0.colorHex
            )
        } ?? palette[(index + 2) % palette.count]
        return HappeningCircleStyle(
            primary: Color(hex: primaryHex),
            accent: Color(hex: accentHex)
        )
    }

    private func happeningButton(
        _ happening: Happening,
        source: HappeningFieldLayout.Source,
        style: HappeningCircleStyle
    ) -> some View {
        let isSelected = transition.selectedID == happening.id
        let isCommitting = isSelected && transition.phase == .committing
        let side = source.radius * 2

        return Button {
            handleTap(happening, at: source.center)
        } label: {
            ZStack {
                if isSelected {
                    previewShape(for: happening, side: side * 1.24, style: style)
                        .matchedGeometryEffect(id: happening.id, in: itemMorphNamespace)
                        .transition(.scale(scale: 0.86).combined(with: .opacity))
                } else {
                    happeningCircle(happening, side: side, style: style)
                        .matchedGeometryEffect(id: happening.id, in: itemMorphNamespace)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: side * 1.28, height: side * 1.28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: max(44, side), height: max(44, side))
        .position(source.center)
        .scaleEffect(isCommitting ? commitScale : (highlightedID == happening.id ? 1.08 : 1))
        .opacity(isCommitting ? commitOpacity : 1)
        .disabled(transition.isInteractionLocked)
        .animation(.spring(response: 0.44, dampingFraction: 0.82), value: isSelected)
        .animation(.easeInOut(duration: 0.28), value: highlightedID == happening.id)
        .accessibilityLabel(happening.localizedTitle())
        .accessibilityValue(isSelected ? "Preview. Tap again to add" : "")
        .accessibilityHint(isSelected ? "Tap again to add to the canvas" : "Shows the canvas shape")
        .accessibilityIdentifier("happening_choice_\(happening.id)")
    }

    private func happeningCircle(
        _ happening: Happening,
        side: CGFloat,
        style: HappeningCircleStyle
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [style.primary, style.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.14), .white.opacity(0.02), .clear],
                        center: UnitPoint(x: 0.30, y: 0.22),
                        startRadius: 0,
                        endRadius: side * 0.72
                    )
                )
                .blendMode(.screen)
            Image("Grain")
                .resizable()
                .scaledToFill()
                .opacity(0.12)
                .blendMode(.softLight)
                .clipShape(Circle())
            Circle()
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.75)

            Text(happening.localizedTitle().replacingOccurrences(of: " ", with: "\n"))
                .font(.onest(size: labelPointSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.94))
                .shadow(color: .black.opacity(0.24), radius: 2, y: 1)
                .multilineTextAlignment(.center)
                .lineLimit(HappeningFieldLabelTypography.maximumLines(for: dynamicTypeSize))
                .minimumScaleFactor(HappeningFieldLabelTypography.minimumScaleFactor(for: dynamicTypeSize))
                .frame(width: side * 0.88, height: side * 0.82)
        }
        .frame(width: side, height: side)
        .saturation(1.10)
        .shadow(color: style.primary.opacity(0.16), radius: 12, y: 6)
    }

    @ViewBuilder
    private func previewShape(
        for happening: Happening,
        side: CGFloat,
        style: HappeningCircleStyle
    ) -> some View {
        if let assignment = figures[happening.id] {
            VStack(spacing: -2) {
                if assignment.shapeType == .rays {
                    HeartRayPreview(
                        seed: assignment.seed,
                        colors: [Color(hex: assignment.colorHex), style.accent]
                    )
                    .frame(width: side * 1.05, height: side * 1.05)
                    .scaleEffect(1.65)
                } else {
                    materializedPreviewTile(
                        for: happening,
                        assignment: assignment,
                        side: side * 1.28,
                        style: style
                    )
                    .id(assignment)
                }

                Text("Tap again to add", comment: "Happening preview confirmation hint")
                    .font(.geist(.caption2))
                    .foregroundStyle(AppColors.Night.textPrimary.opacity(0.86))
                    .fixedSize()
            }
            .shadow(color: style.primary.opacity(0.14), radius: 7, y: 3)
        } else {
            Circle()
                .fill(style.primary)
                .frame(width: side * 0.78, height: side * 0.78)
        }
    }

    private func materializedPreviewTile(
        for happening: Happening,
        assignment: HappeningShapeAssignment,
        side: CGFloat,
        style: HappeningCircleStyle
    ) -> some View {
        let element = HappeningShapeTile.previewElement(
            optionId: happening.id,
            label: happening.localizedTitle(),
            shapeType: assignment.shapeType,
            colorHex: assignment.colorHex,
            seed: assignment.seed,
            rotation: assignment.rotation
        )
        let mask = HappeningPreviewShapeMask(element: element, side: side)

        return ZStack {
            LinearGradient(
                colors: [
                    style.primary,
                    style.accent,
                    style.primary.opacity(0.88),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: side, height: side)
            .overlay(.white.opacity(0.12))
            .mask(mask)

            Image("Grain")
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .opacity(0.13)
                .blendMode(.softLight)
                .mask(HappeningPreviewShapeMask(element: element, side: side))
        }
        .frame(width: side, height: side)
        .saturation(1.16)
    }

    private func handleTap(_ happening: Happening, at center: CGPoint) {
        let decision = transition.handleTap(id: happening.id)
        switch decision {
        case .preview, .switchPreview:
            feedbackTick += 1
        case .commit:
            feedbackTick += 1
            beginCommit(happening, at: center)
        case .ignored:
            break
        }
    }

    private func beginCommit(_ happening: Happening, at center: CGPoint) {
        commitTask?.cancel()
        commitScale = 1
        commitOpacity = 1
        commitTask = Task { @MainActor in
            if motionIsReduced {
                commitOpacity = 0
            } else {
                withAnimation(.easeInOut(duration: Self.commitDuration)) {
                    commitScale = 0.88
                    commitOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }

            let accepted = onPick(happening, center)
            guard transition.resolveCommit(id: happening.id, accepted: accepted) else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                    commitScale = 1
                    commitOpacity = 1
                }
                commitTask = nil
                presentation.finishTransition()
                return
            }

            let remove = { _ = presentation.remove(id: happening.id) }
            if motionIsReduced {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction, remove)
            } else {
                withAnimation(.spring(response: Self.reflowDuration, dampingFraction: 0.82)) {
                    remove()
                }
                try? await Task.sleep(for: .milliseconds(440))
                guard !Task.isCancelled else { return }
            }

            _ = transition.finishCommit(id: happening.id)
            commitScale = 1
            commitOpacity = 1
            commitTask = nil
            presentation.finishTransition()
        }
    }

    private func receiveParentHappenings(_ next: [Happening]) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.receiveParent(next, whileTransitioning: transition.phase != .idle)
        }
    }

    private func cancelTransition() {
        commitTask?.cancel()
        commitTask = nil
        transition.cancelSelection()
        commitScale = 1
        commitOpacity = 1
        presentation.finishTransition()
    }
}

private struct HappeningCircleStyle {
    let primary: Color
    let accent: Color
}

/// Converts the production renderer's translucent large-canvas layers into a
/// crisp opaque silhouette suitable for the small confirmation preview. The
/// contour is still the exact assigned figure; only its preview alpha changes.
private struct HappeningPreviewShapeMask: View {
    let element: CanvasElement
    let side: CGFloat

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            context.addFilter(.alphaThreshold(min: 0.14, color: .white))
            guard let symbol = context.resolveSymbol(id: 0) else { return }
            context.draw(symbol, at: CGPoint(x: size.width / 2, y: size.height / 2))
        } symbols: {
            HappeningShapeTile(element: element, side: side)
                .tag(0)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}

#if DEBUG
private struct HappeningWordFieldPreviewHarness: View {
    @Namespace private var morphNamespace
    @State private var presentation = HappeningFieldPresentationState(
        happenings: HappeningDefaults.builtIns
    )

    private let dayKey = "2026-09-05"

    var body: some View {
        ZStack {
            Color(hex: "#103D3F").ignoresSafeArea()
            HappeningWordField(
                presentation: $presentation,
                happenings: HappeningDefaults.builtIns,
                figures: HappeningShapeRoll.assignments(
                    for: HappeningDefaults.builtIns.map(\.id),
                    dayKey: dayKey,
                    nonce: 0
                ),
                dayPalette: DayComposition.forDay(dayKey: dayKey, happeningCount: 0).palette,
                dayKey: dayKey,
                morphNamespace: morphNamespace,
                contentTopInset: 180,
                onPick: { _, _ in true }
            )
        }
    }
}

#Preview("Happening circles") {
    HappeningWordFieldPreviewHarness()
}
#endif
