import SwiftUI

/// Self-contained renderer for the "Blob" shape type.
/// Provides positioning (stable center + tiny wobble), procedural organic path,
/// rim-gradient fill, and metaball clustering for nearby blobs.
@MainActor
enum BlobShapeRenderer {

    // MARK: - Positioning

    static func center(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
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

    static func frozenCenter(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> CGPoint {
        center(e, size: size, t: t, ampScale: ampScale)
    }

    // MARK: - Sizing

    static let sizeScale: Double = 1.05

    static func radius(
        _ e: CanvasElement,
        size: CGSize,
        t: Double,
        ampScale: Double
    ) -> Double {
        let dim = Double(min(size.width, size.height))
        let effectiveSize = e.userSize ?? e.size
        let pulse = 1.0 + sin(t * (0.3 + e.pulseFrequency * 0.3) + e.phaseOffset) * 0.02 * ampScale
        return Double(effectiveSize) * dim * sizeScale * pulse
    }

    // MARK: - Single Element Drawing

    static func draw(
        _ e: CanvasElement,
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        decay: Double,
        blendMode: GraphicsContext.BlendMode,
        ampScale: Double,
        interaction: ElementInteraction?,
        decayedColor: Color,
        decayedColor2: Color? = nil
    ) {
        let center = center(e, size: size, t: t, ampScale: ampScale)
        let r = radius(e, size: size, t: t, ampScale: ampScale)
        let seed = e.shapeSeed ?? UInt64(bitPattern: Int64(e.id.hashValue))
        let baseComplexity = min(1.0, Double(e.activityCount ?? 1) / 30.0)
        let complexity = min(1.0, baseComplexity + (interaction?.noiseBoost ?? 0))
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)

        let path = ProceduralShapeGenerator.bodyPath(
            seed: seed, complexity: complexity, time: t, in: rect
        )
        drawFill(
            path: path, color: decayedColor, color2: decayedColor2,
            center: center, rect: rect,
            phase: e.phaseOffset, userRotation: e.userRotation,
            blendMode: blendMode, context: &context
        )
    }

    // MARK: - Fill Rendering

    static func drawFill(
        path: Path,
        color: Color,
        color2: Color? = nil,
        center: CGPoint,
        rect: CGRect,
        phase: Double,
        userRotation: Double,
        blendMode: GraphicsContext.BlendMode,
        context: inout GraphicsContext
    ) {
        let rotation = Angle.radians(phase + userRotation)
        let r = min(rect.width, rect.height) / 2
        let innerR = max(0, r - 40)
        let edgeLoc = r > 0 ? Double(innerR / r) : 0

        let gradCenter: CGPoint
        if color2 != nil {
            let offsetAngle = phase * 2.7
            let offsetR = r * 0.3
            gradCenter = CGPoint(
                x: center.x + CGFloat(cos(offsetAngle)) * offsetR,
                y: center.y + CGFloat(sin(offsetAngle)) * offsetR
            )
        } else {
            gradCenter = center
        }

        let innerColor = color
        let outerColor = color2 ?? color

        let rimGrad = Gradient(stops: [
            .init(color: innerColor.opacity(0.18), location: 0),
            .init(color: innerColor.opacity(0.22), location: edgeLoc),
            .init(color: outerColor.opacity(0.50), location: edgeLoc + (1.0 - edgeLoc) * 0.5),
            .init(color: outerColor.opacity(0.72), location: 1.0),
        ])

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.translateBy(x: center.x, y: center.y)
            ctx.rotate(by: rotation)
            ctx.translateBy(x: -center.x, y: -center.y)

            ctx.clip(to: path)
            let ellipse = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(
                Path(ellipseIn: ellipse),
                with: .radialGradient(rimGrad, center: gradCenter, startRadius: 0, endRadius: r)
            )

            let strokeColor = color2 != nil
                ? outerColor.opacity(0.65)
                : color.opacity(0.65)
            ctx.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Cluster Collection

    static func collectClusters(
        elements: [CanvasElement],
        shapeFilter: (CanvasElement) -> Bool,
        size: CGSize,
        t: Double,
        decay: Double,
        ampScale: Double,
        decayedColor: (String, Double) -> Color
    ) -> (clusters: [[BodyBlobInfo]], solos: [BodyBlobInfo]) {
        let blobElements = elements.filter(shapeFilter)
        guard !blobElements.isEmpty else { return ([], []) }

        var infos = [BodyBlobInfo]()
        for e in blobElements {
            let c = center(e, size: size, t: t, ampScale: ampScale)
            let r = radius(e, size: size, t: t, ampScale: ampScale)
            let color = decayedColor(e.hexColor, decay)
            let c2: Color? = e.hexColor2.map { decayedColor($0, decay) }
            infos.append(BodyBlobInfo(element: e, center: c, radius: CGFloat(r), color: color, color2: c2, seed: e.shapeSeed ?? 0))
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

    // MARK: - Cluster Rendering

    static func drawCluster(
        _ cluster: [BodyBlobInfo],
        context: inout GraphicsContext,
        size: CGSize,
        t: Double,
        blendMode: GraphicsContext.BlendMode,
        spawnFactor: (CanvasElement, Double) -> Double,
        renderCache: RenderCache
    ) {
        var blobPaths = [(blob: BodyBlobInfo, path: Path, spawn: Double)]()
        for blob in cluster {
            let spawn = spawnFactor(blob.element, t)
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

        let clusterKey = Set(blobPaths.map(\.blob.element.id))
        let currentCenters = blobPaths.map(\.blob.center)
        let mergedPath: Path
        if let cached = renderCache.clusterCache[clusterKey] {
            let maxDrift = zip(cached.blobCenters, currentCenters).map { old, new in
                hypot(old.x - new.x, old.y - new.y)
            }.max() ?? .greatestFiniteMagnitude
            if maxDrift < 2.0 && cached.blobCenters.count == currentCenters.count {
                mergedPath = cached.mergedPath
            } else {
                var merged = blobPaths[0].path.cgPath
                for i in 1..<blobPaths.count {
                    merged = merged.union(blobPaths[i].path.cgPath)
                }
                mergedPath = Path(merged)
                renderCache.clusterCache[clusterKey] = .init(blobCenters: currentCenters, mergedPath: mergedPath)
            }
        } else {
            var merged = blobPaths[0].path.cgPath
            for i in 1..<blobPaths.count {
                merged = merged.union(blobPaths[i].path.cgPath)
            }
            mergedPath = Path(merged)
            renderCache.clusterCache[clusterKey] = .init(blobCenters: currentCenters, mergedPath: mergedPath)
        }

        context.drawLayer { ctx in
            ctx.blendMode = blendMode
            ctx.clip(to: mergedPath)

            for (blob, _, spawn) in blobPaths {
                let r = blob.radius
                let innerR = max(0, r - 40)
                let edgeLoc: Double = r > 0 ? Double(innerR / r) : 0

                let innerColor = blob.color
                let outerColor = blob.color2 ?? blob.color

                let gradCenter: CGPoint
                if blob.color2 != nil {
                    let offsetAngle = blob.element.phaseOffset * 2.7
                    let offsetR = r * 0.3
                    gradCenter = CGPoint(
                        x: blob.center.x + CGFloat(cos(offsetAngle)) * offsetR,
                        y: blob.center.y + CGFloat(sin(offsetAngle)) * offsetR
                    )
                } else {
                    gradCenter = blob.center
                }

                let midLoc: Double = edgeLoc + (1.0 - edgeLoc) * 0.5
                let s0: Gradient.Stop = .init(color: innerColor.opacity(0.18 * spawn), location: 0)
                let s1: Gradient.Stop = .init(color: innerColor.opacity(0.22 * spawn), location: edgeLoc)
                let s2: Gradient.Stop = .init(color: outerColor.opacity(0.50 * spawn), location: midLoc)
                let s3: Gradient.Stop = .init(color: outerColor.opacity(0.72 * spawn), location: 1.0)
                let rimGrad = Gradient(stops: [s0, s1, s2, s3])

                let ellipse = CGRect(x: blob.center.x - r, y: blob.center.y - r, width: r * 2, height: r * 2)
                ctx.fill(
                    Path(ellipseIn: ellipse),
                    with: .radialGradient(rimGrad, center: gradCenter, startRadius: 0, endRadius: r)
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
            let strokeColor = blob.color2 ?? blob.color
            context.drawLayer { ctx in
                ctx.clip(to: Path(ellipseIn: clipRect))
                ctx.stroke(
                    mergedPath,
                    with: .color(strokeColor.opacity(0.65 * spawn)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
