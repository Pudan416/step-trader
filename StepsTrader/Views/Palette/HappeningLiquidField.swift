import SwiftUI

enum RemovalPhase: Equatable {
    case idle
    case pressing
    case sinking
    case reflowing
}

struct HappeningLiquidTransitionState: Equatable {
    private(set) var phase: RemovalPhase = .idle
    private(set) var selectedID: String?

    mutating func beginRemoval(id: String) -> Bool {
        guard phase == .idle else { return false }
        selectedID = id
        phase = .pressing
        return true
    }

    mutating func advanceRemoval(id: String, to nextPhase: RemovalPhase) -> Bool {
        guard selectedID == id else { return false }

        switch (phase, nextPhase) {
        case (.pressing, .sinking), (.sinking, .reflowing):
            phase = nextPhase
            return true
        default:
            return false
        }
    }

    mutating func finishRemoval(id: String) -> Bool {
        guard phase == .reflowing, selectedID == id else { return false }
        phase = .idle
        selectedID = nil
        return true
    }
}

/// Native, transparent renderer for the palette's Living island.
///
/// The view owns only presentation state. Domain state changes at breakthrough
/// through `onPick`; the field then remains mounted while its surviving sources
/// reflow to the next deterministic layout.
struct HappeningLiquidField: View {
    let happenings: [Happening]
    let dayKey: String
    let onPick: (Happening, CGPoint) -> Void

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var slotHappenings: [Happening]
    @State private var presentedHappenings: [Happening]
    @State private var transition = HappeningLiquidTransitionState()
    @State private var selectedScale: CGFloat = 1
    @State private var sinkProgress: CGFloat = 0
    @State private var sinkPoint: CGPoint = .zero
    @State private var feedbackTick = 0
    @State private var pendingParentHappenings: [Happening]?
    @State private var removalTask: Task<Void, Never>?

    private static let pressDuration = 0.12
    private static let sinkDuration = 0.19
    private static let reflowDuration = 0.38
    private static let reducedRemovalDuration = 0.15
    private static let warmPaletteIndices = [0, 1, 3, 5, 8, 9, 10, 11, 6, 7]

