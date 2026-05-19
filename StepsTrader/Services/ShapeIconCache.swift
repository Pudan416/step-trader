import SwiftUI

/// Pre-renders shape type icons showing 3 elements (body, mind, heart)
/// composed together in brand yellow. Cached after first render.
@MainActor
final class ShapeIconCache {

    static let shared = ShapeIconCache()

    private var cache: [CacheKey: UIImage] = [:]

    private struct CacheKey: Hashable {
        let shape: CanvasShapeType
        let size: CGFloat
        let scale: CGFloat
    }

    // Brand accent: #FFD369
    private let brandYellow = UIColor(red: 0xFF / 255, green: 0xD3 / 255, blue: 0x69 / 255, alpha: 1.0)

    // 3 element placements (normalized to icon rect): body, mind, heart
    private let placements: [(cx: CGFloat, cy: CGFloat, sizeFactor: CGFloat)] = [
        (0.38, 0.42, 0.52),   // body — larger, center-left
        (0.68, 0.30, 0.38),   // mind — medium, upper-right
        (0.55, 0.72, 0.34),   // heart — smaller, lower-center
    ]

    private let seeds: [UInt64] = [31337, 7919, 6271]

    func icon(for shape: CanvasShapeType, size: CGFloat = 68, scale: CGFloat? = nil) -> UIImage {
        let resolvedScale = scale ?? UIScreen.main.scale
        let key = CacheKey(shape: shape, size: size, scale: resolvedScale)
        if let cached = cache[key] { return cached }
        let image = render(shape: shape, size: size, scale: resolvedScale)
        cache[key] = image
        return image
    }

    private func render(shape: CanvasShapeType, size: CGFloat, scale: CGFloat) -> UIImage {
        let pixelSize = size * scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pixelSize, height: pixelSize))

        let image = renderer.image { uiCtx in
            let cgCtx = uiCtx.cgContext
            let fullRect = CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
            let rect = fullRect.insetBy(dx: pixelSize * 0.04, dy: pixelSize * 0.04)

            cgCtx.setFillColor(UIColor.clear.cgColor)
            cgCtx.fill(fullRect)

            for (i, placement) in placements.enumerated() {
                let cx = rect.minX + placement.cx * rect.width
                let cy = rect.minY + placement.cy * rect.height
                let r = min(rect.width, rect.height) * placement.sizeFactor * 0.5
                let elementRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                let seed = seeds[i]
                let alpha: CGFloat = 0.85 - CGFloat(i) * 0.1

                drawElement(shape: shape, in: elementRect, seed: seed, alpha: alpha, ctx: cgCtx)
            }
        }

        return UIImage(cgImage: image.cgImage!, scale: scale, orientation: .up)
    }

    // MARK: - Per-shape rendering

    private func drawElement(shape: CanvasShapeType, in rect: CGRect, seed: UInt64, alpha: CGFloat, ctx: CGContext) {
        switch shape {
        case .circle:
            drawCircle(in: rect, alpha: alpha, ctx: ctx)
        case .snowflake:
            drawSnowflake(in: rect, seed: seed, alpha: alpha, ctx: ctx)
        case .rays:
            drawRays(in: rect, seed: seed, alpha: alpha, ctx: ctx)
        case .organicBlob:
            drawOrganicBlob(in: rect, seed: seed, alpha: alpha, ctx: ctx)
        case .blob:
            drawBlob(in: rect, seed: seed, alpha: alpha, ctx: ctx)
        case .spirograph:
            drawCircle(in: rect, alpha: alpha, ctx: ctx)
        }
    }

    // MARK: - Circle (radial gradient orb)

    private func drawCircle(in rect: CGRect, alpha: CGFloat, ctx: CGContext) {
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) * 0.48

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            brandYellow.withAlphaComponent(alpha).cgColor,
            brandYellow.withAlphaComponent(alpha * 0.35).cgColor,
            brandYellow.withAlphaComponent(0).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.5, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
            ctx.restoreGState()
        }
    }

    // MARK: - Snowflake (rectMorph outline + fill)

    private func drawSnowflake(in rect: CGRect, seed: UInt64, alpha: CGFloat, ctx: CGContext) {
        let frame = ProceduralShapeGenerator.rectMorphFrame(seed: seed, time: 0, in: rect)
        let path = frame.path.cgPath

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(brandYellow.withAlphaComponent(alpha * 0.3).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(brandYellow.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(max(1.0, rect.width * 0.02))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Rays

    private func drawRays(in rect: CGRect, seed: UInt64, alpha: CGFloat, ctx: CGContext) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let reach = min(rect.width, rect.height) * 0.45
        let rays = ProceduralShapeGenerator.heartRays(
            seed: seed, complexity: 0.4, time: 0,
            origin: center,
            direction: CGPoint(x: 0, y: -1),
            reach: reach
        )

        for ray in rays {
            ctx.saveGState()
            ctx.addPath(ray.path.cgPath)
            ctx.setFillColor(brandYellow.withAlphaComponent(alpha * 0.7).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: - Organic Blob

    private func drawOrganicBlob(in rect: CGRect, seed: UInt64, alpha: CGFloat, ctx: CGContext) {
        let path = ProceduralShapeGenerator.organicBlobPath(
            seed: seed, complexity: 0.5, symmetry: 1, time: 0, in: rect
        )

        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) * 0.5

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            brandYellow.withAlphaComponent(alpha * 0.8).cgColor,
            brandYellow.withAlphaComponent(alpha * 0.3).cgColor,
            brandYellow.withAlphaComponent(0).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.5, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.setStrokeColor(brandYellow.withAlphaComponent(alpha * 0.5).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Blob (legacy body shape)

    private func drawBlob(in rect: CGRect, seed: UInt64, alpha: CGFloat, ctx: CGContext) {
        let path = ProceduralShapeGenerator.bodyPath(
            seed: seed, complexity: 0.5, time: 0, in: rect
        )

        ctx.saveGState()
        ctx.addPath(path.cgPath)
        ctx.setFillColor(brandYellow.withAlphaComponent(alpha).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
}
