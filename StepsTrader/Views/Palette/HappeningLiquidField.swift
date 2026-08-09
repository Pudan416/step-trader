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

    mutating func resolveBreakthrough(id: String, accepted: Bool) -> Bool {
        guard phase == .sinking, selectedID == id else { return false }
        guard accepted else {
            cancelRemoval()
            return false
        }
        phase = .reflowing
        return true
    }

    mutating func cancelRemoval() {
        phase = .idle
        selectedID = nil
    }
}

/// Session presentation state shared by the field and its surrounding controls.
/// Parent updates refresh metadata, while ids consumed in this mounted session
/// stay consumed even if `onPick` synchronously republishes its old array.
struct HappeningLiquidPresentationState: Equatable {
    private(set) var slotHappenings: [Happening]
    private(set) var presentedHappenings: [Happening]

    private var sessionRemovedIDs: Set<String> = []
    private var pendingParentHappenings: [Happening]?

    init(happenings: [Happening]) {
        let initial = Array(happenings.prefix(10))
        slotHappenings = initial
        presentedHappenings = initial
    }

    var presentedCount: Int {
        presentedHappenings.count
    }

    func layout(in size: CGSize, safeInsets: EdgeInsets) -> HappeningLiquidLayout.Layout {
        HappeningLiquidLayout.layout(
            count: presentedCount,
            in: size,
            safeInsets: safeInsets
        )
    }

    mutating func remove(id: String) -> Bool {
        guard presentedHappenings.contains(where: { $0.id == id }) else { return false }
        sessionRemovedIDs.insert(id)
        presentedHappenings.removeAll { $0.id == id }
        return true
    }

    mutating func receiveParent(_ happenings: [Happening], whileTransitioning: Bool) {
        if whileTransitioning {
            pendingParentHappenings = happenings
        } else {
            mergeParent(happenings)
        }
    }

    mutating func finishTransition() {
        guard let pendingParentHappenings else { return }
        self.pendingParentHappenings = nil
        mergeParent(pendingParentHappenings)
    }

    mutating func reset(with happenings: [Happening]) {
        let initial = Array(happenings.prefix(10))
        slotHappenings = initial
        presentedHappenings = initial
        sessionRemovedIDs.removeAll()
        pendingParentHappenings = nil
    }

    private mutating func mergeParent(_ happenings: [Happening]) {
        let removedIDs = sessionRemovedIDs
        let eligible = Array(
            happenings
                .filter { !removedIDs.contains($0.id) }
                .prefix(10)
        )
        let replacements = Dictionary(uniqueKeysWithValues: happenings.map { ($0.id, $0) })

        slotHappenings = slotHappenings.map { replacements[$0.id] ?? $0 }
        var slotIDs = Set(slotHappenings.map(\.id))
        for happening in eligible where slotIDs.insert(happening.id).inserted {
            slotHappenings.append(happening)
        }
        presentedHappenings = eligible
    }
}

struct HappeningLiquidLabelTreatment: Equatable {
    enum Foreground: Equatable {
        case black
        case white
    }

    static let primaryWeight = 0.72
    static let accentWeight = 0.28

    let red: Double
    let green: Double
    let blue: Double
    let backingLuminance: Double
    let foreground: Foreground

