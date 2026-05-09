import SwiftUI
import UIKit
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
    /// Color for activity labels on each blob; nil = auto from background.
    var labelColor: Color?
    /// Whether to show labels directly on canvas elements
    var showLabelsOnCanvas: Bool = true
    /// Whether labels are rendered with an outlined shadow halo for readability.
    var showsOutlinedLabels: Bool = true
    /// When false, only activity elements are rendered (no radial background gradient).
    var showsBackgroundGradient: Bool = true
    /// Whether HealthKit has returned step data today (do not infer from points alone).
    var hasStepsData: Bool = true
    /// Whether HealthKit has returned sleep data today (do not infer from points alone).
    var hasSleepData: Bool = true
    /// Amplitude multiplier for drift/wobble (1.0 = normal, 0.25 = subdued for label/edit mode).
    var timeScale: Double = 1.0
    /// When non-nil, renders a single static frame at this time instead of using
    /// TimelineView animation.  Used for ImageRenderer snapshots (e.g. canvas export).
    var fixedTime: Date? = nil


    @State private var ampScale: Double = 1.0

    /// Per-instance render cache. Held in `@State` so the same instance
    /// persists across SwiftUI body recompositions; mutating its properties
    /// does NOT trigger a view update (it's a class held by reference).
    /// Accesses are confined to the Canvas closure on `MainActor`.
    @MainActor
    private final class RenderCache {
        var sortSignature: Int = .min
        var sortedElements: [CanvasElement] = []
        var interactions: [UUID: ElementInteraction] = [:]
    }
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

    var body: some View {
        if let fixedTime {
            Canvas { context, size in
                renderCanvas(context: &context, size: size,
                             t: fixedTime.timeIntervalSinceReferenceDate)
            }
            .background(Color.clear)
            .onAppear { ampScale = timeScale }
            .onChange(of: timeScale) { _, newValue in
                withAnimation(.easeInOut(duration: 0.6)) { ampScale = newValue }
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                Canvas { context, size in
                    renderCanvas(context: &context, size: size,
                                 t: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .background(Color.clear)
            .onAppear { ampScale = timeScale }
            .onChange(of: timeScale) { _, newValue in
                withAnimation(.easeInOut(duration: 0.6)) { ampScale = newValue }
            }
        }
    }

    /// Portrait screen bounds used by GalleryView to pin the canvas to a fixed
    /// frame so it never resizes on rotation / split-view changes.
    /// Re-queried lazily so it always reflects the actual main screen, even when
    /// the first scene wasn't ready at static-init time.
    /// Storage is guarded by `OSAllocatedUnfairLock` because the static is read
    /// from arbitrary scene threads (e.g. ImageRenderer on background actors).
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
        let w = Double(size.width)
        let h = Double(size.height)
        let amp = ampScale

        switch element.category {
        case .mind:
            let p = element.phaseOffset
            let speed = 0.03 + element.driftSpeed * 0.06
            let s = p * 1000.0
            let freq = (
                fx1: 1.0  + sin(s * 0.11) * 0.15,
                fx2: 2.2  + sin(s * 0.23) * 0.3,
                fx3: 3.8  + sin(s * 0.37) * 0.5,
                fy1: 0.85 + cos(s * 0.17) * 0.15,
                fy2: 2.0  + cos(s * 0.31) * 0.3,
                fy3: 3.5  + cos(s * 0.43) * 0.5
            )
            let mod = sin(t * speed * 0.13 + p * 3.7) * sin(t * speed * 0.07 + p * 1.3)
            let env = 0.7 + 0.3 * mod

            let hx = Double(element.basePosition.x) + sin(t * speed * 0.05 + p) * 0.12
            let hy = Double(element.basePosition.y) + cos(t * speed * 0.04 + p * 1.3) * 0.12

            let nx = hx
                + sin(t * speed * freq.fx1 + p) * 0.24 * amp * env
                + sin(t * speed * freq.fx2 + p * 2.3) * 0.09 * amp * env
                + sin(t * speed * freq.fx3 + p * 4.1) * 0.03 * amp
            let ny = hy
                + cos(t * speed * freq.fy1 + p * 1.7) * 0.22 * amp * env
                + cos(t * speed * freq.fy2 + p * 3.1) * 0.08 * amp * env
                + cos(t * speed * freq.fy3 + p * 5.3) * 0.03 * amp

            let margin = 0.06
            return CGPoint(
                x: min(1.0 - margin, max(margin, nx)) * w,
                y: min(1.0 - margin, max(margin, ny)) * h
            )

        case .body:
            let cx = Double(element.basePosition.x) * w
            let cy = Double(element.basePosition.y) * h
            let wobbleX = sin(t * 0.015 + element.phaseOffset) * w * 0.003 * amp
                + sin(t * 0.008 + element.phaseOffset * 2.3) * w * 0.002 * amp
            let wobbleY = cos(t * 0.013 + element.phaseOffset * 1.3) * h * 0.003 * amp
                + cos(t * 0.009 + element.phaseOffset * 0.7) * h * 0.002 * amp
            return CGPoint(x: cx + wobbleX, y: cy + wobbleY)

        case .heart:
            let cx = Double(element.basePosition.x) * w
            let cy = Double(element.basePosition.y) * h
            let wobbleX = sin(t * 0.012 + element.phaseOffset) * w * 0.004 * amp
                + sin(t * 0.007 + element.phaseOffset * 2.3) * w * 0.002 * amp
            let wobbleY = cos(t * 0.010 + element.phaseOffset * 1.3) * h * 0.004 * amp
                + cos(t * 0.006 + element.phaseOffset * 0.7) * h * 0.002 * amp
            return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
        }
    }

    /// Returns elements sorted for rendering (circles first, by size desc; non-
    /// circles in insertion order). Result is cached against a signature derived
    /// from `(id, kind, size)` of each element so the O(n log n) sort runs only
    /// when the element set actually changes — not on every 20fps Canvas tick.
    private func sortedForRendering(_ elements: [CanvasElement]) -> [CanvasElement] {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for e in elements {
            hasher.combine(e.id)
            hasher.combine(e.kind)
            hasher.combine(e.size)
        }
        let signature = hasher.finalize()
        if signature == renderCache.sortSignature {
            return renderCache.sortedElements
        }
        let circles = elements.filter { $0.kind == .circle }.sorted { $0.size > $1.size }
        let nonCircles = elements.filter { $0.kind != .circle }
        let sorted = circles + nonCircles
        renderCache.sortSignature = signature
        renderCache.sortedElements = sorted
        return sorted
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

        let sortedElements = sortedForRendering(elements)

        let interactions = computeInteractions(elements: sortedElements, size: size, t: t)

        // Pass 1: Mind elements (rendered under grain)
        let mindElements = sortedElements.filter { $0.category == .mind }
        for element in mindElements {
            let interaction = interactions[element.id]
            drawElement(element, context: &context, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction)
            if showLabelsOnCanvas {
                let center = elementCenter(element, size: size, t: t)
                drawLabel(element, at: center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
            }
        }

        // Pass 2: Body clusters + body/heart elements
        var clusteredBodyIds = Set<UUID>()
        var allBodyBlobInfos = [BodyBlobInfo]()
        let (clusters, solos) = collectBodyClusters(
            elements: sortedElements, size: size, t: t, decay: decay
        )
        for cluster in clusters {
            drawBodyCluster(cluster, context: &context, size: size, t: t, blendMode: blendMode)
            for blob in cluster {
                clusteredBodyIds.insert(blob.element.id)
                allBodyBlobInfos.append(blob)
                if showLabelsOnCanvas {
                    drawLabel(blob.element, at: blob.center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
                }
            }
        }
        allBodyBlobInfos.append(contentsOf: solos)

        for element in sortedElements {
            if element.category == .mind { continue }
            if clusteredBodyIds.contains(element.id) { continue }

            let interaction = interactions[element.id]
            drawElement(element, context: &context, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction)
            if showLabelsOnCanvas {
                let center = elementCenter(element, size: size, t: t)
                drawLabel(element, at: center, context: &context, labelColor: lblColor, shadowColor: shadowClr)
            }
        }
    }

    // MARK: - Cross-Element Interaction Model

    struct ElementInteraction {
        var noiseBoost: Double = 0
        var attractionOffset: CGVector = .zero
        var stretchFactor: Double = 1.0
    }

    /// Computes per-element interactions consumed by draw paths. Only the
    /// `(.body, .mind) → noiseBoost` channel is actually read downstream
    /// (`drawCircle` body branch boosts complexity by `noiseBoost`); the
    /// `mind ↔ mind` repulsion was previously discarded, so we skip it.
    /// Mind drift positions are precomputed once to avoid O(n²) trig.
    private func computeInteractions(
        elements: [CanvasElement],
        size: CGSize,
        t: Double
    ) -> [UUID: ElementInteraction] {
        // Reuse the cached dict's allocation across frames. `removeAll(keepingCapacity:)`
        // keeps the buffer (refcount=1 here because the previous frame's local
        // `interactions` reference has already gone out of scope), so we avoid
        // a fresh dictionary allocation every 50ms.
        renderCache.interactions.removeAll(keepingCapacity: true)
        let interactionRadius: CGFloat = 0.25

        let bodies = elements.filter { $0.category == .body }
        let minds = elements.filter { $0.category == .mind }
        guard !bodies.isEmpty, !minds.isEmpty else { return renderCache.interactions }

        let invW = size.width > 0 ? 1.0 / Double(size.width) : 0.0
        let invH = size.height > 0 ? 1.0 / Double(size.height) : 0.0
        let mindPositions: [CGPoint] = minds.map { e in
            let p = mindDriftPosition(e, size: size, t: t)
            return CGPoint(x: Double(p.x) * invW, y: Double(p.y) * invH)
        }
        // Use the same animated position the body is rendered at so proximity matches
        // what the user sees on-screen (parity with mind).
        let bodyPositions: [CGPoint] = bodies.map { e in
            let p = circleCenter(e, size: size, t: t)
            return CGPoint(x: Double(p.x) * invW, y: Double(p.y) * invH)
        }

        for (idx, body) in bodies.enumerated() {
            var interaction = ElementInteraction()
            let posA = bodyPositions[idx]

            for posB in mindPositions {
                let dx = posA.x - posB.x
                let dy = posA.y - posB.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist < interactionRadius else { continue }
                let proximity = 1.0 - Double(dist / interactionRadius)
                interaction.noiseBoost += proximity * 0.4
            }

            if interaction.noiseBoost > 0.001 {
                renderCache.interactions[body.id] = interaction
            }
        }
        return renderCache.interactions
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Asset Pipeline (mind & heart image assets)
    // ═══════════════════════════════════════════════════════════

    private static let mindCircleAssetNames = CanvasImageCatalog.mind
    private static let heartAssetNames = CanvasImageCatalog.heart

    /// Returns the asset index for an element. Prefers the persisted `assetVariant` (round-robin,
    /// guarantees variety). Falls back to UUID-based hash for legacy elements saved before the field existed.
    private static func assetIndex(for element: CanvasElement, count: Int) -> Int {
        guard count > 0 else { return 0 }
        if let variant = element.assetVariant {
            return variant % count
        }
        let uuid = element.id.uuid
        let mixed = Int(uuid.0) &+ Int(uuid.4) &* 31 &+ Int(uuid.8) &* 127 &+ Int(uuid.12) &* 8191
        return abs(mixed) % count
    }

    private static var assetAspectRatioCache: [String: CGFloat] = [:]
    private static let assetAspectRatioCacheLock = NSLock()

    /// Returns asset width/height ratio (cached) to avoid geometry distortion when drawing.
    private func assetAspectRatio(name: String) -> CGFloat {
        Self.assetAspectRatioCacheLock.lock()
        if let cached = Self.assetAspectRatioCache[name] {
            Self.assetAspectRatioCacheLock.unlock()
            return cached
        }
        Self.assetAspectRatioCacheLock.unlock()

        let ratio: CGFloat
        if let image = UIImage(named: name), image.size.height > 0 {
            ratio = image.size.width / image.size.height
        } else {
            ratio = 1.0
        }

        Self.assetAspectRatioCacheLock.lock()
        Self.assetAspectRatioCache[name] = ratio
        Self.assetAspectRatioCacheLock.unlock()
        return ratio
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
            switch element.category {
            case .body, .mind:
                drawCircle(element, context: &ctx, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction, bodyBlobInfos: bodyBlobInfos)
            case .heart:
                drawRay(element, context: &ctx, size: size, t: t, decay: decay, blendMode: blendMode, interaction: interaction)
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
    // MARK: - Body (Circle) — soft radial pulse
    // ═══════════════════════════════════════════════════════════

    /// Body: stable, minimal drift. Mind: wide-range slow fly-around.
    private func circleCenter(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        if e.category == .mind {
            return mindDriftPosition(e, size: size, t: t)
        }
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = Double(e.basePosition.x) * w
        let cy = Double(e.basePosition.y) * h
        let amp = ampScale
        let wobbleX = sin(t * 0.015 + e.phaseOffset) * w * 0.003 * amp
            + sin(t * 0.008 + e.phaseOffset * 2.3) * w * 0.002 * amp
        let wobbleY = cos(t * 0.013 + e.phaseOffset * 1.3) * h * 0.003 * amp
            + cos(t * 0.009 + e.phaseOffset * 0.7) * h * 0.002 * amp
        return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Mind Drift — unique per-element Lissajous with variable speed
    // ═══════════════════════════════════════════════════════════

    /// Per-element frequency ratios derived from phaseOffset so every mind
    /// element traces a qualitatively different Lissajous figure.
    private struct MindFrequencyProfile {
        let fx1, fx2, fx3: Double
        let fy1, fy2, fy3: Double

        init(phase p: Double) {
            let s = p * 1000.0
            fx1 = 1.0  + sin(s * 0.11) * 0.15
            fx2 = 2.2  + sin(s * 0.23) * 0.3
            fx3 = 3.8  + sin(s * 0.37) * 0.5
            fy1 = 0.85 + cos(s * 0.17) * 0.15
            fy2 = 2.0  + cos(s * 0.31) * 0.3
            fy3 = 3.5  + cos(s * 0.43) * 0.5
        }
    }

    /// Smooth amplitude envelope — modulates *range* of drift instead of
    /// time, so the path stays continuous. Creates breathing: wide sweeps
    /// alternate with tight hovering.
    private func mindAmplitudeEnvelope(_ e: CanvasElement, speed: Double, t: Double) -> Double {
        let p = e.phaseOffset
        let mod = sin(t * speed * 0.13 + p * 3.7) * sin(t * speed * 0.07 + p * 1.3)
        return 0.7 + 0.3 * mod
    }

    /// Drifting home zone — the orbit center itself wanders slowly, so the
    /// element stays in a neighbourhood but the neighbourhood shifts.
    private func mindHomePosition(_ e: CanvasElement, speed: Double, t: Double) -> (Double, Double) {
        let p = e.phaseOffset
        let hx = Double(e.basePosition.x) + sin(t * speed * 0.05 + p) * 0.12
        let hy = Double(e.basePosition.y) + cos(t * speed * 0.04 + p * 1.3) * 0.12
        return (hx, hy)
    }

    private static let mindClampMargin: Double = 0.06

    /// Shared raw drift state — normalized position and analytical velocity
    /// before any clamp is applied. Pulled out so `mindDriftPosition` and
    /// `mindDriftVelocity` see *exactly* the same envelope/home/freq values
    /// and the boundary clamp can be applied consistently to both.
    private func mindDriftRawState(_ e: CanvasElement, t: Double)
        -> (nx: Double, ny: Double, vx: Double, vy: Double)
    {
        let p = e.phaseOffset
        let speed = 0.03 + e.driftSpeed * 0.06
        let amp = ampScale
        let freq = MindFrequencyProfile(phase: p)
        let env = mindAmplitudeEnvelope(e, speed: speed, t: t)

        let dx1 = sin(t * speed * freq.fx1 + p) * 0.24 * amp * env
        let dx2 = sin(t * speed * freq.fx2 + p * 2.3) * 0.09 * amp * env
        let dx3 = sin(t * speed * freq.fx3 + p * 4.1) * 0.03 * amp

        let dy1 = cos(t * speed * freq.fy1 + p * 1.7) * 0.22 * amp * env
        let dy2 = cos(t * speed * freq.fy2 + p * 3.1) * 0.08 * amp * env
        let dy3 = cos(t * speed * freq.fy3 + p * 5.3) * 0.03 * amp

        let (hx, hy) = mindHomePosition(e, speed: speed, t: t)
        let nx = hx + dx1 + dx2 + dx3
        let ny = hy + dy1 + dy2 + dy3

        let vx1 = cos(t * speed * freq.fx1 + p) * speed * freq.fx1 * 0.24 * amp * env
        let vx2 = cos(t * speed * freq.fx2 + p * 2.3) * speed * freq.fx2 * 0.09 * amp * env
        let vx3 = cos(t * speed * freq.fx3 + p * 4.1) * speed * freq.fx3 * 0.03 * amp

        let vy1 = -sin(t * speed * freq.fy1 + p * 1.7) * speed * freq.fy1 * 0.22 * amp * env
        let vy2 = -sin(t * speed * freq.fy2 + p * 3.1) * speed * freq.fy2 * 0.08 * amp * env
        let vy3 = -sin(t * speed * freq.fy3 + p * 5.3) * speed * freq.fy3 * 0.03 * amp

        return (nx, ny, vx1 + vx2 + vx3, vy1 + vy2 + vy3)
    }

    private func mindDriftPosition(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let s = mindDriftRawState(e, t: t)
        let m = Self.mindClampMargin
        let cx = min(1.0 - m, max(m, s.nx)) * Double(size.width)
        let cy = min(1.0 - m, max(m, s.ny)) * Double(size.height)
        return CGPoint(x: cx, y: cy)
    }

    /// Analytical velocity — derivative of mindDriftPosition w.r.t. t, with the
    /// same boundary clamp applied as the position. When the element pins
    /// against a margin, the outward velocity component is smoothly attenuated
    /// over a small edge band instead of hard-zeroed; at corners (where both
    /// axes can collapse to zero) we bleed in a tiny fraction of the raw
    /// velocity so `atan2(vy, vx)` stays continuous and the asset doesn't
    /// snap-rotate to angle 0 when it pins against a corner.
    private func mindDriftVelocity(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        _ = size  // signature kept for symmetry with mindDriftPosition
        let s = mindDriftRawState(e, t: t)
        let m = Self.mindClampMargin
        let edgeWidth = 0.04

        @inline(__always) func soft(_ d: Double) -> Double {
            max(0.0, min(1.0, d / edgeWidth))
        }
        let leftAllow  = soft(s.nx - m)
        let rightAllow = soft(1.0 - m - s.nx)
        let topAllow   = soft(s.ny - m)
        let botAllow   = soft(1.0 - m - s.ny)

        var vx = s.vx
        var vy = s.vy
        if vx < 0 { vx *= leftAllow }
        if vx > 0 { vx *= rightAllow }
        if vy < 0 { vy *= topAllow }
        if vy > 0 { vy *= botAllow }

        let mag2 = vx * vx + vy * vy
        let rawMag2 = s.vx * s.vx + s.vy * s.vy
        let cornerBand = rawMag2 * 0.0025  // (5% of raw magnitude)^2
        if rawMag2 > 1e-9, mag2 < cornerBand {
            let bleed = max(0.0, 1.0 - mag2 / cornerBand)
            vx += s.vx * bleed * 0.05
            vy += s.vy * bleed * 0.05
        }
        return CGPoint(x: vx, y: vy)
    }

    private func drawCircle(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        interaction: ElementInteraction? = nil,
        bodyBlobInfos: [BodyBlobInfo] = []
    ) {
        let breathePhase = sin(t * (0.25 + e.phaseOffset * 0.1) + e.phaseOffset * 3.7)
        let pulse: Double = e.category == .body
            ? (1.0 + sin(t * (0.3 + e.pulseFrequency * 0.3) + e.phaseOffset) * 0.02 * ampScale)
            : (1.0 + breathePhase * 0.015 * ampScale)
        let center = circleCenter(e, size: size, t: t)
        let dim = Double(min(size.width, size.height))
        let effectiveSize = e.userSize ?? e.size
        let scale: Double = switch e.category {
        case .body:  1.05
        case .mind:  1.1
        case .heart: 1.1
        }
        let radius = Double(effectiveSize) * dim * scale * pulse
        let color = decayedColor(e.hexColor, decay: decay)

        if e.category == .mind {
            let mindAssets = Self.mindCircleAssetNames
            guard !mindAssets.isEmpty else { return }
            let name = mindAssets[Self.assetIndex(for: e, count: mindAssets.count)]
            let image: Image? = UIImage(named: name).map { Image(uiImage: $0) }
            let aspect = assetAspectRatio(name: name)
            let halfW = radius * aspect
            let halfH = radius

            let vel = mindDriftVelocity(e, size: size, t: t)
            let rotation = Angle.radians(atan2(vel.y, vel.x) + e.userRotation) + .degrees(270)

            if let image {
                drawMindAssetTrail(e, image: image, aspect: aspect, radius: radius, t: t, rotation: rotation, blendMode: blendMode, size: size, decay: decay, context: &context)
            }

            let idleOpacity = (0.76 + breathePhase * 0.04) * (1.0 - decay * 0.4)
            let assetRect = CGRect(
                x: center.x - halfW, y: center.y - halfH,
                width: halfW * 2, height: halfH * 2
            )
            context.drawLayer { ctx in
                ctx.opacity = idleOpacity
                ctx.blendMode = blendMode
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -center.x, y: -center.y)
                if let image {
                    ctx.draw(image, in: assetRect)
                } else {
                    drawFallbackBlob(context: &ctx, in: assetRect, color: color)
                }
            }
            return
        }

        let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
        let baseComplexity = min(1.0, Double(e.activityCount ?? 1) / 30.0)
        let complexity = min(1.0, baseComplexity + (interaction?.noiseBoost ?? 0))
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )

        drawProceduralBody(e, seed: seed, complexity: complexity, color: color, center: center, rect: rect, t: t, blendMode: blendMode, context: &context)
    }

    /// Soft radial-gradient circle fallback when the PNG/SVG asset is missing.
    private func drawFallbackBlob(context: inout GraphicsContext, in rect: CGRect, color: Color) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let gradient = Gradient(stops: [
            .init(color: color.opacity(0.7), location: 0),
            .init(color: color.opacity(0.25), location: 0.55),
            .init(color: color.opacity(0), location: 1.0),
        ])
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: r)
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Heart (Ray) — asset-based, pointing toward center
    // ═══════════════════════════════════════════════════════════

    /// Slow oscillating sweep that pivots around the solid tip.
    private func raySweepAngle(_ e: CanvasElement, t: Double) -> Angle {
        let sweepRange = (10.0 + e.rotationSpeed * 0.2) * ampScale
        let sweepSpeed = 0.012 + e.driftSpeed * 0.01
        let sweep = sin(t * sweepSpeed + e.phaseOffset * 2.1) * sweepRange
        return Angle.degrees(sweep)
    }

    private func heartCenter(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = Double(e.basePosition.x) * w
        let cy = Double(e.basePosition.y) * h
        let amp = ampScale
        let wobbleX = sin(t * 0.012 + e.phaseOffset) * w * 0.004 * amp
            + sin(t * 0.007 + e.phaseOffset * 2.3) * w * 0.002 * amp
        let wobbleY = cos(t * 0.010 + e.phaseOffset * 1.3) * h * 0.004 * amp
            + cos(t * 0.006 + e.phaseOffset * 0.7) * h * 0.002 * amp
        return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
    }

    private func drawRay(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        interaction: ElementInteraction? = nil
    ) {
        let dim = Double(min(size.width, size.height))
        let effectiveSize = e.userSize ?? e.size
        let radius = Double(effectiveSize) * dim * 2.2
        let breathe = 0.92 + sin(t * e.pulseFrequency * 0.5 + e.phaseOffset) * 0.06
        let sweep = raySweepAngle(e, t: t)

        let attrOffset = interaction?.attractionOffset ?? .zero
        let center = heartCenter(e, size: size, t: t)
        let anchor = CGPoint(
            x: center.x + attrOffset.dx,
            y: center.y + attrOffset.dy
        )

        let canvasCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let dx = canvasCenter.x - anchor.x
        let dy = canvasCenter.y - anchor.y
        let inwardAngle = Angle.radians(atan2(Double(dy), Double(dx)))

        let heartAssets = Self.heartAssetNames
        guard !heartAssets.isEmpty else { return }
        let name = heartAssets[Self.assetIndex(for: e, count: heartAssets.count)]
        let image: Image? = UIImage(named: name).map { Image(uiImage: $0) }
        let aspect = assetAspectRatio(name: name)

        let halfW = radius * Double(aspect)
        let halfH = radius
        let assetRect = CGRect(
            x: anchor.x - halfW,
            y: anchor.y - halfH,
            width: halfW * 2,
            height: halfH * 2
        )

        let rotation = inwardAngle + .degrees(90) + Angle.radians(e.userRotation) + sweep

        context.drawLayer { ctx in
            ctx.opacity = breathe * (1.0 - decay * 0.4)
            ctx.blendMode = blendMode
            ctx.translateBy(x: anchor.x, y: anchor.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -anchor.x, y: -anchor.y)
            if let image {
                ctx.draw(image, in: assetRect)
            } else {
                let color = decayedColor(e.hexColor, decay: decay)
                drawFallbackRay(context: &ctx, in: assetRect, color: color)
            }
        }
    }

    /// Tapered gradient ray fallback when the heart PNG asset is missing.
    private func drawFallbackRay(context: inout GraphicsContext, in rect: CGRect, color: Color) {
        let tipY = rect.minY
        let baseY = rect.maxY
        let midX = rect.midX
        let halfBase = rect.width * 0.5

        var path = Path()
        path.move(to: CGPoint(x: midX, y: tipY))
        path.addQuadCurve(
            to: CGPoint(x: midX + halfBase, y: baseY),
            control: CGPoint(x: midX + halfBase * 0.3, y: tipY + rect.height * 0.4)
        )
        path.addLine(to: CGPoint(x: midX - halfBase, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: midX, y: tipY),
            control: CGPoint(x: midX - halfBase * 0.3, y: tipY + rect.height * 0.4)
        )
        path.closeSubpath()

        let gradient = Gradient(stops: [
            .init(color: color.opacity(0.6), location: 0),
            .init(color: color.opacity(0.15), location: 0.7),
            .init(color: color.opacity(0), location: 1.0),
        ])
        context.fill(
            path,
            with: .linearGradient(gradient, startPoint: CGPoint(x: midX, y: tipY), endPoint: CGPoint(x: midX, y: baseY))
        )
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Procedural Shape Rendering
    // ═══════════════════════════════════════════════════════════

    private func drawProceduralBody(
        _ e: CanvasElement,
        seed: UInt64,
        complexity: Double,
        color: Color,
        center: CGPoint,
        rect: CGRect,
        t: Double,
        blendMode: GraphicsContext.BlendMode,
        context: inout GraphicsContext
    ) {
        let path = ProceduralShapeGenerator.bodyPath(
            seed: seed, complexity: complexity, time: t, in: rect
        )
        drawBodyFill(path: path, color: color, center: center, rect: rect, phase: e.phaseOffset, userRotation: e.userRotation, seed: seed, blendMode: blendMode, context: &context)
    }

    /// Renders a solo body blob as a bubble — nearly transparent with a thin visible rim.
    private func drawBodyFill(
        path: Path,
        color: Color,
        center: CGPoint,
        rect: CGRect,
        phase: Double,
        userRotation: Double,
        seed: UInt64,
        blendMode: GraphicsContext.BlendMode,
        context: inout GraphicsContext
    ) {
        let rotation = Angle.radians(phase + userRotation)

        let r = min(rect.width, rect.height) / 2
        let innerR = max(0, r - 40)
        let edgeLoc = r > 0 ? Double(innerR / r) : 0

        let rimGrad = Gradient(stops: [
            .init(color: color.opacity(0.12), location: 0),
            .init(color: color.opacity(0.10), location: edgeLoc),
            .init(color: color.opacity(0.35), location: edgeLoc + (1.0 - edgeLoc) * 0.5),
            .init(color: color.opacity(0.55), location: 1.0),
        ])

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)

            ctx.clip(to: path)
            let ellipse = CGRect(x: center.x - r, y: center.y - r,
                                  width: r * 2, height: r * 2)
            ctx.fill(
                Path(ellipseIn: ellipse),
                with: .radialGradient(rimGrad, center: center,
                                      startRadius: 0, endRadius: r)
            )

            ctx.stroke(
                path,
                with: .color(color.opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Metaball Body Cluster Rendering

    struct BodyBlobInfo {
        let element: CanvasElement
        let center: CGPoint
        let radius: CGFloat
        let color: Color
        let seed: UInt64
    }

    /// Collects all body elements with their animated centers and groups nearby ones for metaball merging.
    private func collectBodyClusters(
        elements: [CanvasElement],
        size: CGSize,
        t: Double,
        decay: Double
    ) -> (clusters: [[BodyBlobInfo]], solos: [BodyBlobInfo]) {
        let bodyElements = elements.filter { $0.category == .body }
        guard !bodyElements.isEmpty else { return ([], []) }

        var infos = [BodyBlobInfo]()
        for e in bodyElements {
            let center = circleCenter(e, size: size, t: t)
            let dim = min(size.width, size.height)
            let effectiveSize = e.userSize ?? e.size
            let pulse = 1.0 + sin(t * (0.3 + e.pulseFrequency * 0.3) + e.phaseOffset) * 0.02 * ampScale
            let radius = effectiveSize * dim * 1.05 * pulse
            let color = decayedColor(e.hexColor, decay: decay)
            infos.append(BodyBlobInfo(element: e, center: center, radius: radius, color: color, seed: e.shapeSeed ?? 0))
        }

        let mergeThreshold: CGFloat = 1.6
        var visited = Set<Int>()
        var clusters = [[BodyBlobInfo]]()
        var solos = [BodyBlobInfo]()

        for i in 0..<infos.count {
            guard !visited.contains(i) else { continue }

            var cluster = [infos[i]]
            visited.insert(i)

            var frontier = [i]
            while !frontier.isEmpty {
                let current = frontier.removeFirst()
                for j in 0..<infos.count where !visited.contains(j) {
                    let dx = infos[current].center.x - infos[j].center.x
                    let dy = infos[current].center.y - infos[j].center.y
                    let dist = sqrt(dx * dx + dy * dy)
                    let sumR = (infos[current].radius + infos[j].radius) * mergeThreshold
                    if dist < sumR {
                        cluster.append(infos[j])
                        visited.insert(j)
                        frontier.append(j)
                    }
                }
            }

            if cluster.count > 1 {
                clusters.append(cluster)
            } else {
                solos.append(cluster[0])
            }
        }

        return (clusters, solos)
    }

    /// Draws a cluster of body blobs merged by unioning their procedural paths.
    /// Each blob keeps its animated position and organic breathing shape.
    private func drawBodyCluster(
        _ cluster: [BodyBlobInfo],
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        blendMode: GraphicsContext.BlendMode
    ) {
        // Per-blob spawn factor controls both path-scale and fill/stroke opacity, so a
        // freshly-spawned blob fades into the merged shape instead of popping in.
        var blobPaths = [(blob: BodyBlobInfo, path: Path, spawn: Double)]()
        for blob in cluster {
            let spawn = spawnFactor(for: blob.element, t: t)
            guard spawn > 0.001 else { continue }
            let e = blob.element
            let complexity = min(1.0, Double(e.activityCount ?? 1) / 30.0)
            let rect = CGRect(
                x: blob.center.x - blob.radius,
                y: blob.center.y - blob.radius,
                width: blob.radius * 2,
                height: blob.radius * 2
            )
            let rawPath = ProceduralShapeGenerator.bodyPath(
                seed: blob.seed, complexity: complexity, time: t, in: rect
            )
            let scale = 0.3 + 0.7 * spawn
            let xform = CGAffineTransform(translationX: -blob.center.x, y: -blob.center.y)
                .concatenating(.init(scaleX: scale, y: scale))
                .concatenating(.init(rotationAngle: e.phaseOffset + e.userRotation))
                .concatenating(.init(translationX: blob.center.x, y: blob.center.y))
            guard let xfCG = rawPath.cgPath.copy(using: [xform]) else { continue }
            blobPaths.append((blob, Path(xfCG), spawn))
        }

        guard !blobPaths.isEmpty else { return }
        var mergedCG = blobPaths[0].path.cgPath
        for i in 1..<blobPaths.count {
            mergedCG = mergedCG.union(blobPaths[i].path.cgPath)
        }
        let mergedPath = Path(mergedCG)

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.clip(to: mergedPath)

            for (blob, _, spawn) in blobPaths {
                let r = blob.radius
                let innerR = max(0, r - 40)
                let edgeLoc = r > 0 ? Double(innerR / r) : 0

                let rimGrad = Gradient(stops: [
                    .init(color: blob.color.opacity(0.12 * spawn), location: 0),
                    .init(color: blob.color.opacity(0.10 * spawn), location: edgeLoc),
                    .init(color: blob.color.opacity(0.35 * spawn), location: edgeLoc + (1.0 - edgeLoc) * 0.5),
                    .init(color: blob.color.opacity(0.55 * spawn), location: 1.0),
                ])
                let ellipse = CGRect(x: blob.center.x - r, y: blob.center.y - r,
                                      width: r * 2, height: r * 2)
                ctx.fill(
                    Path(ellipseIn: ellipse),
                    with: .radialGradient(rimGrad, center: blob.center,
                                          startRadius: 0, endRadius: r)
                )
            }
        }

        for (blob, _, spawn) in blobPaths {
            let clipRect = CGRect(
                x: blob.center.x - blob.radius * 1.3,
                y: blob.center.y - blob.radius * 1.3,
                width: blob.radius * 2.6,
                height: blob.radius * 2.6
            )
            context.drawLayer { ctx in
                ctx.clip(to: Path(ellipseIn: clipRect))
                ctx.stroke(
                    mergedPath,
                    with: .color(blob.color.opacity(0.65 * spawn)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private static let mindTrailGhosts = 4
    private static let mindTrailSpacing: Double = 0.8

    /// Draws fading ghost copies of the mind asset image behind the element,
    /// spanning ~100px and dissolving to transparent.
    private func drawMindAssetTrail(
        _ e: CanvasElement,
        image: Image,
        aspect: Double,
        radius: Double,
        t: Double,
        rotation: Angle,
        blendMode: GraphicsContext.BlendMode,
        size: CGSize,
        decay: Double,
        context: inout GraphicsContext
    ) {
        let decayMul = 1.0 - decay * 0.4
        for i in (1...Self.mindTrailGhosts).reversed() {
            let pastT = t - Double(i) * Self.mindTrailSpacing
            let ghostCenter = mindDriftPosition(e, size: size, t: pastT)
            let progress = Double(i) / Double(Self.mindTrailGhosts)
            let ghostOpacity = 0.35 * (1.0 - progress) * decayMul
            let ghostScale = 1.0 - progress * 0.15

            let gr = radius * ghostScale
            let hw = gr * aspect
            let hh = gr
            let ghostRect = CGRect(
                x: ghostCenter.x - hw, y: ghostCenter.y - hh,
                width: hw * 2, height: hh * 2
            )

            context.drawLayer { ctx in
                ctx.opacity = ghostOpacity
                ctx.blendMode = blendMode
                ctx.translateBy(x: ghostCenter.x, y: ghostCenter.y)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -ghostCenter.x, y: -ghostCenter.y)
                ctx.draw(image, in: ghostRect)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Element labels + centers
    // ═══════════════════════════════════════════════════════════

    private func elementCenter(_ element: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        switch element.category {
        case .body, .mind:
            return circleCenter(element, size: size, t: t)
        case .heart:
            return heartCenter(element, size: size, t: t)
        }
    }

    private func drawLabel(_ element: CanvasElement, at point: CGPoint, context: inout GraphicsContext, labelColor: Color, shadowColor: Color) {
        let labelText = element.displayLabel.uppercased()
        if showsOutlinedLabels {
            let offsets: [(CGFloat, CGFloat)] = [
                (-1, -1), (0, -1), (1, -1),
                (-1, 0),           (1, 0),
                (-1, 1),  (0, 1),  (1, 1)
            ]

            for offset in offsets {
                context.drawLayer { ctx in
                    ctx.opacity = 0.4
                    ctx.draw(
                        Text(labelText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(shadowColor),
                        at: CGPoint(x: point.x + offset.0, y: point.y + offset.1),
                        anchor: .center
                    )
                }
            }
        }

        let text = Text(labelText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(labelColor.opacity(0.9))
        context.draw(text, at: point, anchor: .center)
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
