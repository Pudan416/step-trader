import SwiftUI

/// One palette tile: a canvas element drawn through the canvas renderers at
/// tile scale.
///
/// Going through the real renderers is the mechanism, not an optimisation. The
/// palette promises that the figure on the tile is the figure that will land on
/// the canvas, and a hand-drawn preview would break that promise the first time
/// a renderer changed.
struct HappeningShapeTile: View {
    /// Fixed for every tile. `CanvasElement.spawn` gives each shape type its own
    /// random size on the canvas; here they must all render at one scale or the
    /// grid looks ragged.
    ///
    /// 0.24 comes from rendering a sweep of 0.10 to 0.40 and looking at it. The
    /// renderers scale their radius by the canvas dimension, so the sizes
    /// `spawn` uses on a full screen — 0.14 to 0.34 — overflow a 100pt tile.
    static let previewSize: CGFloat = 0.24

    let element: CanvasElement
    let side: CGFloat

    @State private var renderCache = RenderCache()

    static func previewElement(
        optionId: String,
        label: String,
        shapeType: CanvasShapeType,
        colorHex: String,
        seed: UInt64
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            kind: shapeType == .rays ? .ray : .circle,
            optionId: optionId,
            label: label,
            hexColor: colorHex,
            hexColor2: nil,
            size: previewSize,
            basePosition: CGPoint(x: 0.5, y: 0.5),
            // A preview is a still frame: every animated term is zeroed so the
            // tile cannot drift away from the figure it is promising.
            phaseOffset: 0,
            driftSpeed: 0,
            driftAmplitude: 0,
            pulseFrequency: 0,
            pulseAmplitude: 0,
            rotationSpeed: 0,
            opacity: 1,
            createdAt: .now,
            shapeSeed: seed,
            frozenShapeType: shapeType
        )
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            draw(into: &context, size: size)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private func draw(into context: inout GraphicsContext, size: CGSize) {
        let color = Color(hex: element.hexColor)
        switch element.frozenShapeType ?? .circle {
        case .circle, .blob, .spirograph:
            CircleShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil
            )
        case .snowflake:
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, renderCache: renderCache,
                decayedColor: color, decayedColor2: nil
            )
        case .organicBlob:
            OrganicBlobShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil
            )
        case .rays:
            drawRaysPreservingCanvasAspect(into: &context, size: size)
        }
    }

    /// Rays are edge-anchored spotlight cones composed for a tall canvas, not a
    /// small square. Render them in the canvas aspect ratio and scale that down
    /// into the tile, the way the app icon does, so the cones stay recognisable
    /// instead of stretching into a smear.
    ///
    /// `RayShapeRenderer.draw` takes no colour — it resolves its own from the
    /// element and its seed, which is why the preview element carries both.
    private func drawRaysPreservingCanvasAspect(
        into context: inout GraphicsContext,
        size: CGSize
    ) {
        let canvasSize = GenerativeCanvasView.canonicalPortraitSize
        let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
        context.drawLayer { layer in
            layer.translateBy(
                x: (size.width - canvasSize.width * scale) / 2,
                y: (size.height - canvasSize.height * scale) / 2
            )
            layer.scaleBy(x: scale, y: scale)
            RayShapeRenderer.draw(
                element, context: &layer, size: canvasSize, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil
            )
        }
    }
}
