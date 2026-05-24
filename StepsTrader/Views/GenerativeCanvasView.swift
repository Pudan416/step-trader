import SwiftUI
import os

// MARK: - Generative Canvas View (main rendering engine)

struct GenerativeCanvasView: View {
    let elements: [CanvasElement]
    let sleepPoints: Int
    let stepsPoints: Int
    let sleepColor: Color
    let stepsColor: Color
    let decayNorm: Double
    var backgroundColor: Color = Color.black
    /// Color for element labels on each blob; nil = auto from background.
    var labelColor: Color?
    /// Whether to show labels directly on canvas elements
    var showLabelsOnCanvas: Bool = true
    /// Whether labels are rendered with an outlined shadow halo for readability.
    var showsOutlinedLabels: Bool = true
    /// When false, only canvas elements are rendered (no radial background gradient).
    var showsBackgroundGradient: Bool = true
    /// Whether HealthKit has returned step data today (do not infer from points alone).
    var hasStepsData: Bool = true
    /// Whether HealthKit has returned sleep data today (do not infer from points alone).
    var hasSleepData: Bool = true
    /// Amplitude multiplier for drift/wobble (1.0 = normal, 0.25 = subdued for label/edit mode).
    var timeScale: Double = 1.0
    /// When non-nil, renders a single static frame at this time instead of using
    /// TimelineView animation.  Used for ImageRenderer snapshots (e.g. canvas export)
    /// and for the history canvas viewer (live view, Metal shaders available).
    var fixedTime: Date? = nil
    /// Set to `true` when rendering inside `ImageRenderer` or any offscreen context
    /// where Metal shaders silently produce blank output. When `false` (live view),
    /// Metal shader symbols are still provided even with `fixedTime` so ray elements
    /// use the real spotlight shader instead of the software fallback.
    var isOffscreenRender: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ampScale: Double = 1.0

    /// Per-instance render cache. Held in `@State` so the same instance
    /// persists across SwiftUI body recompositions; mutating its properties
    /// See `CanvasRenderCache.swift` for the `RenderCache` class definition.
    @State private var renderCache = RenderCache()

    private var isDarkBackground: Bool {
        var b: CGFloat = 0
        UIColor(backgroundColor).getHue(nil, saturation: nil, brightness: &b, alpha: nil)
        return b < 0.5
    }

    private var elementBlendMode: GraphicsContext.BlendMode {
        isDarkBackground ? .plusLighter : .normal
    }

