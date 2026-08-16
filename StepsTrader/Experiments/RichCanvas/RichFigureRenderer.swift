import SwiftUI

struct RichFigureMotionState: Equatable {
    let center: CGPoint
    let rotation: Angle
    let scale: CGFloat
    let deformationTime: Double
    let highlightPhase: Double
}

struct RichRGBA: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    static let white = RichRGBA(red: 1, green: 1, blue: 1, alpha: 1)
    static let neutral = RichRGBA(red: 0.45, green: 0.48, blue: 0.52, alpha: 1)

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct RichResolvedColors: Equatable {
    let primary: RichRGBA
    let secondary: RichRGBA
}

enum RichFigureRenderer {
    private enum ContentLayer {
        case base, fill, surface, highlight, particle
    }

    static func center(
        for item: RichFigurePreviewItem,
        canvasSize: CGSize
    ) -> CGPoint {
        let fallback = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              item.layout.center.x.isFinite, item.layout.center.y.isFinite else {
            return fallback
        }
        return CGPoint(
            x: item.layout.center.x * canvasSize.width,
            y: item.layout.center.y * canvasSize.height
        )
    }

    @MainActor
    static func motionState(
        for item: RichFigurePreviewItem,
        canvasSize: CGSize,
        time: Double,
        reduceMotion: Bool
    ) -> RichFigureMotionState {
        let baseCenter = center(for: item, canvasSize: canvasSize)
        let canonicalTime = canonicalDeformationTime(seed: item.style.geometrySeed)
        let canonicalHighlight = unitPhase(
            Double(item.style.geometrySeed % 10_000) / 10_000
        )
        guard !reduceMotion else {
            return RichFigureMotionState(
                center: baseCenter,
                rotation: .zero,
                scale: 1,
                deformationTime: canonicalTime,
                highlightPhase: canonicalHighlight
            )
        }

        let safeTime = time.isFinite ? time : canonicalTime
        let speed = item.style.speedMultiplier.isFinite
            ? max(0.1, item.style.speedMultiplier)
            : 1
        let phase = item.style.animationPhase.isFinite
            ? item.style.animationPhase
            : 0

        switch item.style.family {
        case .circle:
            return RichFigureMotionState(
                center: baseCenter,
                rotation: .zero,
                scale: 1 + 0.02 * sin(safeTime * 0.42 * speed + phase),
                deformationTime: canonicalTime,
                highlightPhase: unitPhase(
                    safeTime * 0.07 * speed + phase / (2 * .pi) + 0.23
                )
            )
        case .luminousOrganic:
            return RichFigureMotionState(
                center: baseCenter,
                rotation: .zero,
                scale: 1,
                deformationTime: canonicalTime + safeTime * 0.16 * speed,
                highlightPhase: unitPhase(
                    safeTime * 0.035 * speed + phase / (2 * .pi)
                )
            )
        case .crystallineStar:
            return RichFigureMotionState(
                center: SnowflakeShapeRenderer.driftPosition(
                    item.source,
                    size: canvasSize,
                    t: safeTime,
                    ampScale: 1
                ),
                rotation: .radians(safeTime * 0.055 * speed + phase),
                scale: 1,
                deformationTime: safeTime,
                highlightPhase: unitPhase(
                    safeTime * 0.09 * speed + phase / (2 * .pi)
                )
            )
        case .rays:
            return RichFigureMotionState(
                center: baseCenter,
                rotation: .zero,
                scale: 1 + 0.04 * sin(safeTime * 0.20 * speed + phase),
                deformationTime: canonicalTime,
                highlightPhase: unitPhase(
                    safeTime * 0.11 * speed + phase / (2 * .pi)
                )
            )
        case .orbitalSpirograph:
            return RichFigureMotionState(
                center: baseCenter,
                rotation: .radians(safeTime * 0.035 * speed + phase),
                scale: 1,
                deformationTime: canonicalTime,
                highlightPhase: unitPhase(
                    safeTime * 0.055 * speed + phase / (2 * .pi)
                )
            )
        }
    }

