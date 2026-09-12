import SwiftUI

/// A paused, silent example. Never attaches gesture handlers or a sound bus.
struct SettingsAppearancePreview: View {
    let draft: SettingsAppearanceDraft
    var styleOverride: CanvasVisualStyle? = nil
    var thumbnail = false

    private var style: CanvasVisualStyle {
        styleOverride ?? CanvasVisualStyle(rawValue: draft.canvasStyle) ?? .editorial
    }

    var body: some View {
        Group {
            if style == .editorial {
                DayObjectsView(
                    sceneInput: DayObjectSceneInput(
                        dayKey: "settings-preview", identity: "settings-preview",
                        eventIDs: ["walk", "rest", "create", "connect", "read"],
                        motionEnergy: 0.7, visualClarity: 0.8,
                        canvasCoverage: .fullCanvas,
                        paletteCategories: ModernPaletteSelection.decode(draft.categories),
                        usesEditorialField: true
                    ),
                    isAnimating: false
                )
            } else {
                ZStack {
                    Canvas { context, size in
                        let palette = EnergyGradientRenderer.palette(for: GradientPalette.normalized(rawValue: draft.palette))
                        EnergyGradientRenderer.draw(
                            context: &context, size: size,
                            opacities: EnergyGradientRenderer.computeOpacities(
                                smoothedS: 0.8, smoothedL: 0.6,
                                hasStepsData: true, hasSleepData: true
                            ),
                            baseColor: palette.dark,
                            gradientStyle: GradientStyle(rawValue: draft.style) ?? .radial,
                            colorPalette: palette
                        )
                    }
                    SettingsLegacyHappeningsPreview(shapes: draft.shapes, fills: draft.fills)
                    GeometryReader { geometry in
                        let texture = CanvasTexture.fromStored(draft.texture)
                        if let asset = texture.assetName {
                            Image(decorative: asset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .blendMode(texture.blendMode)
                                .opacity(texture.defaultOpacity)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Uses the same frozen shape renderers and TextureSpec path as the live Canvas,
/// with fixed identities and positions so changing a draft never rerolls the sample.
private struct SettingsLegacyHappeningsPreview: View {
    let shapes: Set<CanvasShapeType>
    let fills: Set<TextureKind>
    @State private var renderCache = RenderCache()

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            let selectedShapes = CanvasShapeType.selectableCases.filter(shapes.contains)
            let selectedFills = TextureKind.allCases.filter(fills.contains)
            if !selectedShapes.isEmpty, !selectedFills.isEmpty {
                let count = max(selectedShapes.count, selectedFills.count)
                let positions: [CGPoint] = [
                    CGPoint(x: 0.22, y: 0.32), CGPoint(x: 0.52, y: 0.28),
                    CGPoint(x: 0.80, y: 0.38), CGPoint(x: 0.35, y: 0.75),
                    CGPoint(x: 0.68, y: 0.73)
                ]
                let side = min(size.width * 0.38, size.height * 0.72)
                for index in 0..<count {
                    let shape = selectedShapes[index % selectedShapes.count]
                    let fill = selectedFills[index % selectedFills.count]
                    let position = positions[index % positions.count]
                    let element = sampleElement(shape: shape, index: index)
                    let spec = TextureSpec(kind: fill, density: 0.5, uniformity: 1, angle: .pi / 4)
                    context.drawLayer { layer in
                        layer.translateBy(
                            x: position.x * size.width - side / 2,
                            y: position.y * size.height - side / 2
                        )
                        draw(element, spec: spec, context: &layer, size: CGSize(width: side, height: side))
                    }
                }
            }
        }
    }

    private func sampleElement(shape: CanvasShapeType, index: Int) -> CanvasElement {
        let colors = ["#FFBF65", "#A6CBD4", "#FD8973", "#C4B5FD", "#DDE6C5"]
        let seed = UInt64(41 + index * 17)
        return CanvasElement(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
            kind: shape == .rays ? .ray : .circle,
            optionId: "settings-preview-\(index)", label: nil,
            hexColor: colors[index % colors.count], hexColor2: nil,
            size: HappeningShapeTile.previewSize(for: shape, seed: seed),
            basePosition: CGPoint(x: 0.5, y: 0.5),
            phaseOffset: 0, driftSpeed: 0, driftAmplitude: 0,
            pulseFrequency: 0, pulseAmplitude: 0, rotationSpeed: 0,
            opacity: 1, createdAt: Date(timeIntervalSinceReferenceDate: 0),
            userRotation: Double(index) * 0.35,
            shapeSeed: seed, frozenShapeType: shape
        )
    }

    private func draw(
        _ element: CanvasElement, spec: TextureSpec,
        context: inout GraphicsContext, size: CGSize
    ) {
        let color = Color(hex: element.hexColor)
        switch element.frozenShapeType ?? .circle {
        case .circle, .blob, .spirograph:
            CircleShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil, spec: spec, cache: renderCache
            )
        case .snowflake:
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, renderCache: renderCache,
                decayedColor: color, decayedColor2: nil, spec: spec
            )
        case .organicBlob:
            OrganicBlobShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 0,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil, spec: spec, cache: renderCache
            )
        case .rays:
            // Spotlight cones are authored for the portrait Canvas. Preserve that
            // aspect ratio, just as HappeningShapeTile does for its palette sample.
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
                    blendMode: .normal, ampScale: 0, interaction: nil, spec: spec
                )
            }
        }
    }
}