    init(primaryHex: String, accentHex: String) {
        let primary = Self.rgb(ofHex: primaryHex)
        let accent = Self.rgb(ofHex: accentHex)
        red = Self.primaryWeight * primary.red + Self.accentWeight * accent.red
        green = Self.primaryWeight * primary.green + Self.accentWeight * accent.green
        blue = Self.primaryWeight * primary.blue + Self.accentWeight * accent.blue
        backingLuminance = Self.relativeLuminance(red: red, green: green, blue: blue)

        let blackContrast = (backingLuminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (backingLuminance + 0.05)
        foreground = blackContrast >= whiteContrast ? .black : .white
    }

    var backingColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var foregroundColor: Color {
        foreground == .black ? .black : .white
    }

    static func inscribedTextSize(in labelSize: CGSize) -> CGSize {
        CGSize(width: labelSize.width * 0.70, height: labelSize.height * 0.70)
    }

    static func relativeLuminance(ofHex hex: String) -> Double {
        let color = rgb(ofHex: hex)
        return relativeLuminance(red: color.red, green: color.green, blue: color.blue)
    }

    private static func rgb(ofHex hex: String) -> (red: Double, green: Double, blue: Double) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else {
            return (1, 1, 1)
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

enum HappeningLiquidLabelTypography {
    static let font = Font.system(.footnote, design: .rounded, weight: .semibold)

    static func maximumLines(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 2 : 3
    }
}

enum HappeningLiquidContourHitRegion {
    /// Covers the seven-point luminance blur plus antialiasing at the rendered
    /// contour edge. `strokedPath` expands by half its line width.
    private static let haloOutset: CGFloat = 12

    static func path(
        sources: [HappeningLiquidLayout.Source],
        in rect: CGRect
    ) -> Path {
        let contour = ProceduralShapeGenerator.metaballPath(
            blobs: sources.map {
                ProceduralShapeGenerator.BlobSource(
                    center: $0.center,
                    radius: $0.radius
                )
            },
            in: rect,
            gridResolution: 58
        )
        var hitRegion = contour
        hitRegion.addPath(
            contour.strokedPath(
                StrokeStyle(
                    lineWidth: haloOutset * 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        )
        return hitRegion
    }
}

/// Native, transparent renderer for the palette's Living island.
///
/// Domain state changes at breakthrough through `onPick`; the field and parent
/// share session presentation state while surviving sources reflow to the next
/// deterministic layout.
struct HappeningLiquidField: View {
    let happenings: [Happening]
    let dayKey: String
    let highlightedID: String?
    let onPick: (Happening, CGPoint) -> Bool

    @Binding var presentation: HappeningLiquidPresentationState

    private let reduceMotionOverride: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var transition = HappeningLiquidTransitionState()
    @State private var selectedScale: CGFloat = 1
    @State private var sinkProgress: CGFloat = 0
    @State private var sinkPoint: CGPoint = .zero
    @State private var feedbackTick = 0
    @State private var removalTask: Task<Void, Never>?

    private static let pressDuration = 0.12
    private static let sinkDuration = 0.19
    private static let reflowDuration = 0.38
    private static let reducedRemovalDuration = 0.15
    static let warmPaletteIndices = [0, 1, 3, 5, 8, 9, 10, 11, 6, 7]

    init(
        happenings: [Happening],
        presentation: Binding<HappeningLiquidPresentationState>,
        dayKey: String,
        reduceMotionOverride: Bool? = nil,
        highlightedID: String? = nil,
        onPick: @escaping (Happening, CGPoint) -> Bool
    ) {
        self.happenings = happenings
        _presentation = presentation
        self.dayKey = dayKey
        self.reduceMotionOverride = reduceMotionOverride
        self.highlightedID = highlightedID
        self.onPick = onPick
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = presentation.layout(in: proxy.size, safeInsets: proxy.safeAreaInsets)
            let styles = slotStyles
            let liquidHitRegion = HappeningLiquidContourHitRegion.path(
                sources: layout.sources,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack(alignment: .topLeading) {
                HappeningLiquidCanvas(
                    sourceVector: renderVector(for: layout),
                    styles: styles
                )

                liquidHitRegion
                    .fill(.clear)
                    .contentShape(liquidHitRegion)
                    .onTapGesture {}
                    .accessibilityHidden(true)

                ForEach(Array(presentation.presentedHappenings.enumerated()), id: \.element.id) { index, happening in
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
            cancelRemoval()
        }
    }

    private var slotStyles: [HappeningLiquidSlotStyle] {
        presentation.slotHappenings.enumerated().map { index, happening in
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
        guard let index = presentation.slotHappenings.firstIndex(where: { $0.id == happening.id }),
              index < styles.count else {
            return Self.makeStyle(for: happening, index: 0, dayKey: dayKey)
        }
        return styles[index]
    }

    private func renderVector(
        for layout: HappeningLiquidLayout.Layout
    ) -> HappeningLiquidSourceVector {
        let visibleIndices = Dictionary(
            uniqueKeysWithValues: presentation.presentedHappenings.enumerated().map {
                ($0.element.id, $0.offset)
            }
        )

        let sources = presentation.slotHappenings.map { happening -> HappeningLiquidRenderSource in
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
        let isHighlighted = highlightedID == happening.id
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
        let textSize = HappeningLiquidLabelTreatment.inscribedTextSize(in: frame.size)

        return Button {
            beginRemoval(happening, source: source)
        } label: {
            ZStack {
                Ellipse()
                    .fill(style.labelTreatment.backingColor)
                    .overlay {
                        Ellipse().stroke(
                            .white.opacity(isHighlighted ? 0.95 : 0.14),
                            lineWidth: isHighlighted ? 2 : 0.5
                        )
                    }

                Text(happening.localizedTitle())
                    .font(HappeningLiquidLabelTypography.font)
                    .foregroundStyle(style.labelTreatment.foregroundColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(
                        HappeningLiquidLabelTypography.maximumLines(for: dynamicTypeSize)
                    )
                    .minimumScaleFactor(0.78)
                    // This rectangle is inscribed in the opaque ellipse, so
                    // every rendered glyph has a known contrast backing.
                    .frame(width: textSize.width, height: textSize.height)
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .position(center)
        .scaleEffect(scale * (isHighlighted ? 1.08 : 1))
        .opacity(opacity)
        .disabled(transition.phase != .idle)
        .animation(.easeInOut(duration: 0.28), value: isHighlighted)
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
        let accepted = onPick(happening, sinkPoint)
        guard transition.resolveBreakthrough(id: happening.id, accepted: accepted) else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedScale = 1
                sinkProgress = 0
            }
            removalTask = nil
            presentation.finishTransition()
            return
        }

        feedbackTick += 1

        let removeFromPresentation: () -> Void = {
            _ = presentation.remove(id: happening.id)
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
        removalTask = nil
        selectedScale = 1
        sinkProgress = 0
        presentation.finishTransition()
    }

    private func receiveParentHappenings(_ next: [Happening]) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            presentation.receiveParent(next, whileTransitioning: transition.phase != .idle)
        }
    }

    private func cancelRemoval() {
        removalTask?.cancel()
        removalTask = nil

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transition.cancelRemoval()
            selectedScale = 1
            sinkProgress = 0
            presentation.finishTransition()
        }
    }

    static func labelTreatment(forSlot index: Int) -> HappeningLiquidLabelTreatment {
        let hexes = paletteHexes(forSlot: index)
        return HappeningLiquidLabelTreatment(
            primaryHex: hexes.primary,
            accentHex: hexes.accent
        )
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
                labelTreatment: HappeningLiquidLabelTreatment(
                    primaryHex: fallback,
                    accentHex: fallback
                ),
                highlightOffset: .zero
            )
        }

        let hexes = paletteHexes(forSlot: index)
        let seed = CanvasElement.makeSeed(optionId: happening.id, dayKey: dayKey, index: index)
        let unitX = CGFloat(seed & 0xFFFF) / CGFloat(UInt16.max) - 0.5
        let unitY = CGFloat((seed >> 16) & 0xFFFF) / CGFloat(UInt16.max) - 0.5

        return HappeningLiquidSlotStyle(
            primary: Color(hex: hexes.primary),
            accent: Color(hex: hexes.accent),
            labelTreatment: labelTreatment(forSlot: index),
            highlightOffset: CGSize(width: unitX * 0.42, height: unitY * 0.34)
        )
    }

    private static func paletteHexes(forSlot index: Int) -> (primary: String, accent: String) {
        let palette = CanvasColorPalette.paletteHex
        let fallback = AppColors.goldFallbackHex
        guard !palette.isEmpty else { return (fallback, fallback) }

        let normalizedIndex = max(0, index)
        let primaryIndex = warmPaletteIndices[normalizedIndex % warmPaletteIndices.count]
            % palette.count
        let accentIndex = warmPaletteIndices[(normalizedIndex + 3) % warmPaletteIndices.count]
            % palette.count
        return (palette[primaryIndex], palette[accentIndex])
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
    let labelTreatment: HappeningLiquidLabelTreatment
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
    @State private var largerType = false
    @State private var lastPick = "Tap a happening"
    @State private var presentation = HappeningLiquidPresentationState(
        happenings: Array(HappeningDefaults.builtIns.prefix(10))
    )

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
                presentation: $presentation,
                dayKey: "2026-08-09",
                reduceMotionOverride: reduceMotion,
                onPick: { happening, _ in
                    lastPick = happening.localizedTitle()
                    return true
                }
            )
            .environment(\.dynamicTypeSize, largerType ? .accessibility1 : .large)

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach([10, 9, 8], id: \.self) { nextCount in
                        Button("\(nextCount)") {
                            count = nextCount
                            presentation.reset(
                                with: Array(HappeningDefaults.builtIns.prefix(nextCount))
                            )
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                HStack(spacing: 14) {
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                        .toggleStyle(.switch)
                        .font(.caption)

                    Toggle("Larger Type", isOn: $largerType)
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
