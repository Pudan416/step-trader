import SwiftUI
import UIKit

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

    /// Procedural shapes are the default. Set `useProceduralShapes` to false in UserDefaults to revert to legacy PNG assets.
    static let useProceduralShapes: Bool = {
        if UserDefaults.standard.object(forKey: "useProceduralShapes") != nil {
            return UserDefaults.standard.bool(forKey: "useProceduralShapes")
        }
        return true
    }()

    @State private var ampScale: Double = 1.0

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
    static var canonicalPortraitSize: CGSize {
        if _canonicalPortraitSizeOverride == .zero {
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                let b = scene.screen.bounds.size
                _canonicalPortraitSizeOverride = b.width <= b.height
                    ? b
                    : CGSize(width: b.height, height: b.width)
            }
        }
        return _canonicalPortraitSizeOverride == .zero
            ? CGSize(width: 393, height: 852)
            : _canonicalPortraitSizeOverride
    }
    private static var _canonicalPortraitSizeOverride: CGSize = .zero

    static func frozenElementCenter(_ element: CanvasElement, size: CGSize, at date: Date) -> CGPoint {
        let t = date.timeIntervalSinceReferenceDate
        let w = Double(size.width)
        let h = Double(size.height)

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
                + sin(t * speed * freq.fx1 + p) * 0.24 * env
                + sin(t * speed * freq.fx2 + p * 2.3) * 0.09 * env
                + sin(t * speed * freq.fx3 + p * 4.1) * 0.03
            let ny = hy
                + cos(t * speed * freq.fy1 + p * 1.7) * 0.22 * env
                + cos(t * speed * freq.fy2 + p * 3.1) * 0.08 * env
                + cos(t * speed * freq.fy3 + p * 5.3) * 0.03

            let margin = 0.06
            return CGPoint(
                x: min(1.0 - margin, max(margin, nx)) * w,
                y: min(1.0 - margin, max(margin, ny)) * h
            )

        case .body:
            let cx = Double(element.basePosition.x) * w
            let cy = Double(element.basePosition.y) * h
            let wobbleX = sin(t * 0.015 + element.phaseOffset) * w * 0.003
                + sin(t * 0.008 + element.phaseOffset * 2.3) * w * 0.002
            let wobbleY = cos(t * 0.013 + element.phaseOffset * 1.3) * h * 0.003
                + cos(t * 0.009 + element.phaseOffset * 0.7) * h * 0.002
            return CGPoint(x: cx + wobbleX, y: cy + wobbleY)

        case .heart:
            let cx = Double(element.basePosition.x) * w
            let cy = Double(element.basePosition.y) * h
            let wobbleX = sin(t * 0.012 + element.phaseOffset) * w * 0.004
                + sin(t * 0.007 + element.phaseOffset * 2.3) * w * 0.002
            let wobbleY = cos(t * 0.010 + element.phaseOffset * 1.3) * h * 0.004
                + cos(t * 0.006 + element.phaseOffset * 0.7) * h * 0.002
            return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
        }
    }

    static func sortedForRendering(_ elements: [CanvasElement]) -> [CanvasElement] {
        let circles = elements.filter { $0.kind == .circle }.sorted { $0.size > $1.size }
        let nonCircles = elements.filter { $0.kind != .circle }
        return circles + nonCircles
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

        let sortedElements = Self.sortedForRendering(elements)

        let interactions: [UUID: ElementInteraction]
        if Self.useProceduralShapes {
            interactions = computeInteractions(elements: sortedElements, size: size, t: t)
        } else {
            interactions = [:]
        }

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
        if Self.useProceduralShapes {
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
        }

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

    /// Normalized (0…1) position for interaction checks — uses animated
    /// position for mind (which drifts far from basePosition).
    private func interactionPosition(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        if e.category == .mind {
            let pos = mindDriftPosition(e, size: size, t: t)
            return CGPoint(x: pos.x / Double(size.width), y: pos.y / Double(size.height))
        }
        return e.basePosition
    }

    private func computeInteractions(
        elements: [CanvasElement],
        size: CGSize,
        t: Double
    ) -> [UUID: ElementInteraction] {
        var result = [UUID: ElementInteraction]()
        let interactionRadius: CGFloat = 0.25

        for i in 0..<elements.count {
            let a = elements[i]
            var interaction = ElementInteraction()
            let posA = interactionPosition(a, size: size, t: t)

            for j in 0..<elements.count where i != j {
                let b = elements[j]
                let posB = interactionPosition(b, size: size, t: t)
                let dx = posA.x - posB.x
                let dy = posA.y - posB.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist < interactionRadius else { continue }
                let proximity = 1.0 - Double(dist / interactionRadius)

                switch (a.category, b.category) {
                case (.body, .mind):
                    interaction.noiseBoost += proximity * 0.4
                case (.mind, .mind):
                    let repulsion = CGFloat(proximity) * 8.0
                    let len = max(dist, 0.001)
                    interaction.attractionOffset.dx += (dx / len) * repulsion
                    interaction.attractionOffset.dy += (dy / len) * repulsion
                default:
                    break
                }
            }

            if interaction.noiseBoost > 0.001
                || abs(interaction.attractionOffset.dx) > 0.01
                || abs(interaction.attractionOffset.dy) > 0.01
                || abs(interaction.stretchFactor - 1.0) > 0.001 {
                result[a.id] = interaction
            }
        }
        return result
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Asset Pipeline (legacy — retained for rollback, will be removed)
    // ═══════════════════════════════════════════════════════════

    private static let bodyCircleAssetNames = CanvasImageCatalog.body
    private static let mindCircleAssetNames = CanvasImageCatalog.mind
    private static let heartAssetNames = CanvasImageCatalog.heart

    /// Returns the asset index for an element. Prefers the persisted `assetVariant` (round-robin,
    /// guarantees variety). Falls back to UUID-based hash for legacy elements saved before the field existed.
    private static func assetIndex(for element: CanvasElement, count: Int) -> Int {
        if let variant = element.assetVariant {
            return variant % count
        }
        let uuid = element.id.uuid
        let mixed = Int(uuid.0) &+ Int(uuid.4) &* 31 &+ Int(uuid.8) &* 127 &+ Int(uuid.12) &* 8191
        return abs(mixed) % count
    }

    /// NSCache-compatible wrapper for SwiftUI Image (NSCache requires class types).
    private final class CachedImage {
        let image: Image
        init(_ image: Image) { self.image = image }
    }

    private static let tintedImageCache: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>()
        cache.countLimit = 900
        return cache
    }()
    private static let tintedImageCacheLock = NSLock()
    private static var assetAspectRatioCache: [String: CGFloat] = [:]

    /// Renders an asset tinted with the user's color. Cached by (name, hex, decayBucket).
    private func tintedAssetImage(name: String, color: Color, hex: String, decay: Double) -> Image? {
        let decayBucket = min(10, max(0, Int(round(decay * 10))))
        let key = "\(name)|\(hex)|\(decayBucket)" as NSString
        Self.tintedImageCacheLock.lock()
        if let cached = Self.tintedImageCache.object(forKey: key) {
            Self.tintedImageCacheLock.unlock()
            return cached.image
        }
        Self.tintedImageCacheLock.unlock()

        guard let template = UIImage(named: name)?.withRenderingMode(.alwaysTemplate) else { return nil }
        let sz = template.size
        let rect = CGRect(origin: .zero, size: sz)
        UIGraphicsBeginImageContextWithOptions(sz, false, template.scale)
        defer { UIGraphicsEndImageContext() }
        UIColor(color).set()
        template.draw(in: rect)
        guard let tinted = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        let image = Image(uiImage: tinted)

        Self.tintedImageCacheLock.lock()
        Self.tintedImageCache.setObject(CachedImage(image), forKey: key)
        Self.tintedImageCacheLock.unlock()
        return image
    }

    /// Returns asset width/height ratio (cached) to avoid geometry distortion when drawing.
    private func assetAspectRatio(name: String) -> CGFloat {
        Self.tintedImageCacheLock.lock()
        if let cached = Self.assetAspectRatioCache[name] {
            Self.tintedImageCacheLock.unlock()
            return cached
        }
        Self.tintedImageCacheLock.unlock()

        let ratio: CGFloat
        if let image = UIImage(named: name), image.size.height > 0 {
            ratio = image.size.width / image.size.height
        } else {
            ratio = 1.0
        }

        Self.tintedImageCacheLock.lock()
        Self.assetAspectRatioCache[name] = ratio
        Self.tintedImageCacheLock.unlock()
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

    private func mindDriftPosition(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let w = Double(size.width)
        let h = Double(size.height)
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

        let margin = 0.06
        let cx = min(1.0 - margin, max(margin, nx)) * w
        let cy = min(1.0 - margin, max(margin, ny)) * h

        return CGPoint(x: cx, y: cy)
    }

    /// Analytical velocity — derivative of mindDriftPosition w.r.t. t.
    private func mindDriftVelocity(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let p = e.phaseOffset
        let speed = 0.03 + e.driftSpeed * 0.06
        let amp = ampScale
        let freq = MindFrequencyProfile(phase: p)
        let env = mindAmplitudeEnvelope(e, speed: speed, t: t)

        let vx1 = cos(t * speed * freq.fx1 + p) * speed * freq.fx1 * 0.24 * amp * env
        let vx2 = cos(t * speed * freq.fx2 + p * 2.3) * speed * freq.fx2 * 0.09 * amp * env
        let vx3 = cos(t * speed * freq.fx3 + p * 4.1) * speed * freq.fx3 * 0.03 * amp

        let vy1 = -sin(t * speed * freq.fy1 + p * 1.7) * speed * freq.fy1 * 0.22 * amp * env
        let vy2 = -sin(t * speed * freq.fy2 + p * 3.1) * speed * freq.fy2 * 0.08 * amp * env
        let vy3 = -sin(t * speed * freq.fy3 + p * 5.3) * speed * freq.fy3 * 0.03 * amp

        return CGPoint(
            x: vx1 + vx2 + vx3,
            y: vy1 + vy2 + vy3
        )
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
            let name = mindAssets[Self.assetIndex(for: e, count: mindAssets.count)]
            let image: Image? = UIImage(named: name).map { Image(uiImage: $0) }
            let aspect = assetAspectRatio(name: name)
            let halfW = radius * aspect
            let halfH = radius

            let vel = mindDriftVelocity(e, size: size, t: t)
            let rotation = Angle.radians(atan2(vel.y, vel.x) + e.userRotation) + .degrees(270)

            if let image {
                drawMindAssetTrail(e, image: image, aspect: aspect, radius: radius, t: t, rotation: rotation, blendMode: blendMode, size: size, context: &context)
            }

            let idleOpacity = 0.76 + breathePhase * 0.04
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

        if Self.useProceduralShapes, let seed = e.shapeSeed {
            let baseComplexity = min(1.0, Double(e.activityCount ?? 1) / 30.0)
            let complexity = min(1.0, baseComplexity + (interaction?.noiseBoost ?? 0))
            let rect = CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            )

            drawProceduralBody(e, seed: seed, complexity: complexity, color: color, center: center, rect: rect, t: t, blendMode: blendMode, context: &context)
            return
        }

        // Legacy PNG fallback
        let circleAssets = Self.bodyCircleAssetNames
        let name = circleAssets[Self.assetIndex(for: e, count: circleAssets.count)]
        let image = tintedAssetImage(name: name, color: color, hex: e.hexColor, decay: decay)
        let aspect = image != nil ? assetAspectRatio(name: name) : 1.0
        let halfW = radius * aspect
        let halfH = radius
        let rect = CGRect(
            x: center.x - halfW, y: center.y - halfH,
            width: halfW * 2, height: halfH * 2
        )

        let rotation = Angle.radians(e.phaseOffset + e.userRotation)
        context.drawLayer { ctx in
            ctx.opacity = 0.85
            ctx.blendMode = blendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)
            if let image {
                ctx.draw(image, in: rect)
            } else {
                drawFallbackBlob(context: &ctx, in: rect, color: color)
            }
        }
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
    // MARK: - Heart (Soft Line) — gentle floating drift
    // ═══════════════════════════════════════════════════════════

    /// Gentle sine-wave drift — hearts float slowly across the canvas.
    private func heartDriftPosition(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = e.phaseOffset
        let speed = e.driftSpeed * 1.2

        let dx1 = sin(t * speed * 0.06 + p) * 0.35
        let dx2 = sin(t * speed * 0.14 + p * 2.3) * 0.15
        let dx3 = sin(t * speed * 0.27 + p * 4.1) * 0.06
        let dx4 = sin(t * speed * 0.41 + p * 6.7) * 0.02

        let dy1 = cos(t * speed * 0.05 + p * 1.7) * 0.30
        let dy2 = cos(t * speed * 0.12 + p * 3.1) * 0.14
        let dy3 = cos(t * speed * 0.23 + p * 5.3) * 0.06
        let dy4 = cos(t * speed * 0.38 + p * 7.9) * 0.02

        let nx = 0.5 + dx1 + dx2 + dx3 + dx4
        let ny = 0.5 + dy1 + dy2 + dy3 + dy4

        let margin = 0.04
        let cx = min(1.0 - margin, max(margin, nx)) * w
        let cy = min(1.0 - margin, max(margin, ny)) * h

        return CGPoint(x: cx, y: cy)
    }

    /// Velocity vector — orients the asset in the direction of travel.
    private func heartDriftVelocity(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let p = e.phaseOffset
        let speed = e.driftSpeed * 1.2

        let vx1 = cos(t * speed * 0.06 + p) * speed * 0.06 * 0.35
        let vx2 = cos(t * speed * 0.14 + p * 2.3) * speed * 0.14 * 0.15
        let vx3 = cos(t * speed * 0.27 + p * 4.1) * speed * 0.27 * 0.06
        let vx4 = cos(t * speed * 0.41 + p * 6.7) * speed * 0.41 * 0.02

        let vy1 = -sin(t * speed * 0.05 + p * 1.7) * speed * 0.05 * 0.30
        let vy2 = -sin(t * speed * 0.12 + p * 3.1) * speed * 0.12 * 0.14
        let vy3 = -sin(t * speed * 0.23 + p * 5.3) * speed * 0.23 * 0.06
        let vy4 = -sin(t * speed * 0.38 + p * 7.9) * speed * 0.38 * 0.02

        return CGPoint(
            x: vx1 + vx2 + vx3 + vx4,
            y: vy1 + vy2 + vy3 + vy4
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
            ctx.opacity = breathe
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
        let bodyElements = elements.filter {
            $0.category == .body && Self.useProceduralShapes && $0.shapeSeed != nil
        }
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
        var blobPaths = [(blob: BodyBlobInfo, path: Path)]()
        for blob in cluster {
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
            let rotation = CGAffineTransform(translationX: -blob.center.x, y: -blob.center.y)
                .concatenating(.init(rotationAngle: e.phaseOffset + e.userRotation))
                .concatenating(.init(translationX: blob.center.x, y: blob.center.y))
            let transformed = Path(rawPath.cgPath.copy(using: [rotation])!)
            blobPaths.append((blob, transformed))
        }

        var mergedCG = blobPaths[0].path.cgPath
        for i in 1..<blobPaths.count {
            mergedCG = mergedCG.union(blobPaths[i].path.cgPath)
        }
        let mergedPath = Path(mergedCG)

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.clip(to: mergedPath)

            for (blob, _) in blobPaths {
                let r = blob.radius
                let innerR = max(0, r - 40)
                let edgeLoc = r > 0 ? Double(innerR / r) : 0

                let rimGrad = Gradient(stops: [
                    .init(color: blob.color.opacity(0.12), location: 0),
                    .init(color: blob.color.opacity(0.10), location: edgeLoc),
                    .init(color: blob.color.opacity(0.35), location: edgeLoc + (1.0 - edgeLoc) * 0.5),
                    .init(color: blob.color.opacity(0.55), location: 1.0),
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

        for (blob, _) in blobPaths {
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
                    with: .color(blob.color.opacity(0.65)),
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
        context: inout GraphicsContext
    ) {
        for i in (1...Self.mindTrailGhosts).reversed() {
            let pastT = t - Double(i) * Self.mindTrailSpacing
            let ghostCenter = mindDriftPosition(e, size: size, t: pastT)
            let progress = Double(i) / Double(Self.mindTrailGhosts)
            let ghostOpacity = 0.35 * (1.0 - progress)
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
