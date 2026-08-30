import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import EditorialFieldCore

public enum NeutralOverlay: String, CaseIterable, Codable, Hashable, Sendable {
    case crop
    case overlap
    case centerOfMass
    case occupiedBounds
}

public struct NeutralRenderConfiguration: Equatable, Sendable {
    public let scale: Int
    public let overlays: Set<NeutralOverlay>

    public init(scale: Int = 3, overlays: Set<NeutralOverlay> = []) {
        self.scale = scale
        self.overlays = overlays
    }
}

public struct PixelRect: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct NeutralRenderedImage: Sendable {
    public let pngData: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(pngData: Data, pixelWidth: Int, pixelHeight: Int) {
        self.pngData = pngData
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct NeutralActorEvidence: Codable, Equatable, Sendable {
    public let eventID: String
    public let label: String
    public let position: CompositionPoint
    public let diameter: Double
    public let diameterPixels: Double
    public let depth: Double
    public let luminance: Double
    public let localBlur: Double
    public let localBlurPixels: Double
    public let cropFraction: Double
    public let drawOrder: Int
    public let labelInkPixelCount: Int
}

public struct NeutralRenderedScene: Sendable {
    public let fullScreen: NeutralRenderedImage
    public let calendarTile: NeutralRenderedImage
    public let tileCrop: PixelRect
    public let debugOverlays: [NeutralOverlay: NeutralRenderedImage]
    public let actors: [NeutralActorEvidence]
    public let drawSequence: [String]
}

public enum NeutralRendererError: Error, LocalizedError {
    case invalidScale(Int)
    case unsupportedViewport(EditorialViewport)
    case cannotCreateBitmap(Int, Int)
    case cannotCreateImage
    case cannotEncodePNG

    public var errorDescription: String? {
        switch self {
        case .invalidScale(let scale): "Render scale must be positive, got \(scale)"
        case .unsupportedViewport(let viewport): "Neutral renderer requires phone recipe, got \(viewport.rawValue)"
        case .cannotCreateBitmap(let width, let height): "Cannot create \(width)x\(height) bitmap"
        case .cannotCreateImage: "Cannot create rendered image"
        case .cannotEncodePNG: "Cannot encode PNG"
        }
    }
}

public struct NeutralRenderer {
    public static let version = "neutral-coregraphics-v1"

    public init() {}

    public func render(
        recipe: CompositionRecipe,
        background: BackgroundCondition,
        configuration: NeutralRenderConfiguration = .init()
    ) throws -> NeutralRenderedScene {
        guard configuration.scale > 0 else { throw NeutralRendererError.invalidScale(configuration.scale) }
        guard recipe.viewport == .phone else { throw NeutralRendererError.unsupportedViewport(recipe.viewport) }

        let width = Int(recipe.viewport.width) * configuration.scale
        let height = Int(recipe.viewport.height) * configuration.scale
        let context = try makeContext(width: width, height: height)
        let backgroundLuminance = backgroundGray(background)
        context.setFillColor(gray: backgroundLuminance, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let ordered = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }
        let labels = Dictionary(uniqueKeysWithValues: recipe.actors.enumerated().map {
            ($0.element.eventID, String(format: "A%02d", $0.offset + 1))
        })

        for actor in ordered {
            try drawActor(actor, in: context, canvasWidth: width, canvasHeight: height)
        }
        for actor in ordered {
            drawLabel(
                labels[actor.eventID]!,
                actor: actor,
                in: context,
                canvasWidth: width,
                canvasHeight: height
            )
        }

        guard let fullImage = context.makeImage() else { throw NeutralRendererError.cannotCreateImage }
        let tileSide = width
        let tileCrop = PixelRect(
            x: 0,
            y: (height - tileSide) / 2,
            width: tileSide,
            height: tileSide
        )
        guard let tileImage = fullImage.cropping(to: CGRect(
            x: tileCrop.x,
            y: tileCrop.y,
            width: tileCrop.width,
            height: tileCrop.height
        )) else { throw NeutralRendererError.cannotCreateImage }

        let fullPNG = try pngData(fullImage)
        let tilePNG = try pngData(tileImage)
        var debug = [NeutralOverlay: NeutralRenderedImage]()
        for overlay in configuration.overlays.sorted(by: { $0.rawValue < $1.rawValue }) {
            let image = try overlayImage(
                overlay,
                base: fullImage,
                recipe: recipe,
                tileCrop: tileCrop,
                width: width,
                height: height
            )
            debug[overlay] = NeutralRenderedImage(
                pngData: try pngData(image),
                pixelWidth: width,
                pixelHeight: height
            )
        }

        let actorEvidence = recipe.actors.enumerated().map { index, actor in
            let label = labels[actor.eventID]!
            return NeutralActorEvidence(
                eventID: actor.eventID,
                label: label,
                position: actor.position,
                diameter: actor.diameter,
                diameterPixels: actor.diameter * Double(min(width, height)),
                depth: actor.depth,
                luminance: actorLuminance(actor.depth),
                localBlur: actor.localBlur,
                localBlurPixels: actor.localBlur * Double(min(width, height)),
                cropFraction: recipe.cropFraction(of: actor),
                drawOrder: actor.drawOrder,
                labelInkPixelCount: max(1, label.count * configuration.scale * 8)
            )
        }

        return NeutralRenderedScene(
            fullScreen: NeutralRenderedImage(pngData: fullPNG, pixelWidth: width, pixelHeight: height),
            calendarTile: NeutralRenderedImage(pngData: tilePNG, pixelWidth: tileSide, pixelHeight: tileSide),
            tileCrop: tileCrop,
            debugOverlays: debug,
            actors: actorEvidence,
            drawSequence: ordered.map(\.eventID)
        )
    }

    private func drawActor(
        _ actor: ActorCompositionRecipe,
        in canvas: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) throws {
        let shortSide = Double(min(canvasWidth, canvasHeight))
        let diameter = max(1, actor.diameter * shortSide)
        let blur = max(0, actor.localBlur * shortSide)
        let padding = ceil(blur * 3) + 3
        let layerSide = max(1, Int(ceil(diameter + padding * 2)))
        let layer = try makeContext(width: layerSide, height: layerSide)
        let circle = CGRect(
            x: padding,
            y: padding,
            width: diameter,
            height: diameter
        )
        layer.setFillColor(gray: actorLuminance(actor.depth), alpha: 0.90)
        layer.fillEllipse(in: circle)
        guard let unblurred = layer.makeImage() else { throw NeutralRendererError.cannotCreateImage }

        let actorImage: CGImage
        if blur >= 0.5 {
            let input = CIImage(cgImage: unblurred)
            let blurred = input
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
                .cropped(to: input.extent)
            let ciContext = CIContext(options: [.useSoftwareRenderer: true])
            guard let output = ciContext.createCGImage(blurred, from: input.extent) else {
                throw NeutralRendererError.cannotCreateImage
            }
            actorImage = output
        } else {
            actorImage = unblurred
        }

        let center = actorCenter(actor, width: canvasWidth, height: canvasHeight)
        canvas.draw(
            actorImage,
            in: CGRect(
                x: center.x - CGFloat(layerSide) * 0.5,
                y: center.y - CGFloat(layerSide) * 0.5,
                width: CGFloat(layerSide),
                height: CGFloat(layerSide)
            )
        )
    }

    private func drawLabel(
        _ label: String,
        actor: ActorCompositionRecipe,
        in context: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) {
        let center = actorCenter(actor, width: canvasWidth, height: canvasHeight)
        let shortSide = Double(min(canvasWidth, canvasHeight))
        let diameter = actor.diameter * shortSide
        let glyphHeight = min(64, max(18, diameter * 0.22))
        let glyphWidth = glyphHeight * 0.48
        let spacing = glyphWidth * 0.25
        let totalWidth = glyphWidth * 3 + spacing * 2
        let box = CGRect(
            x: center.x - totalWidth * 0.58,
            y: center.y - glyphHeight * 0.62,
            width: totalWidth * 1.16,
            height: glyphHeight * 1.24
        )
        let luminance = actorLuminance(actor.depth)
        context.setFillColor(gray: luminance > 0.5 ? 0.05 : 0.95, alpha: 0.72)
        context.fillEllipse(in: box)
        context.setStrokeColor(gray: luminance > 0.5 ? 0.98 : 0.02, alpha: 1)
        context.setLineWidth(max(1.5, glyphHeight * 0.085))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let originX = center.x - totalWidth * 0.5
        drawLetterA(in: context, rect: CGRect(x: originX, y: center.y - glyphHeight * 0.5, width: glyphWidth, height: glyphHeight))
        for (offset, digit) in label.dropFirst().enumerated() {
            let x = originX + Double(offset + 1) * (glyphWidth + spacing)
            drawDigit(digit, in: context, rect: CGRect(x: x, y: center.y - glyphHeight * 0.5, width: glyphWidth, height: glyphHeight))
        }
    }

    private func drawLetterA(in context: CGContext, rect: CGRect) {
        context.beginPath()
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.midY))
        context.strokePath()
    }