    private var effectiveLabelColor: Color {
        labelColor ?? (isDarkBackground ? .white : .black)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body
    // ═══════════════════════════════════════════════════════════

    /// Elements whose resolved shape type is `.rays` — needed for spotlight symbols.
    private var rayElements: [CanvasElement] {
        elements.filter { $0.resolvedShapeType == .rays }
    }

    private func shapeType(for element: CanvasElement) -> CanvasShapeType {
        element.resolvedShapeType
    }

    var body: some View {
        if let fixedTime {
            let t = fixedTime.timeIntervalSinceReferenceDate
            if isOffscreenRender {
                // ImageRenderer / offscreen: Metal shaders silently produce blank
                // output. Omit the symbols closure so resolveSymbol returns nil and
                // RayShapeRenderer falls through to the software cone renderer.
                Canvas { context, size in
                    renderCanvas(context: &context, size: size, t: t)
                }
                .drawingGroup()
                .background(Color.clear)
                .canvasAnimationScale($ampScale, timeScale: timeScale, reduceMotion: reduceMotion)
            } else {
                // Live view with fixed time (e.g. history viewer): Metal shaders
                // work, so provide symbols for proper ray rendering.
                Canvas { context, size in
                    renderCanvas(context: &context, size: size, t: t)
                } symbols: {
                    spotlightSymbols(t: t)
                }
                .drawingGroup()
                .background(Color.clear)
                .canvasAnimationScale($ampScale, timeScale: timeScale, reduceMotion: reduceMotion)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    renderCanvas(context: &context, size: size, t: t)
                } symbols: {
                    spotlightSymbols(t: t)
                }
                .drawingGroup()
            }
            .background(Color.clear)
            .canvasAnimationScale($ampScale, timeScale: timeScale, reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private func spotlightSymbols(t: Double) -> some View {
        ForEach(rayElements) { e in
            let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
            let (near, mid, far): (Color, Color, Color) = {
                if let hex2 = e.hexColor2 {
                    let n = Color(hex: e.hexColor)
                    let f = Color(hex: hex2)
                    return (n, Color.lerp(n, f, t: 0.5), f)
                } else {
                    let colors = ProceduralShapeGenerator.spotlightColors(seed: seed)
                    return (colors.near, colors.mid, colors.far)
                }
            }()
            Rectangle()
                .fill(.white)
                .layerEffect(ShaderLibrary.spotlightEffect(
                    .float2(Float(RayShapeRenderer.symbolSize), Float(RayShapeRenderer.symbolSize)),
                    .float(Float(t + e.phaseOffset)),
                    .color(near),
                    .color(mid),
                    .color(far)
                ), maxSampleOffset: .zero)
                .frame(width: RayShapeRenderer.symbolSize, height: RayShapeRenderer.symbolSize)
                .tag(e.id)
        }
    }

    /// Portrait screen bounds used by GalleryView to pin the canvas to a fixed
    /// frame so it never resizes on rotation / split-view changes.
    /// Re-queried lazily so it always reflects the actual main screen, even when
    /// the first scene wasn't ready at static-init time.
    /// Storage is guarded by `OSAllocatedUnfairLock` because the static is read
    /// from arbitrary scene threads (e.g. ImageRenderer on background actors).
    /// 3:4 frame size for the museum-style framed canvas (history viewer, export, thumbnails).
    /// Based on the device width so elements map naturally without squishing.
    static var framedCanvasSize: CGSize {
        let w = canonicalPortraitSize.width
        return CGSize(width: w, height: w * 4.0 / 3.0)
    }

    static var canonicalPortraitSize: CGSize {
        if let cached = _canonicalPortraitSizeOverrideLock.withLock({ $0 }) {
            return cached
        }
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            let b = scene.screen.bounds.size
            let portrait: CGSize = b.width <= b.height
                ? b
                : CGSize(width: b.height, height: b.width)
            _canonicalPortraitSizeOverrideLock.withLock { $0 = portrait }
            return portrait
        }
        return CGSize(width: 393, height: 852)
    }
    private static let _canonicalPortraitSizeOverrideLock = OSAllocatedUnfairLock<CGSize?>(initialState: nil)

    /// Computes the same animated center as the live render path, but at a fixed
    /// time. Pass `ampScale` to match what the user sees on-screen during dampened
    /// (edit-mode / label-mode) rendering — defaults to 1.0 for back-compat with
    /// callers that render at full amplitude.
    ///
    /// Known limitation (audit L2): GalleryView's snapshot/hit-test call sites
    /// currently rely on the default `1.0`, so frozen positions can desync from
    /// the live edit-mode view by up to ~0.6% of canvas width when `timeScale`
    /// is dampened. Pass the live `ampScale` from those call sites to fix.
    static func frozenElementCenter(
        _ element: CanvasElement,
        size: CGSize,
        at date: Date,
        ampScale: Double = 1.0
    ) -> CGPoint {
        let t = date.timeIntervalSinceReferenceDate
        let shape = element.resolvedShapeType
        switch shape {
        case .snowflake:
            return SnowflakeShapeRenderer.frozenCenter(element, size: size, t: t, ampScale: ampScale)
        case .blob:
            return BlobShapeRenderer.frozenCenter(element, size: size, t: t, ampScale: ampScale)
        case .organicBlob:
            return OrganicBlobShapeRenderer.frozenCenter(element, size: size, t: t, ampScale: ampScale)
        case .rays:
            return RayShapeRenderer.frozenCenter(element, size: size, t: t, ampScale: ampScale)
        case .circle, .spirograph:
            return CircleShapeRenderer.frozenCenter(element, size: size, t: t, ampScale: ampScale)
        }
    }

    /// Returns elements sorted for rendering (circles first, by size desc; non-
    /// circles in insertion order). Sort *order* is cached against a signature
    /// derived from `(id, kind, size)` so the O(n log n) sort runs only when
    /// the element set actually changes — not on every 20fps Canvas tick.
    /// The cached value is an array of IDs (not element copies) so that
    /// mutable fields like `basePosition` are always read from the fresh input.
    private func sortedForRendering(_ elements: [CanvasElement]) -> [CanvasElement] {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for e in elements {
            hasher.combine(e.id)
            hasher.combine(e.kind)
            hasher.combine(e.size)
            hasher.combine(e.frozenShapeType)
        }
        let signature = hasher.finalize()

        if signature != renderCache.sortSignature {
            let nonRays = elements.filter { shapeType(for: $0) != .rays }.sorted { $0.size > $1.size }
            let rays = elements.filter { shapeType(for: $0) == .rays }
            renderCache.sortedOrder = (nonRays + rays).map(\.id)
            renderCache.sortSignature = signature
            renderCache.sortedIndexMap.removeAll(keepingCapacity: true)
            for (i, e) in elements.enumerated() {
                renderCache.sortedIndexMap[e.id] = i
            }
        } else if renderCache.sortedIndexMap.isEmpty {
            for (i, e) in elements.enumerated() {
                renderCache.sortedIndexMap[e.id] = i
            }
        }

        return renderCache.sortedOrder.compactMap { id in
            guard let idx = renderCache.sortedIndexMap[id], idx < elements.count else { return nil }
            return elements[idx]
        }
    }


    private func renderCanvas(context: inout GraphicsContext, size: CGSize, t: Double) {
        let decay = decayNorm
        let dark = isDarkBackground
        let blendMode: GraphicsContext.BlendMode = dark ? .plusLighter : .normal
        let lblColor = labelColor ?? (dark ? .white : .black)
        let shadowClr = dark ? Color.black : Color.white

        if showsBackgroundGradient {
            drawUnifiedGradient(context: &context, size: size, t: t)
        }

        // Pre-compute drift positions for all snowflake-type elements.
        let isSnowflake: (CanvasElement) -> Bool = { [self] e in shapeType(for: e) == .snowflake }
        SnowflakeShapeRenderer.precomputePositions(
            elements: elements, shapeFilter: isSnowflake,
            size: size, t: t, ampScale: ampScale, renderCache: renderCache
        )

        let sortedElements = sortedForRendering(elements)
        let interactions = computeInteractions(elements: sortedElements, size: size, t: t)

        // Pass 1: Snowflake elements (rendered under grain, like Mind used to be)
        let snowflakeElements = sortedElements.filter { shapeType(for: $0) == .snowflake }
        for element in snowflakeElements {
            let interaction = interactions[element.id]
            drawElement(element, context: &context, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction)
            if showLabelsOnCanvas {
                let center = elementCenter(element, size: size, t: t)
                drawLabel(element, at: center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
            }
        }

        // Pass 2: Blob clusters + remaining (blob + ray) elements
        let isBlob: (CanvasElement) -> Bool = { [self] e in shapeType(for: e) == .blob }
        var clusteredBlobIds = Set<UUID>()
        var allBlobInfos = [BodyBlobInfo]()
        let (clusters, solos) = BlobShapeRenderer.collectClusters(
            elements: sortedElements, shapeFilter: isBlob,
            size: size, t: t, decay: decay,
            ampScale: ampScale, decayedColor: decayedColor
        )
        for cluster in clusters {
            BlobShapeRenderer.drawCluster(
                cluster, context: &context, size: size, t: t, blendMode: blendMode,
                spawnFactor: { e, time in spawnFactor(for: e, t: time) },
                renderCache: renderCache
            )
            for blob in cluster {
                clusteredBlobIds.insert(blob.element.id)
                allBlobInfos.append(blob)
                if showLabelsOnCanvas {
                    drawLabel(blob.element, at: blob.center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
                }
            }
        }
        allBlobInfos.append(contentsOf: solos)

        for element in sortedElements {
            if shapeType(for: element) == .snowflake { continue }
            if clusteredBlobIds.contains(element.id) { continue }

            let interaction = interactions[element.id]
            drawElement(element, context: &context, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction)
            if showLabelsOnCanvas {
                let center = elementCenter(element, size: size, t: t)
                drawLabel(element, at: center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
            }
        }
    }

    // MARK: - Cross-Element Interaction Model

    /// Computes blob↔snowflake proximity interactions. When a snowflake drifts
    /// near a blob (or organic blob), the blob's noise complexity increases (noiseBoost).
    private func computeInteractions(
        elements: [CanvasElement],
        size: CGSize,
        t: Double
    ) -> [UUID: ElementInteraction] {
        renderCache.interactions.removeAll(keepingCapacity: true)
        let interactionRadius: CGFloat = 0.25

        let blobs = elements.filter {
            let s = shapeType(for: $0)
            return s == .blob || s == .organicBlob
        }
        let snowflakes = elements.filter { shapeType(for: $0) == .snowflake }
        guard !blobs.isEmpty, !snowflakes.isEmpty else { return renderCache.interactions }

        let invW = size.width > 0 ? 1.0 / Double(size.width) : 0.0
        let invH = size.height > 0 ? 1.0 / Double(size.height) : 0.0

        let snowflakePositions: [CGPoint] = snowflakes.map { e in
            let p = renderCache.mindPositionCache[e.id]
                ?? SnowflakeShapeRenderer.driftPosition(e, size: size, t: t, ampScale: ampScale)
            return CGPoint(x: Double(p.x) * invW, y: Double(p.y) * invH)
        }
        let blobPositions: [CGPoint] = blobs.map { e in
            let s = shapeType(for: e)
            let p = s == .organicBlob
                ? OrganicBlobShapeRenderer.center(e, size: size, t: t, ampScale: ampScale)
                : BlobShapeRenderer.center(e, size: size, t: t, ampScale: ampScale)
            return CGPoint(x: Double(p.x) * invW, y: Double(p.y) * invH)
        }

        for (idx, blob) in blobs.enumerated() {
            var interaction = ElementInteraction()
            let posA = blobPositions[idx]

            for posB in snowflakePositions {
                let dx = posA.x - posB.x
                let dy = posA.y - posB.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist < interactionRadius else { continue }
                let proximity = 1.0 - Double(dist / interactionRadius)
                interaction.noiseBoost += proximity * 0.4
            }

            if interaction.noiseBoost > 0.001 {
                renderCache.interactions[blob.id] = interaction
            }
        }
        return renderCache.interactions
    }

    // MARK: - Spawn Animation

    /// Returns 0->1 over spawnDuration seconds since element creation. Cubic ease-out.
    private func spawnFactor(for element: CanvasElement, t: Double) -> Double {
        let spawnDuration = 0.8
        let age = t - element.createdAt.timeIntervalSinceReferenceDate
        guard age < spawnDuration else { return 1.0 }
        guard age > 0 else { return 0.0 }
        let linear = age / spawnDuration
        return 1.0 - pow(1.0 - linear, 3.0)
    }

    // MARK: - Element Dispatch

    private func drawElement(
        _ element: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        interaction: ElementInteraction? = nil,
        bodyBlobInfos: [BodyBlobInfo] = []
    ) {
        let spawn = spawnFactor(for: element, t: t)
        guard spawn > 0.001 else { return }

        context.drawLayer { ctx in
            ctx.opacity = spawn
            if spawn < 1.0 {
                let center = elementCenter(element, size: size, t: t)
                let scale = 0.3 + 0.7 * spawn
                ctx.translateBy(x: center.x, y: center.y)
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -center.x, y: -center.y)
            }
            let color = decayedColor(element.hexColor, decay: decay)
            let color2: Color? = element.hexColor2.map { decayedColor($0, decay: decay) }
            switch shapeType(for: element) {
            case .blob:
                BlobShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    interaction: interaction, decayedColor: color,
                    decayedColor2: color2
                )
            case .organicBlob:
                OrganicBlobShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    interaction: interaction, decayedColor: color,
                    decayedColor2: color2
                )
            case .snowflake:
                SnowflakeShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    renderCache: renderCache,
                    decayedColor: color, decayedColor2: color2
                )
            case .rays:
                RayShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    interaction: interaction
                )
            case .circle:
                CircleShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    interaction: interaction, decayedColor: color,
                    decayedColor2: color2
                )
            case .spirograph:
                CircleShapeRenderer.draw(
                    element, context: &ctx, size: size, t: t, decay: decay,
                    blendMode: blendMode, ampScale: ampScale,
                    interaction: interaction, decayedColor: color,
                    decayedColor2: color2
                )
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Unified Background Gradient
    // ═══════════════════════════════════════════════════════════

    /// Delegates to `EnergyGradientRenderer` — single source of truth for gradient logic.
    private func drawUnifiedGradient(context: inout GraphicsContext, size: CGSize, t: Double) {
        let stepsNorm = Double(min(max(stepsPoints, 0), 20)) / 20.0
        let sleepNorm = Double(min(max(sleepPoints, 0), 20)) / 20.0
        let Ss = EnergyGradientRenderer.smoothstep(stepsNorm)
        let Ls = EnergyGradientRenderer.smoothstep(sleepNorm)
        let opacities = EnergyGradientRenderer.computeOpacities(
            smoothedS: Ss,
            smoothedL: Ls,
            hasStepsData: hasStepsData,
            hasSleepData: hasSleepData
        )
        EnergyGradientRenderer.draw(context: &context, size: size, opacities: opacities)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Element labels + centers
    // ═══════════════════════════════════════════════════════════

    private func elementCenter(_ element: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        switch shapeType(for: element) {
        case .blob:
            return BlobShapeRenderer.center(element, size: size, t: t, ampScale: ampScale)
        case .organicBlob:
            return OrganicBlobShapeRenderer.center(element, size: size, t: t, ampScale: ampScale)
        case .snowflake:
            return SnowflakeShapeRenderer.center(element, size: size, t: t, ampScale: ampScale, renderCache: renderCache)
        case .rays:
            return RayShapeRenderer.center(element, size: size, t: t, ampScale: ampScale)
        case .circle, .spirograph:
            return CircleShapeRenderer.center(element, size: size, t: t, ampScale: ampScale)
        }
    }

    private func drawLabel(_ element: CanvasElement, at point: CGPoint, context: inout GraphicsContext, labelColor: Color, shadowColor: Color) {
        let raw = element.displayLabel
        let labelText = raw.prefix(1).uppercased() + raw.dropFirst().lowercased()
        let font: Font = .system(size: 11, weight: .regular, design: .default)
        if showsOutlinedLabels {
            // 4 diagonal offsets give the same visual halo as 8 at 1pt,
            // cutting drawLayer + Text resolution calls in half.
            let shadowText = Text(labelText).font(font).foregroundStyle(shadowColor)
            context.drawLayer { ctx in
                ctx.opacity = 0.4
                ctx.draw(shadowText, at: CGPoint(x: point.x - 1, y: point.y - 1), anchor: .center)
                ctx.draw(shadowText, at: CGPoint(x: point.x + 1, y: point.y - 1), anchor: .center)
                ctx.draw(shadowText, at: CGPoint(x: point.x - 1, y: point.y + 1), anchor: .center)
                ctx.draw(shadowText, at: CGPoint(x: point.x + 1, y: point.y + 1), anchor: .center)
            }
        }

        context.draw(
            Text(labelText).font(font).foregroundStyle(labelColor.opacity(0.9)),
            at: point,
            anchor: .center
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Decay Effects
    // ═══════════════════════════════════════════════════════════

    /// Graceful desaturation: colors fade toward monochrome as energy is spent.
    /// 0-25%: full color. 25-75%: progressive desaturation. 75-100%: near-monochrome.
    private func decayedColor(_ hex: String, decay: Double) -> Color {
        let base = Color(hex: hex)
        guard decay > 0.25 else { return base }

        if decay < 0.75 {
            let t = (decay - 0.25) / 0.50
            return base.desaturated(by: t * 0.7)
        } else {
            let t = (decay - 0.75) / 0.25
            return base.desaturated(by: 0.7 + t * 0.25)
        }
    }

}

// MARK: - Preview

#Preview("Empty Canvas - Dark") {
    GenerativeCanvasView(
        elements: [],
        sleepPoints: 10,
        stepsPoints: 15,
        sleepColor: Color(hex: "#000000"),
        stepsColor: Color(hex: "#FED415"),
        decayNorm: 0,
        backgroundColor: AppColors.Night.background
    )
    .frame(height: 500)
}

#Preview("With Elements") {
    let elements: [CanvasElement] = [
        .spawn(optionId: "activity_sport", category: .body, color: "#C3143B", label: "Sport", existingElements: []),
        .spawn(optionId: "creativity_curiosity", category: .mind, color: "#7652AF", label: "Curiosity", existingElements: []),
        .spawn(optionId: "joys_friends", category: .heart, color: "#FEAAC2", label: "Friends", existingElements: []),
    ]
    GenerativeCanvasView(
        elements: elements,
        sleepPoints: 14,
        stepsPoints: 18,
        sleepColor: Color(hex: "#000000"),
        stepsColor: Color(hex: "#FED415"),
        decayNorm: 0.1,
        backgroundColor: AppColors.Night.background
    )
    .frame(height: 500)
}

// MARK: - Animation Scale (Reduce Motion)

private extension View {
    func canvasAnimationScale(
        _ ampScale: Binding<Double>,
        timeScale: Double,
        reduceMotion: Bool
    ) -> some View {
        let effective = reduceMotion ? 0 : timeScale
        return onAppear { ampScale.wrappedValue = effective }
            .onChange(of: timeScale) { _, newValue in
                withAnimation(.easeInOut(duration: 0.6)) {
                    ampScale.wrappedValue = reduceMotion ? 0 : newValue
                }
            }
            .onChange(of: reduceMotion) { _, reduced in
                withAnimation(.easeInOut(duration: 0.6)) {
                    ampScale.wrappedValue = reduced ? 0 : timeScale
                }
            }
    }
}