    @MainActor
    static func draw(
        item: RichFigurePreviewItem,
        context: inout GraphicsContext,
        canvasSize: CGSize,
        time: Double,
        budget: RichRenderBudget,
        particleCount: Int,
        reduceMotion: Bool,
        cache: RichRenderCache
    ) {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0 else { return }

        let motion = motionState(
            for: item,
            canvasSize: canvasSize,
            time: time,
            reduceMotion: reduceMotion
        )
        let geometryTime = reduceMotion
            ? motion.deformationTime
            : (time.isFinite ? time : motion.deformationTime)
        let bucket = RichTimeBuckets.bucket(
            time: geometryTime,
            seed: item.style.geometrySeed
        )
        let key = RichGeometryCacheKey(
            family: item.style.family,
            fill: item.style.fill,
            seed: item.style.geometrySeed,
            detailTier: item.style.detailTier,
            timeBucket: bucket
        )
        let cached = cache.geometry(for: key) {
            let canonicalTime = Double(bucket) * RichTimeBuckets.bucketSeconds
                - RichTimeBuckets.phase(for: item.style.geometrySeed)
            let canonicalBudget = RichRenderBudget.resolve(
                elementCount: 1,
                lowPowerMode: false
            )
            let base = RichFigureGeometryFactory.make(
                family: item.style.family,
                seed: item.style.geometrySeed,
                detailTier: item.style.detailTier,
                canonicalTime: canonicalTime,
                budget: canonicalBudget
            )
            return RichCachedGeometry(
                base: base,
                fill: RichFillGeometryFactory.make(
                    fill: item.style.fill,
                    base: base,
                    seed: item.style.geometrySeed,
                    budget: canonicalBudget
                )
            )
        }
        let geometry = applyingBudget(
            budget,
            fillKind: item.style.fill,
            to: validatedGeometry(cached)
        )
        let colors = resolvedColors(
            primaryHex: item.style.primaryHex,
            secondaryHex: item.style.secondaryHex
        )
        let primary = colors.primary.color
        let secondary = colors.secondary.color
        let targetDiameter = item.layout.targetDiameterFraction
            * min(canvasSize.width, canvasSize.height)
        let fittedScale = RichFigureLayout.fittedScale(
            canonicalBounds: geometry.base.bounds,
            targetDiameter: targetDiameter,
            opticalScale: item.layout.opticalScale
        )
        guard fittedScale.isFinite, fittedScale > 0 else { return }

        let basePath = path(
            for: geometry.base.lines,
            layer: .base,
            item: item,
            geometry: geometry.base,
            motion: motion,
            fittedScale: fittedScale
        )
        let fillPath = path(
            for: geometry.fill.lines,
            layer: .fill,
            item: item,
            geometry: geometry.base,
            motion: motion,
            fittedScale: fittedScale
        )
        let allLinePath = combined(basePath, fillPath)
        let core = transformed(
            geometry.base.core,
            lineIndex: 0,
            role: .accent,
            layer: .highlight,
            item: item,
            geometry: geometry.base,
            motion: motion,
            fittedScale: fittedScale
        )
        let blendMode: GraphicsContext.BlendMode =
            context.environment.colorScheme == .dark ? .plusLighter : .normal
        let lineWidth = max(0.65, min(2.2, targetDiameter * 0.008))
        let glowIntensity = item.style.glowIntensity.isFinite
            ? min(1, max(0, item.style.glowIntensity))
            : 0.65

        if budget.glowPassCount >= 1 {
            let blur = min(10, max(2, targetDiameter * item.layout.overscanFraction * 0.18))
            context.drawLayer { layer in
                layer.blendMode = blendMode
                layer.addFilter(.blur(radius: blur))
                layer.stroke(
                    allLinePath,
                    with: .color(primary.opacity(0.30 * glowIntensity)),
                    style: StrokeStyle(
                        lineWidth: lineWidth * 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }

        if budget.glowPassCount == 2 {
            let radius = min(18, max(5, targetDiameter * 0.08))
            let glowPath = Path(ellipseIn: CGRect(
                x: core.x - radius / 2,
                y: core.y - radius / 2,
                width: radius,
                height: radius
            ))
            context.drawLayer { layer in
                layer.blendMode = blendMode
                layer.addFilter(.blur(radius: min(7, radius * 0.35)))
                layer.fill(
                    glowPath,
                    with: .color(secondary.opacity(0.55 * glowIntensity))
                )
            }
        }

        drawTranslucentSurfaces(
            geometry.fill.translucentSurfaces,
            context: &context,
            blendMode: blendMode,
            primary: primary,
            secondary: secondary,
            item: item,
            geometry: geometry.base,
            motion: motion,
            fittedScale: fittedScale
        )

        context.drawLayer { layer in
            layer.blendMode = blendMode
            if item.style.fill == .luminousGradient,
               let envelope = geometry.base.lines.first(where: {
                   $0.isClosed && $0.points.count > 2
               }) {
                let envelopePath = path(
                    for: [envelope],
                    layer: .surface,
                    item: item,
                    geometry: geometry.base,
                    motion: motion,
                    fittedScale: fittedScale
                )
                let gradient = Gradient(colors: [
                    primary.opacity(0.08),
                    secondary.opacity(0.24),
                    primary.opacity(0.04)
                ])
                layer.fill(
                    envelopePath,
                    with: .radialGradient(
                        gradient,
                        center: core,
                        startRadius: 0,
                        endRadius: max(1, targetDiameter * 0.55)
                    )
                )
            }
            layer.stroke(
                basePath,
                with: .linearGradient(
                    Gradient(colors: [primary, secondary]),
                    startPoint: CGPoint(
                        x: motion.center.x - targetDiameter / 2,
                        y: motion.center.y - targetDiameter / 2
                    ),
                    endPoint: CGPoint(
                        x: motion.center.x + targetDiameter / 2,
                        y: motion.center.y + targetDiameter / 2
                    )
                ),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            layer.stroke(
                fillPath,
                with: .color(secondary.opacity(0.82)),
                style: StrokeStyle(
                    lineWidth: max(0.5, lineWidth * 0.72),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        drawHighlights(
            geometry.fill.highlightPoints,
            core: core,
            context: &context,
            blendMode: blendMode,
            primary: primary,
            secondary: secondary,
            item: item,
            geometry: geometry.base,
            motion: motion,
            fittedScale: fittedScale,
            targetDiameter: targetDiameter
        )

        if item.style.particleEligible {
            let boundedCount = min(
                max(0, particleCount),
                max(0, budget.globalParticleCount)
            )
            drawParticles(
                particlePoints(
                    in: geometry.base,
                    count: boundedCount,
                    seed: item.style.geometrySeed,
                    phase: motion.highlightPhase
                ),
                context: &context,
                blendMode: blendMode,
                color: secondary,
                item: item,
                geometry: geometry.base,
                motion: motion,
                fittedScale: fittedScale,
                targetDiameter: targetDiameter
            )
        }
    }

    static func validatedGeometry(_ geometry: RichCachedGeometry) -> RichCachedGeometry {
        guard validBase(geometry.base), validFill(geometry.fill) else {
            return fallbackGeometry()
        }
        return geometry
    }

    static func resolvedColors(
        primaryHex: String,
        secondaryHex: String?
    ) -> RichResolvedColors {
        let primary = parseHex(primaryHex) ?? .neutral
        let secondary = secondaryHex.flatMap(parseHex) ?? primary
        return RichResolvedColors(primary: primary, secondary: secondary)
    }

    static func particlePoints(
        in geometry: RichFigureGeometry,
        count: Int,
        seed: UInt64,
        phase: Double
    ) -> [CGPoint] {
        guard count > 0 else { return [] }
        let candidates = geometry.lines.filter { $0.points.count >= 2 }
        guard !candidates.isEmpty else { return [] }
        let safePhase = phase.isFinite ? unitPhase(phase) : 0
        let start = Int(seed % UInt64(candidates.count))

        return (0..<count).map { index in
            let line = candidates[(start + index) % candidates.count]
            let segmentCount = line.isClosed ? line.points.count : line.points.count - 1
            let progress = unitPhase(
                safePhase + Double(index) / Double(max(1, count))
            )
            let scaled = progress * Double(segmentCount)
            let segment = min(segmentCount - 1, Int(floor(scaled)))
            let localProgress = scaled - Double(segment)
            let startPoint = line.points[segment]
            let endPoint = line.points[(segment + 1) % line.points.count]
            return CGPoint(
                x: startPoint.x + (endPoint.x - startPoint.x) * localProgress,
                y: startPoint.y + (endPoint.y - startPoint.y) * localProgress
            )
        }
    }

    private static func canonicalDeformationTime(seed: UInt64) -> Double {
        Double(seed % 65_521) / 997
    }

    private static func unitPhase(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private static func parseHex(_ input: String) -> RichRGBA? {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard [3, 4, 6, 8].contains(raw.count),
              let value = UInt64(raw, radix: 16) else { return nil }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64
        switch raw.count {
        case 3:
            red = (value >> 8) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
            alpha = 255
        case 4:
            alpha = ((value >> 12) & 0xF) * 17
            red = ((value >> 8) & 0xF) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        case 6:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 255
        default:
            alpha = value >> 24
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }
        return RichRGBA(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: Double(alpha) / 255
        )
    }

    private static func validBase(_ base: RichFigureGeometry) -> Bool {
        guard base.bounds.origin.x.isFinite, base.bounds.origin.y.isFinite,
              base.bounds.width.isFinite, base.bounds.height.isFinite,
              base.bounds.width > 0, base.bounds.height > 0,
              base.core.x.isFinite, base.core.y.isFinite,
              !base.lines.isEmpty else { return false }
        return base.lines.allSatisfy { line in
            let enoughPoints = line.isClosed
                ? line.points.count >= 3
                : line.points.count >= 2
            return enoughPoints && line.points.allSatisfy(validPoint)
        }
    }

    private static func validFill(_ fill: RichFillGeometry) -> Bool {
        let validLines = fill.lines.allSatisfy { line in
            let enoughPoints = line.isClosed
                ? line.points.count >= 3
                : line.points.count >= 2
            return enoughPoints && line.points.allSatisfy(validPoint)
        }
        let validSurfaces = fill.translucentSurfaces.allSatisfy {
            $0.count >= 3 && $0.allSatisfy(validPoint)
        }
        return validLines
            && validSurfaces
            && fill.highlightPoints.allSatisfy(validPoint)
    }

    private static func validPoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
            && (-1.000_001...1.000_001).contains(point.x)
            && (-1.000_001...1.000_001).contains(point.y)
    }

    private static func fallbackGeometry() -> RichCachedGeometry {
        let sampleCount = 64
        let points = (0..<sampleCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(sampleCount)
            return CGPoint(x: cos(angle), y: sin(angle))
        }
        let circle = RichPolyline(
            points: points,
            isClosed: true,
            role: .silhouette
        )
        return RichCachedGeometry(
            base: RichFigureGeometry(
                lines: [circle],
                core: .zero,
                bounds: CGRect(x: -1, y: -1, width: 2, height: 2)
            ),
            fill: RichFillGeometry(
                lines: [],
                translucentSurfaces: [points],
                highlightPoints: [.zero]
            )
        )
    }

    private static func applyingBudget(
        _ budget: RichRenderBudget,
        fillKind: RichFillKind,
        to geometry: RichCachedGeometry
    ) -> RichCachedGeometry {
        let baseLines: [RichPolyline]
        if geometry.base.lines.contains(where: { $0.role == .orbit }) {
            var orbitCount = 0
            baseLines = geometry.base.lines.filter { line in
                guard line.role == .orbit else { return true }
                defer { orbitCount += 1 }
                return orbitCount < max(0, budget.orbitalRingCount)
            }
        } else {
            baseLines = geometry.base.lines
        }

        let lineLimit: Int
        switch fillKind {
        case .nestedContours:
            lineLimit = budget.contourCount
        case .orbitalLines:
            lineLimit = budget.orbitalRingCount
        case .filamentField:
            lineLimit = budget.filamentCount
        case .luminousGradient, .outlineWithCore, .layeredTranslucentMass:
            lineLimit = geometry.fill.lines.count
        }
        let surfaceLimit = fillKind == .layeredTranslucentMass
            ? min(5, max(3, budget.contourCount / 2))
            : geometry.fill.translucentSurfaces.count
        return RichCachedGeometry(
            base: RichFigureGeometry(
                lines: baseLines,
                core: geometry.base.core,
                bounds: geometry.base.bounds
            ),
            fill: RichFillGeometry(
                lines: Array(geometry.fill.lines.prefix(max(0, lineLimit))),
                translucentSurfaces: Array(
                    geometry.fill.translucentSurfaces.prefix(max(0, surfaceLimit))
                ),
                highlightPoints: geometry.fill.highlightPoints
            )
        )
    }

    private static func path(
        for lines: [RichPolyline],
        layer: ContentLayer,
        item: RichFigurePreviewItem,
        geometry: RichFigureGeometry,
        motion: RichFigureMotionState,
        fittedScale: CGFloat
    ) -> Path {
        var result = Path()
        for (lineIndex, line) in lines.enumerated() {
            guard let first = line.points.first else { continue }
            result.move(to: transformed(
                first,
                lineIndex: lineIndex,
                role: line.role,
                layer: layer,
                item: item,
                geometry: geometry,
                motion: motion,
                fittedScale: fittedScale
            ))
            for point in line.points.dropFirst() {
                result.addLine(to: transformed(
                    point,
                    lineIndex: lineIndex,
                    role: line.role,
                    layer: layer,
                    item: item,
                    geometry: geometry,
                    motion: motion,
                    fittedScale: fittedScale
                ))
            }
            if line.isClosed { result.closeSubpath() }
        }
        return result
    }

    private static func combined(_ first: Path, _ second: Path) -> Path {
        var result = first
        result.addPath(second)
        return result
    }

    private static func transformed(
        _ point: CGPoint,
        lineIndex: Int,
        role: RichPolyline.Role,
        layer: ContentLayer,
        item: RichFigurePreviewItem,
        geometry: RichFigureGeometry,
        motion: RichFigureMotionState,
        fittedScale: CGFloat
    ) -> CGPoint {
        var canonical = point
        var rotation = 0.0
        var uniformScale = 1.0

        switch item.style.family {
        case .circle:
            uniformScale = Double(motion.scale)
        case .luminousOrganic:
            let x = Double(point.x - geometry.core.x)
            let y = Double(point.y - geometry.core.y)
            let angle = atan2(y, x)
            let deformation = 1 + 0.025 * sin(
                angle * 3 + motion.deformationTime + item.style.animationPhase
            )
            canonical = CGPoint(
                x: geometry.core.x + x * deformation,
                y: geometry.core.y + y * deformation
            )
        case .crystallineStar:
            switch (layer, role) {
            case (.base, .structure):
                rotation = -motion.rotation.radians * 0.65
            case (.fill, _), (.surface, _):
                rotation = -motion.rotation.radians * 0.35
            default:
                rotation = motion.rotation.radians * 0.40
            }
        case .rays:
            if point != geometry.core {
                let x = Double(point.x - geometry.core.x)
                let y = Double(point.y - geometry.core.y)
                let angle = atan2(y, x)
                let distance = hypot(x, y)
                let centerAngle = -0.32
                let openedAngle = centerAngle
                    + (angle - centerAngle) * Double(motion.scale)
                canonical = CGPoint(
                    x: geometry.core.x + distance * cos(openedAngle),
                    y: geometry.core.y + distance * sin(openedAngle)
                )
            }
        case .orbitalSpirograph:
            let direction = lineIndex.isMultiple(of: 2) ? 1.0 : -1.0
            let rate = 0.45 + Double(lineIndex % 5) * 0.18
            rotation = motion.rotation.radians * direction * rate
        }

        let centerX = geometry.bounds.midX
        let centerY = geometry.bounds.midY
        var x = Double(canonical.x - centerX) * Double(fittedScale) * uniformScale
        var y = Double(canonical.y - centerY) * Double(fittedScale) * uniformScale
        if rotation != 0 {
            let cosine = cos(rotation)
            let sine = sin(rotation)
            (x, y) = (x * cosine - y * sine, x * sine + y * cosine)
        }
        return CGPoint(
            x: motion.center.x + x,
            y: motion.center.y + y
        )
    }

    private static func drawTranslucentSurfaces(
        _ surfaces: [[CGPoint]],
        context: inout GraphicsContext,
        blendMode: GraphicsContext.BlendMode,
        primary: Color,
        secondary: Color,
        item: RichFigurePreviewItem,
        geometry: RichFigureGeometry,
        motion: RichFigureMotionState,
        fittedScale: CGFloat
    ) {
        context.drawLayer { layer in
            layer.blendMode = blendMode
            for (index, points) in surfaces.enumerated() {
                let line = RichPolyline(
                    points: points,
                    isClosed: true,
                    role: .accent
                )
                let surfacePath = path(
                    for: [line],
                    layer: .surface,
                    item: item,
                    geometry: geometry,
                    motion: motion,
                    fittedScale: fittedScale
                )
                let color = index.isMultiple(of: 2) ? primary : secondary
                layer.fill(
                    surfacePath,
                    with: .color(color.opacity(max(0.06, 0.22 - Double(index) * 0.025)))
                )
            }
        }
    }

    private static func drawHighlights(
        _ points: [CGPoint],
        core: CGPoint,
        context: inout GraphicsContext,
        blendMode: GraphicsContext.BlendMode,
        primary: Color,
        secondary: Color,
        item: RichFigurePreviewItem,
        geometry: RichFigureGeometry,
        motion: RichFigureMotionState,
        fittedScale: CGFloat,
        targetDiameter: CGFloat
    ) {
        let radius = min(7, max(1.8, targetDiameter * 0.018))
        var highlightPath = Path(ellipseIn: CGRect(
            x: core.x - radius,
            y: core.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        for (index, point) in points.enumerated() {
            let transformedPoint = transformed(
                point,
                lineIndex: index,
                role: .accent,
                layer: .highlight,
                item: item,
                geometry: geometry,
                motion: motion,
                fittedScale: fittedScale
            )
            highlightPath.addEllipse(in: CGRect(
                x: transformedPoint.x - radius * 0.65,
                y: transformedPoint.y - radius * 0.65,
                width: radius * 1.3,
                height: radius * 1.3
            ))
        }
        context.drawLayer { layer in
            layer.blendMode = blendMode
            layer.fill(
                highlightPath,
                with: .linearGradient(
                    Gradient(colors: [primary, secondary]),
                    startPoint: CGPoint(x: core.x - radius, y: core.y - radius),
                    endPoint: CGPoint(x: core.x + radius, y: core.y + radius)
                )
            )
        }
    }

    private static func drawParticles(
        _ points: [CGPoint],
        context: inout GraphicsContext,
        blendMode: GraphicsContext.BlendMode,
        color: Color,
        item: RichFigurePreviewItem,
        geometry: RichFigureGeometry,
        motion: RichFigureMotionState,
        fittedScale: CGFloat,
        targetDiameter: CGFloat
    ) {
        let radius = min(2.4, max(0.7, targetDiameter * 0.007))
        var particlePath = Path()
        for (index, point) in points.enumerated() {
            let transformedPoint = transformed(
                point,
                lineIndex: index,
                role: .orbit,
                layer: .particle,
                item: item,
                geometry: geometry,
                motion: motion,
                fittedScale: fittedScale
            )
            particlePath.addEllipse(in: CGRect(
                x: transformedPoint.x - radius,
                y: transformedPoint.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        context.drawLayer { layer in
            layer.blendMode = blendMode
            layer.fill(particlePath, with: .color(color.opacity(0.88)))
        }
    }
}