    init(
        happenings: [Happening],
        dayKey: String,
        reduceMotionOverride: Bool? = nil,
        onPick: @escaping (Happening, CGPoint) -> Void
    ) {
        let initial = Array(happenings.prefix(10))
        self.happenings = happenings
        self.dayKey = dayKey
        self.reduceMotionOverride = reduceMotionOverride
        self.onPick = onPick
        _slotHappenings = State(initialValue: initial)
        _presentedHappenings = State(initialValue: initial)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = HappeningLiquidLayout.layout(
                count: presentedHappenings.count,
                in: proxy.size,
                safeInsets: proxy.safeAreaInsets
            )
            let styles = slotStyles

            ZStack(alignment: .topLeading) {
                HappeningLiquidCanvas(
                    sourceVector: renderVector(for: layout),
                    styles: styles
                )

                ForEach(Array(presentedHappenings.enumerated()), id: \.element.id) { index, happening in
                    if index < layout.sources.count, index < layout.labelFrames.count {
                        labelButton(
                            happening: happening,
                            source: layout.sources[index],
                            frame: layout.labelFrames[index],
                            style: style(for: happening, in: styles)
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.clear)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTick)
        .onChange(of: happenings) { _, next in
            receiveParentHappenings(next)
        }
        .onDisappear {
            removalTask?.cancel()
        }
    }

    private var slotStyles: [HappeningLiquidSlotStyle] {
        slotHappenings.enumerated().map { index, happening in
            Self.makeStyle(for: happening, index: index, dayKey: dayKey)
        }
    }

    private var motionIsReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private func style(
        for happening: Happening,
        in styles: [HappeningLiquidSlotStyle]
    ) -> HappeningLiquidSlotStyle {
        guard let index = slotHappenings.firstIndex(where: { $0.id == happening.id }),
              index < styles.count else {
            return Self.makeStyle(for: happening, index: 0, dayKey: dayKey)
        }
        return styles[index]
    }

    private func renderVector(
        for layout: HappeningLiquidLayout.Layout
    ) -> HappeningLiquidSourceVector {
        let visibleIndices = Dictionary(
            uniqueKeysWithValues: presentedHappenings.enumerated().map { ($0.element.id, $0.offset) }
        )

        let sources = slotHappenings.map { happening -> HappeningLiquidRenderSource in
            guard let visibleIndex = visibleIndices[happening.id],
                  visibleIndex < layout.sources.count else {
                return HappeningLiquidRenderSource(
                    center: sinkPoint,
                    radius: 0,
                    opacity: 0
                )
            }

            let source = layout.sources[visibleIndex]
            guard transition.selectedID == happening.id else {
                return HappeningLiquidRenderSource(
                    center: source.center,
                    radius: source.radius,
                    opacity: 1
                )
            }

            switch transition.phase {
            case .idle:
                return HappeningLiquidRenderSource(
                    center: source.center,
                    radius: source.radius,
                    opacity: 1
                )
            case .pressing:
                return HappeningLiquidRenderSource(
                    center: source.center,
                    radius: source.radius * selectedScale,
                    opacity: 1
                )
            case .sinking:
                if motionIsReduced {
                    return HappeningLiquidRenderSource(
                        center: source.center,
                        radius: source.radius,
                        opacity: 1 - sinkProgress
                    )
                }
                return HappeningLiquidRenderSource(
                    center: Self.interpolate(source.center, sinkPoint, progress: sinkProgress),
                    radius: source.radius * selectedScale * (1 - sinkProgress),
                    opacity: 1 - sinkProgress
                )
            case .reflowing:
                return HappeningLiquidRenderSource(
                    center: sinkPoint,
                    radius: 0,
                    opacity: 0
                )
            }
        }

        return HappeningLiquidSourceVector(sources: sources)
    }

    private func labelButton(
        happening: Happening,
        source: HappeningLiquidLayout.Source,
        frame: CGRect,
        style: HappeningLiquidSlotStyle
    ) -> some View {
        let isSelected = transition.selectedID == happening.id
        let progress = isSelected && transition.phase == .sinking ? sinkProgress : 0
        let center = motionIsReduced
            ? CGPoint(x: frame.midX, y: frame.midY)
            : Self.interpolate(CGPoint(x: frame.midX, y: frame.midY), sinkPoint, progress: progress)
        let opacity = isSelected && transition.phase == .sinking ? 1 - sinkProgress : 1
        let scale: CGFloat
        if isSelected && transition.phase == .pressing {
            scale = selectedScale
        } else if isSelected && transition.phase == .sinking && !motionIsReduced {
            scale = selectedScale * (1 - sinkProgress * 0.25)
        } else {
            scale = 1
        }
        let usesDarkText = style.sampledLuminance >= 0.18

        return Button {
            beginRemoval(happening, source: source)
        } label: {
            Text(happening.localizedTitle())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    usesDarkText ? Color.black.opacity(0.84) : Color.white.opacity(0.94)
                )
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(width: frame.width, height: frame.height)
                .contentShape(Rectangle())
                .shadow(
                    color: usesDarkText ? .white.opacity(0.10) : .black.opacity(0.18),
                    radius: 1,
                    y: 1
                )
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .position(center)
        .scaleEffect(scale)
        .opacity(opacity)
        .disabled(transition.phase != .idle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(happening.localizedTitle())
        .accessibilityAddTraits(.isButton)
    }

    private func beginRemoval(
        _ happening: Happening,
        source: HappeningLiquidLayout.Source
    ) {
        guard transition.beginRemoval(id: happening.id) else { return }

        sinkPoint = CGPoint(
            x: source.center.x,
            y: source.center.y + source.radius * 0.42
        )
        sinkProgress = 0
        selectedScale = 1
        removalTask?.cancel()
        removalTask = Task { @MainActor in
            if motionIsReduced {
                await performReducedRemoval(happening)
            } else {
                await performLivingRemoval(happening)
            }
        }
    }

    @MainActor
    private func performLivingRemoval(_ happening: Happening) async {
        withAnimation(.easeOut(duration: Self.pressDuration)) {
            selectedScale = 0.92
        }
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled,
              transition.advanceRemoval(id: happening.id, to: .sinking) else { return }

        withAnimation(.easeIn(duration: Self.sinkDuration)) {
            sinkProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(190))
        guard !Task.isCancelled else { return }

        await breakthrough(happening, animatedReflow: true)
    }

    @MainActor
    private func performReducedRemoval(_ happening: Happening) async {
        guard transition.advanceRemoval(id: happening.id, to: .sinking) else { return }
        withAnimation(.easeOut(duration: Self.reducedRemovalDuration)) {
            sinkProgress = 1
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        await breakthrough(happening, animatedReflow: false)
    }

    @MainActor
    private func breakthrough(_ happening: Happening, animatedReflow: Bool) async {
        guard transition.advanceRemoval(id: happening.id, to: .reflowing) else { return }

        feedbackTick += 1
        onPick(happening, sinkPoint)

        let removeFromPresentation = {
            presentedHappenings.removeAll { $0.id == happening.id }
        }
        if animatedReflow {
            withAnimation(.spring(duration: Self.reflowDuration, bounce: 0.20)) {
                removeFromPresentation()
            }
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                removeFromPresentation()
            }
        }

        guard transition.finishRemoval(id: happening.id) else { return }
        selectedScale = 1
        sinkProgress = 0
        applyPendingParentHappenings()
    }

    private func receiveParentHappenings(_ next: [Happening]) {
        let limited = Array(next.prefix(10))
        guard transition.phase == .idle else {
            pendingParentHappenings = limited
            return
        }
        synchronizePresentation(with: limited)
    }

    private func applyPendingParentHappenings() {
        guard let pendingParentHappenings else { return }
        self.pendingParentHappenings = nil
        synchronizePresentation(with: pendingParentHappenings)
    }

    private func synchronizePresentation(with next: [Happening]) {
        let nextIDs = next.map(\.id)
        let presentedIDs = presentedHappenings.map(\.id)

        if nextIDs == presentedIDs {
            let replacements = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
            slotHappenings = slotHappenings.map { replacements[$0.id] ?? $0 }
            presentedHappenings = next
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                slotHappenings = next
                presentedHappenings = next
            }
        }
    }

    private static func makeStyle(
        for happening: Happening,
        index: Int,
        dayKey: String
    ) -> HappeningLiquidSlotStyle {
        let palette = CanvasColorPalette.paletteHex
        let fallback = AppColors.goldFallbackHex
        guard !palette.isEmpty else {
            return HappeningLiquidSlotStyle(
                primary: Color(hex: fallback),
                accent: Color(hex: fallback),
                sampledLuminance: HappeningPaletteView.relativeLuminance(ofHex: fallback),
                highlightOffset: .zero
            )
        }

        let primaryIndex = warmPaletteIndices[index % warmPaletteIndices.count] % palette.count
        let accentIndex = warmPaletteIndices[(index + 3) % warmPaletteIndices.count] % palette.count
        let primaryHex = palette[primaryIndex]
        let accentHex = palette[accentIndex]
        let seed = CanvasElement.makeSeed(optionId: happening.id, dayKey: dayKey, index: index)
        let unitX = CGFloat(seed & 0xFFFF) / CGFloat(UInt16.max) - 0.5
        let unitY = CGFloat((seed >> 16) & 0xFFFF) / CGFloat(UInt16.max) - 0.5

        return HappeningLiquidSlotStyle(
            primary: Color(hex: primaryHex),
            accent: Color(hex: accentHex),
            sampledLuminance: 0.72 * HappeningPaletteView.relativeLuminance(ofHex: primaryHex)
                + 0.28 * HappeningPaletteView.relativeLuminance(ofHex: accentHex),
            highlightOffset: CGSize(width: unitX * 0.42, height: unitY * 0.34)
        )
    }

    private static func interpolate(
        _ start: CGPoint,
        _ end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }
}

private struct HappeningLiquidSlotStyle {
    let primary: Color
    let accent: Color
    let sampledLuminance: Double
    /// Unit-space offset, scaled by the source radius during drawing.
    let highlightOffset: CGSize
}

private struct HappeningLiquidRenderSource {
    let center: CGPoint
    let radius: CGFloat
    let opacity: CGFloat
}

private struct HappeningLiquidCanvas: View, Animatable {
    var sourceVector: HappeningLiquidSourceVector
    let styles: [HappeningLiquidSlotStyle]

    var animatableData: HappeningLiquidSourceVector {
        get { sourceVector }
        set { sourceVector = newValue }
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let sources = sourceVector.sources
            let visible = sources.enumerated().filter {
                $0.element.radius > 0.5 && $0.element.opacity > 0.005 && $0.offset < styles.count
            }
            guard !visible.isEmpty else { return }

            let contour = ProceduralShapeGenerator.metaballPath(
                blobs: visible.map {
                    ProceduralShapeGenerator.BlobSource(
                        center: $0.element.center,
                        radius: $0.element.radius
                    )
                },
                in: CGRect(origin: .zero, size: size),
                gridResolution: 58
            )
            let maximumOpacity = Double(visible.map(\.element.opacity).max() ?? 0)

            context.fill(
                contour,
                with: .color(Color.white.opacity(0.025 * maximumOpacity))
            )

            context.drawLayer { mesh in
                mesh.clip(to: contour)
                mesh.addFilter(.blur(radius: 2.5))

                for (slotIndex, source) in visible {
                    let style = styles[slotIndex]
                    let sourceOpacity = Double(source.opacity)
                    let reach = source.radius * 1.72
                    let gradientCenter = CGPoint(
                        x: source.center.x + style.highlightOffset.width * source.radius,
                        y: source.center.y + style.highlightOffset.height * source.radius
                    )
                    let paintBounds = CGRect(
                        x: source.center.x - reach,
                        y: source.center.y - reach,
                        width: reach * 2,
                        height: reach * 2
                    )
                    mesh.fill(
                        Path(ellipseIn: paintBounds),
                        with: .radialGradient(
                            Gradient(stops: [
                                .init(color: style.primary.opacity(0.88 * sourceOpacity), location: 0),
                                .init(color: style.accent.opacity(0.62 * sourceOpacity), location: 0.52),
                                .init(color: style.primary.opacity(0.18 * sourceOpacity), location: 0.82),
                                .init(color: .clear, location: 1),
                            ]),
                            center: gradientCenter,
                            startRadius: 0,
                            endRadius: reach
                        )
                    )
                }
            }

            context.drawLayer { luminance in
                luminance.clip(to: contour)
                luminance.blendMode = .screen
                luminance.opacity = 0.12
                luminance.addFilter(.luminanceToAlpha)
                luminance.addFilter(.blur(radius: 7))

                for (slotIndex, source) in visible {
                    let style = styles[slotIndex]
                    let glowRadius = source.radius * 0.82
                    let glowCenter = CGPoint(
                        x: source.center.x + style.highlightOffset.width * source.radius,
                        y: source.center.y + style.highlightOffset.height * source.radius
                    )
                    luminance.fill(
                        Path(ellipseIn: CGRect(
                            x: glowCenter.x - glowRadius,
                            y: glowCenter.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [
                                Color.white.opacity(Double(source.opacity)),
                                Color.clear,
                            ]),
                            center: glowCenter,
                            startRadius: 0,
                            endRadius: glowRadius
                        )
                    )
                }
            }

            context.stroke(
                contour,
                with: .color(Color.white.opacity(0.16 * maximumOpacity)),
                lineWidth: 0.75
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HappeningLiquidSourceVector: VectorArithmetic {
    var values: [Double]

    init(sources: [HappeningLiquidRenderSource]) {
        values = sources.flatMap {
            [Double($0.center.x), Double($0.center.y), Double($0.radius), Double($0.opacity)]
        }
    }

    private init(values: [Double]) {
        self.values = values
    }

    static var zero: HappeningLiquidSourceVector {
        HappeningLiquidSourceVector(values: [])
    }

    static func + (
        lhs: HappeningLiquidSourceVector,
        rhs: HappeningLiquidSourceVector
    ) -> HappeningLiquidSourceVector {
        var result = lhs
        result += rhs
        return result
    }

    static func - (
        lhs: HappeningLiquidSourceVector,
        rhs: HappeningLiquidSourceVector
    ) -> HappeningLiquidSourceVector {
        var result = lhs
        result -= rhs
        return result
    }

    static func += (
        lhs: inout HappeningLiquidSourceVector,
        rhs: HappeningLiquidSourceVector
    ) {
        lhs.combine(with: rhs, operation: +)
    }

    static func -= (
        lhs: inout HappeningLiquidSourceVector,
        rhs: HappeningLiquidSourceVector
    ) {
        lhs.combine(with: rhs, operation: -)
    }

    mutating func scale(by rhs: Double) {
        for index in values.indices {
            values[index] *= rhs
        }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    var sources: [HappeningLiquidRenderSource] {
        stride(from: 0, to: values.count, by: 4).compactMap { offset in
            guard offset + 3 < values.count else { return nil }
            return HappeningLiquidRenderSource(
                center: CGPoint(x: values[offset], y: values[offset + 1]),
                radius: CGFloat(values[offset + 2]),
                opacity: CGFloat(values[offset + 3])
            )
        }
    }

    private mutating func combine(
        with other: HappeningLiquidSourceVector,
        operation: (Double, Double) -> Double
    ) {
        let count = max(values.count, other.values.count)
        if values.count < count {
            values.append(contentsOf: repeatElement(0, count: count - values.count))
        }
        for index in 0..<count {
            let rhs = index < other.values.count ? other.values[index] : 0
            values[index] = operation(values[index], rhs)
        }
    }
}

#if DEBUG
private struct HappeningLiquidFieldPreviewHarness: View {
    @State private var count = 10
    @State private var reduceMotion = false
    @State private var revision = 0
    @State private var lastPick = "Tap a happening"

    private var previewHappenings: [Happening] {
        Array(HappeningDefaults.builtIns.prefix(count))
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(hex: CanvasColorPalette.paletteHex[27]).opacity(0.76),
                    Color(hex: CanvasColorPalette.paletteHex[14]).opacity(0.64),
                    Color(hex: CanvasColorPalette.paletteHex[1]).opacity(0.44),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HappeningLiquidField(
                happenings: previewHappenings,
                dayKey: "2026-08-09",
                reduceMotionOverride: reduceMotion,
                onPick: { happening, _ in lastPick = happening.localizedTitle() }
            )
            .id(revision)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach([10, 9, 8], id: \.self) { nextCount in
                        Button("\(nextCount)") {
                            count = nextCount
                            revision += 1
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Toggle("Reduce Motion", isOn: $reduceMotion)
                        .toggleStyle(.switch)
                        .font(.caption)
                }

                Text(lastPick)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }
}

#Preview("Living island — 10→9→8") {
    HappeningLiquidFieldPreviewHarness()
}
#endif