    private func drawDigit(_ digit: Character, in context: CGContext, rect: CGRect) {
        let segments: [Character: Set<Int>] = [
            "0": [0, 1, 2, 3, 4, 5],
            "1": [1, 2],
            "2": [0, 1, 6, 4, 3],
            "3": [0, 1, 6, 2, 3],
            "4": [5, 6, 1, 2],
            "5": [0, 5, 6, 2, 3],
            "6": [0, 5, 6, 4, 2, 3],
            "7": [0, 1, 2],
            "8": [0, 1, 2, 3, 4, 5, 6],
            "9": [0, 1, 2, 3, 5, 6],
        ]
        let selected = segments[digit] ?? []
        let p: [(CGPoint, CGPoint)] = [
            (.init(x: rect.minX, y: rect.maxY), .init(x: rect.maxX, y: rect.maxY)),
            (.init(x: rect.maxX, y: rect.maxY), .init(x: rect.maxX, y: rect.midY)),
            (.init(x: rect.maxX, y: rect.midY), .init(x: rect.maxX, y: rect.minY)),
            (.init(x: rect.minX, y: rect.minY), .init(x: rect.maxX, y: rect.minY)),
            (.init(x: rect.minX, y: rect.midY), .init(x: rect.minX, y: rect.minY)),
            (.init(x: rect.minX, y: rect.maxY), .init(x: rect.minX, y: rect.midY)),
            (.init(x: rect.minX, y: rect.midY), .init(x: rect.maxX, y: rect.midY)),
        ]
        context.beginPath()
        for index in selected.sorted() {
            context.move(to: p[index].0)
            context.addLine(to: p[index].1)
        }
        context.strokePath()
    }

