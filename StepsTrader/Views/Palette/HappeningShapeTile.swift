import SwiftUI

/// One palette tile: a canvas element drawn through the canvas renderers at
/// tile scale.
///
/// Going through the real renderers is the mechanism, not an optimisation. The
/// palette promises that the figure on the tile is the figure that will land on
/// the canvas, and a hand-drawn preview would break that promise the first time
/// a renderer changed.
struct HappeningShapeTile: View {
    /// Palette assignments promise the shape, silhouette, colour and rotation.
    /// Texture belongs to the day composition and is only known once the item
    /// is inserted at a concrete canvas rank, so previews use the neutral
    /// gradient path shared by every closed-shape renderer.
    static let previewTextureSpec = TextureSpec(
        kind: .gradient,
        density: 0.5,
        uniformity: 1,
        angle: 0
    )

    /// Per shape type, because one number does not work for all four.
    ///
    /// The renderers read `size` as a fraction of the canvas dimension but each
    /// interprets it differently — `spawn` already compensates with a different
    /// random range per type. At a single 0.24 the circle filled its tile while
    /// the blob washed out and the cones were a speck. These are calibrated by
    /// rendering them and looking.
    ///
    /// Rays need by far the most because they are drawn into a box holding the
    /// canvas aspect ratio and then scaled to fit the square, which throws away
    /// better than half the scale.
    static func previewSize(for shapeType: CanvasShapeType) -> CGFloat {
        switch shapeType {
        case .circle, .blob, .spirograph: 0.24
        case .snowflake:                  0.34
        // The blob's contour reaches well past its nominal radius, so it
        // clips into a square block sooner than the others.
        case .organicBlob:                0.24
        // Not larger: past roughly 0.45 the cone runs past the tile's canvas
        // and is clipped into a hard-edged block rather than reading as light.
        case .rays:                       0.42
        }
    }

    let element: CanvasElement
    let side: CGFloat

    @State private var renderCache = RenderCache()

    static func previewElement(
        optionId: String,
        label: String,
        shapeType: CanvasShapeType,
        colorHex: String,
        seed: UInt64,
        rotation: Double = 0
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            kind: shapeType == .rays ? .ray : .circle,
            optionId: optionId,
            label: label,
            hexColor: colorHex,
            hexColor2: nil,
            size: previewSize(for: shapeType),
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
            // Rays take their cone direction from the vector to the canvas
            // centre, and a tile puts the element exactly there — so without an
            // explicit rotation every rays tile points the same way and the
            // seed changes nothing visible.
            userRotation: rotation,
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
                decayedColor: color, decayedColor2: nil,
                spec: Self.previewTextureSpec,
                cache: renderCache
            )
        case .snowflake:
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, renderCache: renderCache,
                decayedColor: color, decayedColor2: nil,
                spec: Self.previewTextureSpec
            )
        case .organicBlob:
            OrganicBlobShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil,
                spec: Self.previewTextureSpec,
                cache: renderCache
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
