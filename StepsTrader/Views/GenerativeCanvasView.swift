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
    /// When false, only activity elements are rendered (no radial background gradient).
    var showsBackgroundGradient: Bool = true

    /// Whether the background is visually dark — controls blend mode for elements.
    /// When true, uses `.plusLighter` (additive glow on dark). When false, uses `.normal`.
    private var isDarkBackground: Bool {
        let uiColor = UIColor(backgroundColor)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
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
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let decay = decayNorm

                // Unified background gradient
                if showsBackgroundGradient {
                    drawUnifiedGradient(context: &context, size: size, t: t)
                }

                // Activity elements + labels
                let circles = elements.filter { $0.kind == .circle }.sorted { $0.size > $1.size }
                let nonCircles = elements.filter { $0.kind != .circle }
                let sortedElements = circles + nonCircles

                for element in sortedElements {
                    drawElement(element, context: &context, size: size, t: t, decay: decay)

                    if showLabelsOnCanvas {
                        let center = elementCenter(element, size: size, t: t)
                        drawLabel(element, at: center, context: &context)
                    }
                }
            }
        }
        .background(backgroundColor)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Asset Pipeline
    // ═══════════════════════════════════════════════════════════

    private static let bodyCircleAssetNames = ["body 1", "body 2", "body 3"]
    private static let mindCircleAssetNames = ["mind 1"]
    private static let heartAssetNames = ["heart 1"]

    /// Stable, uniformly-distributed index derived from UUID bytes (not hashValue, which clusters).
    private static func assetIndex(for id: UUID, count: Int) -> Int {
        let uuid = id.uuid
        let mixed = Int(uuid.0) &+ Int(uuid.4) &* 31 &+ Int(uuid.8) &* 127 &+ Int(uuid.12) &* 8191
        return abs(mixed) % count
    }

    private static let tintedImageCacheMax = 400
    private static var tintedImageCache: [String: Image] = [:]
    private static let tintedImageCacheLock = NSLock()

    /// Renders an asset tinted with the user's color. Cached by (name, hex, decayBucket).
    private func tintedAssetImage(name: String, color: Color, hex: String, decay: Double) -> Image? {
        let decayBucket = min(10, max(0, Int(round(decay * 10))))
        let key = "\(name)|\(hex)|\(decayBucket)"
        Self.tintedImageCacheLock.lock()
        if let cached = Self.tintedImageCache[key] {
            Self.tintedImageCacheLock.unlock()
            return cached
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
        if Self.tintedImageCache.count >= Self.tintedImageCacheMax {
            Self.tintedImageCache.removeAll()
        }
        Self.tintedImageCache[key] = image
        Self.tintedImageCacheLock.unlock()
        return image
    }

    /// Luminance-mapped tinting: black stays black, grey mid-tones become the user's color,
    /// transparent stays transparent.
    private func luminanceTintedAssetImage(name: String, color: Color, hex: String, decay: Double) -> Image? {
        let decayBucket = min(10, max(0, Int(round(decay * 10))))
        let key = "lum|\(name)|\(hex)|\(decayBucket)"
        Self.tintedImageCacheLock.lock()
        if let cached = Self.tintedImageCache[key] {
            Self.tintedImageCacheLock.unlock()
            return cached
        }
        Self.tintedImageCacheLock.unlock()

        guard let original = UIImage(named: name),
              let cgImage = original.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let uiColor = UIColor(color)
        var tR: CGFloat = 0, tG: CGFloat = 0, tB: CGFloat = 0, tA: CGFloat = 0
        uiColor.getRed(&tR, green: &tG, blue: &tB, alpha: &tA)

        for i in 0..<(width * height) {
            let offset = i * bytesPerPixel
            let r = pixelData[offset]
            let g = pixelData[offset + 1]
            let b = pixelData[offset + 2]
            let a = pixelData[offset + 3]

            guard a > 0 else { continue }

            let af = CGFloat(a) / 255.0
            let trueR = CGFloat(r) / (af * 255.0)
            let trueG = CGFloat(g) / (af * 255.0)
            let trueB = CGFloat(b) / (af * 255.0)
            let luminance = min(1.0, 0.299 * trueR + 0.587 * trueG + 0.114 * trueB)

            pixelData[offset]     = UInt8(min(255, luminance * tR * 255.0 * af))
            pixelData[offset + 1] = UInt8(min(255, luminance * tG * 255.0 * af))
            pixelData[offset + 2] = UInt8(min(255, luminance * tB * 255.0 * af))
        }

        guard let outputContext = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let outputCG = outputContext.makeImage() else { return nil }

        let image = Image(uiImage: UIImage(cgImage: outputCG, scale: original.scale, orientation: original.imageOrientation))

        Self.tintedImageCacheLock.lock()
        if Self.tintedImageCache.count >= Self.tintedImageCacheMax {
            Self.tintedImageCache.removeAll()
        }
        Self.tintedImageCache[key] = image
        Self.tintedImageCacheLock.unlock()
        return image
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
        decay: Double
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
            // Enforce category-driven behavior (works for legacy saved elements too).
            switch element.category {
            case .body, .mind:
                drawCircle(element, context: &ctx, size: size, t: t, decay: decay)
            case .heart:
                drawRay(element, context: &ctx, size: size, t: t, decay: decay)
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Unified Background Gradient
    // ═══════════════════════════════════════════════════════════

    /// Radial gradient — warm gold center, coral & navy mid-ring, dark night edges.
    /// Steps intensify the warm core; sleep deepens the outer ring.
    /// Palette: #FFBF65 → #FD8973 → #003A6C → #13181B
    private func drawUnifiedGradient(context: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width)
        let h = Double(size.height)
        let dim = min(w, h)

        let stepsNorm = Double(min(max(stepsPoints, 0), 20)) / 20.0
        let sleepNorm = Double(min(max(sleepPoints, 0), 20)) / 20.0

        // Sunset palette
        let gold = Color(hex: "#FFBF65")     // warm center (steps)
        let coral = Color(hex: "#FD8973")     // warm-to-cool transition
        let navy = Color(hex: "#003A6C")      // cool-to-dark transition
        let night = Color(hex: "#13181B")     // dark edges (sleep)

        // Steps control core brightness + reach
        let goldOpacity = 0.35 + stepsNorm * 0.55
        let coralOpacity = 0.3 + stepsNorm * 0.4

        // Sleep controls edge darkness
        let navyOpacity = 0.3 + sleepNorm * 0.5
        let nightOpacity = 0.5 + sleepNorm * 0.5

        // Fixed center — exact middle of the screen, no drift
        let cx = w * 0.5
        let cy = h * 0.5
        let center = CGPoint(x: cx, y: cy)

        // Radial gradient: gold center → coral → navy → night edges
        let gradient = Gradient(stops: [
            .init(color: gold.opacity(goldOpacity), location: 0.0),
            .init(color: coral.opacity(coralOpacity), location: 0.25),
            .init(color: navy.opacity(navyOpacity), location: 0.55),
            .init(color: night.opacity(nightOpacity), location: 0.85),
            .init(color: night.opacity(nightOpacity), location: 1.0)
        ])

        let canvasRect = CGRect(x: 0, y: 0, width: w, height: h)
        let maxReach = max(w, h)

        context.drawLayer { ctx in
            ctx.fill(
                Path(canvasRect),
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: 0,
                    endRadius: maxReach * 0.7
                )
            )
        }

        // Soft secondary glow — also pinned to center
        let secondaryCenter = center
        let secondaryGrad = Gradient(colors: [
            gold.opacity(goldOpacity * 0.2),
            coral.opacity(coralOpacity * 0.08),
            .clear
        ])
        let glowRadius = dim * 0.4
        context.drawLayer { ctx in
            ctx.opacity = 0.5
            let shading = GraphicsContext.Shading.radialGradient(
                secondaryGrad,
                center: secondaryCenter,
                startRadius: 0,
                endRadius: glowRadius
            )
            ctx.fill(Ellipse().path(in: CGRect(
                x: secondaryCenter.x - glowRadius,
                y: secondaryCenter.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )), with: shading)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Body (Circle) — soft radial pulse
    // ═══════════════════════════════════════════════════════════

    /// Body: stable, minimal drift. Mind: wide-range slow fly-around.
    private func circleCenter(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        if e.category == .mind {
            return mindDriftPosition(e, size: size, t: t)
        }
        // Body: stable pulsing — barely perceptible drift
        let w = Double(size.width)
        let h = Double(size.height)
        let cx = Double(e.basePosition.x) * w
        let cy = Double(e.basePosition.y) * h
        let wobbleX = sin(t * 0.04 + e.phaseOffset) * w * 0.008
            + sin(t * 0.017 + e.phaseOffset * 2.3) * w * 0.005
        let wobbleY = cos(t * 0.035 + e.phaseOffset * 1.3) * h * 0.008
            + cos(t * 0.02 + e.phaseOffset * 0.7) * h * 0.005
        return CGPoint(x: cx + wobbleX, y: cy + wobbleY)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Mind Drift — slow fly-around across full canvas
    // ═══════════════════════════════════════════════════════════

    /// Multi-frequency Lissajous drift that covers the full canvas slowly.
    /// Each mind element gets unique paths via phaseOffset + driftSpeed.
    private func mindDriftPosition(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let w = Double(size.width)
        let h = Double(size.height)
        let p = e.phaseOffset
        let speed = 0.03 + e.driftSpeed * 0.06   // very slow: ~0.03–0.09

        // Sum of 4 sine harmonics — irregular, non-repeating-looking path
        let dx1 = sin(t * speed * 1.00 + p) * 0.34
        let dx2 = sin(t * speed * 2.37 + p * 2.3) * 0.12
        let dx3 = sin(t * speed * 4.13 + p * 4.1) * 0.04
        let dx4 = sin(t * speed * 6.71 + p * 6.7) * 0.015

        let dy1 = cos(t * speed * 0.83 + p * 1.7) * 0.32
        let dy2 = cos(t * speed * 1.97 + p * 3.1) * 0.11
        let dy3 = cos(t * speed * 3.61 + p * 5.3) * 0.04
        let dy4 = cos(t * speed * 5.89 + p * 7.9) * 0.015

        let nx = 0.5 + dx1 + dx2 + dx3 + dx4
        let ny = 0.5 + dy1 + dy2 + dy3 + dy4

        let margin = 0.06
        let cx = min(1.0 - margin, max(margin, nx)) * w
        let cy = min(1.0 - margin, max(margin, ny)) * h

        return CGPoint(x: cx, y: cy)
    }

    /// Velocity vector for mind drift — used to orient the asset in the travel direction.
    private func mindDriftVelocity(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        let p = e.phaseOffset
        let speed = 0.03 + e.driftSpeed * 0.06

        let vx1 = cos(t * speed * 1.00 + p) * speed * 1.00 * 0.34
        let vx2 = cos(t * speed * 2.37 + p * 2.3) * speed * 2.37 * 0.12
        let vx3 = cos(t * speed * 4.13 + p * 4.1) * speed * 4.13 * 0.04
        let vx4 = cos(t * speed * 6.71 + p * 6.7) * speed * 6.71 * 0.015

        let vy1 = -sin(t * speed * 0.83 + p * 1.7) * speed * 0.83 * 0.32
        let vy2 = -sin(t * speed * 1.97 + p * 3.1) * speed * 1.97 * 0.11
        let vy3 = -sin(t * speed * 3.61 + p * 5.3) * speed * 3.61 * 0.04
        let vy4 = -sin(t * speed * 5.89 + p * 7.9) * speed * 5.89 * 0.015

        return CGPoint(
            x: vx1 + vx2 + vx3 + vx4,
            y: vy1 + vy2 + vy3 + vy4
        )
    }

    private func drawCircle(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double
    ) {
        // Body: visible inhale/exhale pulse. Mind: no pulse (wandering is the motion).
        let pulse: Double = e.category == .body
            ? (1.0 + sin(t * (0.7 + e.pulseFrequency * 0.8) + e.phaseOffset) * 0.05)
            : 1.0
        let center = circleCenter(e, size: size, t: t)
        let dim = Double(min(size.width, size.height))
        let radius = Double(e.size) * dim * 1.1 * pulse
        let circleAssets = e.category == .body ? Self.bodyCircleAssetNames : Self.mindCircleAssetNames
        let name = circleAssets[Self.assetIndex(for: e.id, count: circleAssets.count)]
        let color = decayedColor(e.hexColor, decay: decay)
        guard let image = tintedAssetImage(name: name, color: color, hex: e.hexColor, decay: decay) else { return }
        let rect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )

        if e.category == .mind {
            // Rotate so the solid/front side faces the direction of travel.
            let vel = mindDriftVelocity(e, size: size, t: t)
            // Asset's solid face points left (–X) in source — flip 180° so it leads travel.
            let rotation = Angle.radians(atan2(vel.y, vel.x)) + .degrees(180)
            context.drawLayer { ctx in
                ctx.opacity = 0.6
                ctx.blendMode = elementBlendMode
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: rotation)
                ctx.translateBy(x: -center.x, y: -center.y)
                ctx.draw(image, in: rect)
            }
        } else {
            context.drawLayer { ctx in
                ctx.opacity = 0.6
                ctx.blendMode = elementBlendMode
                ctx.draw(image, in: rect)
            }
        }
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

    private func heartCenter(_ e: CanvasElement, size: CGSize, t: Double) -> CGPoint {
        heartDriftPosition(e, size: size, t: t)
    }

    /// Keep heart anchors visually close to edges/corners, even for legacy positions.
    private func edgeAnchoredCenter(_ e: CanvasElement, size: CGSize) -> CGPoint {
        let nx = Double(e.basePosition.x)
        let ny = Double(e.basePosition.y)

        let edgeInset = 0.08
        let minN = edgeInset
        let maxN = 1.0 - edgeInset

        let distLeft = nx
        let distRight = 1.0 - nx
        let distTop = ny
        let distBottom = 1.0 - ny
        let minDist = min(distLeft, distRight, distTop, distBottom)

        var ax = nx
        var ay = ny
        if minDist == distLeft {
            ax = minN
            ay = min(max(ny, minN), maxN)
        } else if minDist == distRight {
            ax = maxN
            ay = min(max(ny, minN), maxN)
        } else if minDist == distTop {
            ay = minN
            ax = min(max(nx, minN), maxN)
        } else {
            ay = maxN
            ax = min(max(nx, minN), maxN)
        }

        return CGPoint(x: ax * Double(size.width), y: ay * Double(size.height))
    }

    /// Direction from a point to the canvas center.
    private func angleTowardCanvasCenter(from point: CGPoint, size: CGSize) -> Angle {
        let canvasCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        return .radians(atan2(canvasCenter.y - point.y, canvasCenter.x - point.x))
    }

    private func drawSoftLine(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double
    ) {
        let phase = t * e.pulseFrequency * 0.5 + e.phaseOffset
        let pulse = 1.0 + sin(phase) * 0.05
        let center = heartCenter(e, size: size, t: t)
        let dim = Double(min(size.width, size.height))
        let radius = Double(e.size) * dim * 0.42 * pulse
        let color = decayedColor(e.hexColor, decay: decay)
        let name = Self.heartAssetNames[Self.assetIndex(for: e.id, count: Self.heartAssetNames.count)]
        guard let image = tintedAssetImage(name: name, color: color, hex: e.hexColor, decay: decay) else { return }
        let drawRect = CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )

        let inward = angleTowardCanvasCenter(from: center, size: size)
        // Asset's broad side points "up" in source; add 90deg so broad side aims inward.
        let rotation = inward + .degrees(90)

        context.drawLayer { ctx in
            ctx.opacity = 0.7
            ctx.blendMode = elementBlendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)
            ctx.draw(image, in: drawRect)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Heart (Ray) — angled rays pointing toward center
    // ═══════════════════════════════════════════════════════════

    /// Heart rays: hold their spawn position, only "look" left-right.
    private func raySearchAngle(_ e: CanvasElement, t: Double, size: CGSize) -> Angle {
        // Keep hearts horizontally oriented. Left side faces right, right side faces left.
        let isLeftSide = Double(e.basePosition.x) < 0.5
        let baseDeg = isLeftSide ? 0.0 : 180.0
        let sweepRange = 12.0 + e.rotationSpeed * 0.2
        let sweepSpeed = 0.012 + e.driftSpeed * 0.01
        let sweep = sin(t * sweepSpeed + e.phaseOffset * 2.1) * sweepRange
        return Angle.degrees(baseDeg + sweep)
    }

    private func drawRay(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double
    ) {
        let center = edgeAnchoredCenter(e, size: size)
        let dim = Double(min(size.width, size.height))
        let radius = Double(e.size) * dim * 2.2   // heart rays larger, at edges
        let breathe = 0.85 + sin(t * e.pulseFrequency * 0.5 + e.phaseOffset) * 0.1
        let color = decayedColor(e.hexColor, decay: decay)
        let angle = raySearchAngle(e, t: t, size: size)
        let name = Self.heartAssetNames[Self.assetIndex(for: e.id, count: Self.heartAssetNames.count)]
        guard let image = tintedAssetImage(name: name, color: color, hex: e.hexColor, decay: decay) else { return }
        let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        // Asset's broad side points "up" in source; add 90deg so broad side aims inward.
        let orientedAngle = angle + .degrees(90)

        context.drawLayer { ctx in
            ctx.opacity = breathe
            ctx.blendMode = elementBlendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: orientedAngle)
            ctx.draw(image, in: rect)
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
            return edgeAnchoredCenter(element, size: size)
        }
    }

    private func drawLabel(_ element: CanvasElement, at point: CGPoint, context: inout GraphicsContext) {
        let labelText = element.displayLabel.uppercased()
        let shadowColor = isDarkBackground ? Color.black : Color.white

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

        let text = Text(labelText)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(effectiveLabelColor.opacity(0.9))
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