    private func overlayImage(
        _ overlay: NeutralOverlay,
        base: CGImage,
        recipe: CompositionRecipe,
        tileCrop: PixelRect,
        width: Int,
        height: Int
    ) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = Double(min(width, height))
        context.setStrokeColor(gray: 1, alpha: 0.95)
        context.setFillColor(gray: 1, alpha: 0.22)
        context.setLineWidth(max(2, scale / 250))
        context.setLineDash(phase: 0, lengths: [scale / 80, scale / 120])

        switch overlay {
        case .crop:
            context.stroke(CGRect(
                x: tileCrop.x,
                y: tileCrop.y,
                width: tileCrop.width,
                height: tileCrop.height
            ))
        case .overlap:
            for leftIndex in recipe.actors.indices {
                for rightIndex in recipe.actors.indices where rightIndex > leftIndex {
                    let left = recipe.actors[leftIndex]
                    let right = recipe.actors[rightIndex]
                    guard CompositionGeometry.intersects(left, right, viewport: recipe.viewport) else { continue }
                    context.saveGState()
                    context.addEllipse(in: actorRect(left, width: width, height: height))
                    context.clip()
                    context.fillEllipse(in: actorRect(right, width: width, height: height))
                    context.restoreGState()
                }
            }
        case .centerOfMass:
            let weights = recipe.actors.map { $0.diameter * $0.diameter }
            let total = weights.reduce(0, +)
            if total > 0 {
                let x = zip(recipe.actors, weights).map { $0.position.x * $1 }.reduce(0, +) / total * Double(width)
                let y = (1 - zip(recipe.actors, weights).map { $0.position.y * $1 }.reduce(0, +) / total) * Double(height)
                let reach = scale * 0.04
                context.move(to: CGPoint(x: x - reach, y: y))
                context.addLine(to: CGPoint(x: x + reach, y: y))
                context.move(to: CGPoint(x: x, y: y - reach))
                context.addLine(to: CGPoint(x: x, y: y + reach))
                context.strokePath()
            }
        case .occupiedBounds:
            let bounds = recipe.actors.map { actorRect($0, width: width, height: height) }
                .reduce(CGRect.null) { $0.union($1) }
                .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            if !bounds.isNull { context.stroke(bounds) }
        }
        guard let image = context.makeImage() else { throw NeutralRendererError.cannotCreateImage }
        return image
    }

    private func actorCenter(_ actor: ActorCompositionRecipe, width: Int, height: Int) -> CGPoint {
        CGPoint(x: actor.position.x * Double(width), y: (1 - actor.position.y) * Double(height))
    }

    private func actorRect(_ actor: ActorCompositionRecipe, width: Int, height: Int) -> CGRect {
        let center = actorCenter(actor, width: width, height: height)
        let diameter = actor.diameter * Double(min(width, height))
        return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    private func actorLuminance(_ depth: Double) -> Double {
        0.22 + min(max(depth, 0), 1) * 0.58
    }

    private func backgroundGray(_ condition: BackgroundCondition) -> Double {
        switch condition {
        case .light: 0.91
        case .dark: 0.09
        case .warm: 0.76
        case .cool: 0.29
        case .saturated: 0.16
        case .lowContrast: 0.53
        }
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NeutralRendererError.cannotCreateBitmap(width, height) }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        return context
    }

    private func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw NeutralRendererError.cannotEncodePNG }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw NeutralRendererError.cannotEncodePNG }
        return data as Data
    }
}
