import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import EditorialFieldCore

public struct MaterialRenderConfiguration: Equatable, Sendable {
    public let scale: Int

    public init(scale: Int = 3) {
        self.scale = scale
    }
}

public struct MaterialRenderedScene: Sendable {
    public let fullScreen: NeutralRenderedImage
    public let calendarTile: NeutralRenderedImage
    public let tileCrop: PixelRect
    public let drawSequence: [String]
}

public enum MaterialRendererError: Error, LocalizedError {
    case invalidPixelSize(Int)
    case invalidScale(Int)
    case unsupportedViewport(EditorialViewport)
    case missingActorMaterial(String)
    case incoherentDailyFamily
    case invalidMaterial(String)
    case cannotCreateBitmap(Int, Int)
    case cannotCreateImage
    case cannotEncodePNG

    public var errorDescription: String? {
        switch self {
        case .invalidPixelSize(let size): "Material actor size must be positive, got \(size)"
        case .invalidScale(let scale): "Material render scale must be positive, got \(scale)"
        case .unsupportedViewport(let viewport): "Material renderer requires phone recipe, got \(viewport.rawValue)"
        case .missingActorMaterial(let eventID): "Missing material for actor \(eventID)"
        case .incoherentDailyFamily: "Every actor must use the daily material family and compatible accent"
        case .invalidMaterial(let detail): "Invalid material recipe: \(detail)"
        case .cannotCreateBitmap(let width, let height): "Cannot create \(width)x\(height) material bitmap"
        case .cannotCreateImage: "Cannot create rendered material image"
        case .cannotEncodePNG: "Cannot encode material PNG"
        }
    }
}

/// Software CoreGraphics reference renderer for the bounded radial material
/// recipe. It is intentionally independent from app/Metal code and consumes
/// immutable composition values without deriving or changing geometry.
public struct MaterialRenderer {
    public static let version = "material-coregraphics-radial-v7"

    public init() {}

    public func renderActor(
        _ material: ActorMaterialRecipe,
        pixelSize: Int,
        background: BackgroundCondition? = nil
    ) throws -> NeutralRenderedImage {
        guard pixelSize > 0 else { throw MaterialRendererError.invalidPixelSize(pixelSize) }
        try validate(material)
        let backgroundColor = background.map(Self.backgroundColor(for:))
        let actorImage = try makeActorImage(
            material,
            pixelSize: pixelSize,
            contrastBackground: backgroundColor
        )
        let finalImage: CGImage
        if let backgroundColor {
            let context = try makeContext(width: pixelSize, height: pixelSize)
            context.setFillColor(
                red: backgroundColor.red,
                green: backgroundColor.green,
                blue: backgroundColor.blue,
                alpha: 1
            )
            context.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
            context.draw(actorImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
            guard let image = context.makeImage() else { throw MaterialRendererError.cannotCreateImage }
            finalImage = image
        } else {
            finalImage = actorImage
        }
        return NeutralRenderedImage(
            pngData: try pngData(finalImage),
            pixelWidth: pixelSize,
            pixelHeight: pixelSize
        )
    }

    /// Transparent structural masks rendered through the same actor-local
    /// Gaussian blur and open-center restoration as a composed scene. Outline
    /// contours are returned separately so evidence can measure each alpha
    /// band without allowing palette chroma to impersonate topology.
    public func renderStructuralAlphaLayers(
        _ material: ActorMaterialRecipe,
        pixelSize: Int,
        blurRadius: Double
    ) throws -> [NeutralRenderedImage] {
        guard pixelSize > 0 else { throw MaterialRendererError.invalidPixelSize(pixelSize) }
        guard blurRadius.isFinite, blurRadius >= 0 else {
            throw MaterialRendererError.invalidMaterial("blur radius must be finite and nonnegative")
        }
        try validate(material)
        let selectors: [Int?]
        switch material.family {
        case .outline:
            selectors = material.organicTopology?.contours.indices.map(Optional.some) ?? []
        case .halo, .counterform:
            selectors = [nil]
        default:
            throw MaterialRendererError.invalidMaterial(
                "alpha topology layers require halo, outline, or counterform"
            )
        }
        return try selectors.map { contourIndex in
            var image = try makeActorImage(
                material,
                pixelSize: pixelSize,
                contrastBackground: nil,
                isolatedContourIndex: contourIndex
            )
            if blurRadius >= 0.5 {
                image = try padded(image, by: max(2, Int(ceil(blurRadius * 3))))
                image = try blurred(image, radius: blurRadius)
                image = try restoringOpenCenter(
                    image,
                    material: material,
                    sourceDiameter: pixelSize,
                    blurRadius: blurRadius
                )
            }
            return NeutralRenderedImage(
                pngData: try pngData(image),
                pixelWidth: image.width,
                pixelHeight: image.height
            )
        }
    }

    public func render(
        recipe: CompositionRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        configuration: MaterialRenderConfiguration = .init()
    ) throws -> MaterialRenderedScene {
        guard configuration.scale > 0 else {
            throw MaterialRendererError.invalidScale(configuration.scale)
        }
        guard recipe.viewport == .phone else {
            throw MaterialRendererError.unsupportedViewport(recipe.viewport)
        }
        guard material.actors.allSatisfy({ actor in
            actor.family == material.family
                && (actor.mutation == nil || actor.mutation == material.accentMutation)
                && (actor.mutation?.isCompatible(with: material.family) ?? true)
        }) else {
            throw MaterialRendererError.incoherentDailyFamily
        }

        let width = Int(recipe.viewport.width) * configuration.scale
        let height = Int(recipe.viewport.height) * configuration.scale
        let context = try makeContext(width: width, height: height)
        let backgroundColor = Self.backgroundColor(for: background)
        context.setFillColor(
            red: backgroundColor.red,
            green: backgroundColor.green,
            blue: backgroundColor.blue,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let ordered = recipe.actors.sorted {
            if $0.drawOrder != $1.drawOrder { return $0.drawOrder < $1.drawOrder }
            if $0.depth != $1.depth { return $0.depth < $1.depth }
            if $0.diameter != $1.diameter { return $0.diameter < $1.diameter }
            return $0.eventID < $1.eventID
        }
        let shortSide = Double(min(width, height))
        for actor in ordered {
            guard let actorMaterial = material.actor(actor.eventID) else {
                throw MaterialRendererError.missingActorMaterial(actor.eventID)
            }
            try validate(actorMaterial)
            let diameter = max(1, Int(ceil(actor.diameter * shortSide)))
            var actorImage = try makeActorImage(
                actorMaterial,
                pixelSize: diameter,
                contrastBackground: backgroundColor
            )
            let blur = max(0, actor.localBlur * shortSide)
            if blur >= 0.5 {
                actorImage = try padded(
                    actorImage,
                    by: max(2, Int(ceil(blur * 3)))
                )
                actorImage = try blurred(actorImage, radius: blur)
                actorImage = try restoringOpenCenter(
                    actorImage,
                    material: actorMaterial,
                    sourceDiameter: diameter,
                    blurRadius: blur
                )
            }
            let center = CGPoint(
                x: actor.position.x * Double(width),
                y: (1 - actor.position.y) * Double(height)
            )
            let layerWidth = Double(actorImage.width)
            let layerHeight = Double(actorImage.height)
            context.draw(actorImage, in: CGRect(
                x: center.x - layerWidth * 0.5,
                y: center.y - layerHeight * 0.5,
                width: layerWidth,
                height: layerHeight
            ))
        }

        guard let fullImage = context.makeImage() else { throw MaterialRendererError.cannotCreateImage }
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
        )) else { throw MaterialRendererError.cannotCreateImage }

        return MaterialRenderedScene(
            fullScreen: NeutralRenderedImage(
                pngData: try pngData(fullImage),
                pixelWidth: width,
                pixelHeight: height
            ),
            calendarTile: NeutralRenderedImage(
                pngData: try pngData(tileImage),
                pixelWidth: tileSide,
                pixelHeight: tileSide
            ),
            tileCrop: tileCrop,
            drawSequence: ordered.map(\.eventID)
        )
    }

    public static func backgroundColor(for condition: BackgroundCondition) -> MaterialColor {
        switch condition {
        case .light: MaterialColor(red: 0.94, green: 0.92, blue: 0.88)
        case .dark: MaterialColor(red: 0.045, green: 0.060, blue: 0.105)
        case .warm: MaterialColor(red: 0.48, green: 0.15, blue: 0.085)
        case .cool: MaterialColor(red: 0.055, green: 0.20, blue: 0.38)
        case .saturated: MaterialColor(red: 0.21, green: 0.045, blue: 0.29)
        case .lowContrast: MaterialColor(red: 0.49, green: 0.50, blue: 0.47)
        }
    }

    private func validate(_ material: ActorMaterialRecipe) throws {
        guard (1...3).contains(material.colors.count) else {
            throw MaterialRendererError.invalidMaterial("colors must contain one to three entries")
        }
        guard material.fields.count <= 3 else {
            throw MaterialRendererError.invalidMaterial("more than three radial fields")
        }
        guard material.fields.allSatisfy({ (0..<material.colors.count).contains($0.colorIndex) }) else {
            throw MaterialRendererError.invalidMaterial("field color index is out of range")
        }
        guard material.mutation?.isCompatible(with: material.family) ?? true else {
            throw MaterialRendererError.invalidMaterial("accent is unrelated to family")
        }
        if material.family == .solid,
           material.colors.count != 1 || !material.fields.isEmpty {
            throw MaterialRendererError.invalidMaterial("solid must have one color and zero fields")
        }
        if material.family == .outline,
           material.contourCount < 1 || material.contourWidth <= 0 {
            throw MaterialRendererError.invalidMaterial("outline requires a visible contour")
        }
        if material.family == .counterform,
           (material.counterformRadius ?? 0) <= 0 {
            throw MaterialRendererError.invalidMaterial("counterform requires a cut center")
        }
        switch material.family {
        case .halo, .counterform:
            guard let topology = material.organicTopology,
                  topology.contours.isEmpty,
                  validTopologyPoint(topology.outerCenter),
                  validTopologyPoint(topology.innerCenter),
                  validRadius(topology.outerRadius),
                  validRadius(topology.innerRadius),
                  topology.innerRadius < topology.outerRadius
            else {
                throw MaterialRendererError.invalidMaterial(
                    "halo/counterform requires one bounded radial body and no contour array"
                )
            }
        case .outline:
            guard let topology = material.organicTopology,
                  (1...3).contains(material.contourCount),
                  topology.contours.count == material.contourCount,
                  let first = topology.contours.first,
                  let last = topology.contours.last,
                  topology.outerCenter == first.outerCenter,
                  topology.outerRadius == first.outerRadius,
                  topology.innerCenter == last.innerCenter,
                  topology.innerRadius == last.innerRadius,
                  topology.contours.allSatisfy(validContour),
                  zip(topology.contours, topology.contours.dropFirst()).allSatisfy({ pair in
                      pair.0.outerRadius > pair.1.outerRadius
                          && pair.0.innerRadius > pair.1.innerRadius
                  })
            else {
                throw MaterialRendererError.invalidMaterial(
                    "outline contour array is the bounded authoritative topology"
                )
            }
        default:
            guard material.organicTopology == nil else {
                throw MaterialRendererError.invalidMaterial(
                    "non-structural family cannot carry organic topology"
                )
            }
        }
    }

    private func validTopologyPoint(_ point: CompositionPoint) -> Bool {
        point.x.isFinite
            && point.y.isFinite
            && (0.28...0.72).contains(point.x)
            && (0.28...0.72).contains(point.y)
    }

    private func validRadius(_ radius: Double) -> Bool {
        radius.isFinite && (0.02...0.50).contains(radius)
    }

    private func validContour(_ contour: OrganicRadialContour) -> Bool {
        validTopologyPoint(contour.outerCenter)
            && validTopologyPoint(contour.innerCenter)
            && validRadius(contour.outerRadius)
            && validRadius(contour.innerRadius)
            && contour.innerRadius < contour.outerRadius
            && contour.opacity.isFinite
            && contour.opacity > 0
            && contour.opacity <= 1
    }

    private func makeActorImage(
        _ material: ActorMaterialRecipe,
        pixelSize: Int,
        contrastBackground: MaterialColor?,
        isolatedContourIndex: Int? = nil
    ) throws -> CGImage {
        let context = try makeContext(width: pixelSize, height: pixelSize)
        guard let rawData = context.data else {
            throw MaterialRendererError.cannotCreateBitmap(pixelSize, pixelSize)
        }
        let bytes = rawData.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        let antialias = max(1 / Double(pixelSize), 0.0025)
        let outerRadius = 0.48

        for y in 0..<pixelSize {
            let v = (Double(y) + 0.5) / Double(pixelSize)
            for x in 0..<pixelSize {
                let u = (Double(x) + 0.5) / Double(pixelSize)
                let shapeDistance = hypot(u - 0.5, v - 0.5)
                let edgeWidth = max(material.edgeSoftness, antialias)
                var alpha = 1 - smoothstep(
                    outerRadius - edgeWidth,
                    outerRadius,
                    shapeDistance
                )
                var color = fieldColor(material: material, u: u, v: v)

                switch material.family {
                case .solid, .gradient:
                    break
                case .sphere:
                    let highlight = radialWeight(
                        u: u,
                        v: v,
                        focusX: 0.32,
                        focusY: 0.36,
                        radius: 0.30,
                        softness: 0.72
                    )
                    let bodyDepth = sqrt(clamp(1 - shapeDistance / outerRadius))
                    color = color.scaled(0.70 + bodyDepth * 0.30)
                    color = mix(color, RGB.white, 0.30 * highlight)
                case .glass:
                    let surfaceTension = 1 - smoothstep(
                        0.012,
                        0.050,
                        abs(shapeDistance - outerRadius * 0.90)
                    )
                    let refractedBand = 1 - smoothstep(
                        0.018,
                        0.060,
                        abs(shapeDistance - outerRadius * 0.76)
                    )
                    let highlight = radialWeight(
                        u: u,
                        v: v,
                        focusX: 0.31,
                        focusY: 0.34,
                        radius: 0.25,
                        softness: 0.76
                    )
                    color = mix(
                        color,
                        RGB(material.colors.last ?? material.colors[0]),
                        refractedBand * 0.24
                    )
                    color = mix(
                        color,
                        RGB.white,
                        min(0.42, surfaceTension * 0.32 + highlight * 0.14)
                    )
                    alpha *= 0.90 + surfaceTension * 0.10
                case .mist:
                    let radialVolumes = material.fields.map { field in
                        radialWeight(
                            u: u,
                            v: v,
                            focusX: field.focus.x,
                            focusY: field.focus.y,
                            radius: field.radius,
                            softness: field.softness
                        ) * clamp(field.opacity)
                    }
                    let peakVolume = radialVolumes.max() ?? 1
                    let sharedVolume = radialVolumes.reduce(0, +)
                        / Double(max(radialVolumes.count, 1))
                    // Mist is translucent depth made only from the same broad,
                    // overlapping radial fields as its color surface. There is
                    // intentionally no actor-seeded texture or 2D noise here.
                    let volume = clamp(peakVolume * 0.58 + sharedVolume * 0.42)
                    color = mix(color, RGB.white, 0.025 + (1 - volume) * 0.035)
                    alpha *= 0.58 + volume * 0.42
                case .halo:
                    guard let topology = material.organicTopology else {
                        throw MaterialRendererError.invalidMaterial("halo topology was not validated")
                    }
                    let outerCenter = topology.outerCenter
                    let innerCenter = topology.innerCenter
                    let organicOuterRadius = topology.outerRadius
                    let organicInnerRadius = topology.innerRadius
                    let outerDistance = hypot(u - outerCenter.x, v - outerCenter.y)
                    let innerDistance = hypot(u - innerCenter.x, v - innerCenter.y)
                    let body = 1 - smoothstep(
                        organicOuterRadius - edgeWidth,
                        organicOuterRadius,
                        outerDistance
                    )
                    let opening = smoothstep(
                        organicInnerRadius - edgeWidth * 1.6,
                        organicInnerRadius + edgeWidth * 1.4,
                        innerDistance
                    )
                    let atmosphericEdge = 1 - smoothstep(
                        edgeWidth * 0.7,
                        edgeWidth * 3.4,
                        abs(innerDistance - organicInnerRadius)
                    )
                    alpha = min(alpha, body) * opening * (0.76 + atmosphericEdge * 0.24)
                    color = mix(color, RGB.white, atmosphericEdge * 0.09)
                case .luminous:
                    let core = radialWeight(
                        u: u,
                        v: v,
                        focusX: 0.43,
                        focusY: 0.55,
                        radius: 0.24,
                        softness: 0.72
                    )
                    let innerGlow = radialWeight(
                        u: u,
                        v: v,
                        focusX: 0.43,
                        focusY: 0.55,
                        radius: 0.43,
                        softness: 0.82
                    )
                    let outerCorona = 1 - smoothstep(
                        0.018,
                        0.075,
                        abs(shapeDistance - outerRadius * 0.86)
                    )
                    color = mix(
                        color,
                        RGB.white,
                        min(0.62, core * 0.38 + innerGlow * 0.10 + outerCorona * 0.46)
                    )
                    alpha *= 0.92 + core * 0.05 + outerCorona * 0.03
                case .outline:
                    var contourAlpha = 0.0
                    guard let topology = material.organicTopology else {
                        throw MaterialRendererError.invalidMaterial("outline topology was not validated")
                    }
                    let contours: ArraySlice<OrganicRadialContour>
                    if let isolatedContourIndex {
                        guard topology.contours.indices.contains(isolatedContourIndex) else {
                            throw MaterialRendererError.invalidMaterial("outline contour index is invalid")
                        }
                        contours = topology.contours[isolatedContourIndex...isolatedContourIndex]
                    } else {
                        contours = topology.contours[...]
                    }
                    for contour in contours {
                        let outerDistance = hypot(
                            u - contour.outerCenter.x,
                            v - contour.outerCenter.y
                        )
                        let innerDistance = hypot(
                            u - contour.innerCenter.x,
                            v - contour.innerCenter.y
                        )
                        let outerFill = 1 - smoothstep(
                            contour.outerRadius - antialias * 1.8,
                            contour.outerRadius + antialias * 1.2,
                            outerDistance
                        )
                        let innerCut = smoothstep(
                            contour.innerRadius - antialias * 1.4,
                            contour.innerRadius + antialias * 1.8,
                            innerDistance
                        )
                        contourAlpha = max(
                            contourAlpha,
                            outerFill * innerCut * contour.opacity
                        )
                    }
                    alpha *= contourAlpha
                case .counterform:
                    guard let topology = material.organicTopology else {
                        throw MaterialRendererError.invalidMaterial(
                            "counterform topology was not validated"
                        )
                    }
                    let innerCenter = topology.innerCenter
                    let holeRadius = topology.innerRadius
                    let holeSoftness = max(material.counterformSoftness, antialias)
                    let innerDistance = hypot(u - innerCenter.x, v - innerCenter.y)
                    let cutout = smoothstep(
                        holeRadius - holeSoftness,
                        holeRadius + holeSoftness,
                        innerDistance
                    )
                    let corona = 1 - smoothstep(
                        holeSoftness,
                        holeSoftness * 3.2,
                        abs(innerDistance - holeRadius)
                    )
                    alpha *= cutout
                    color = mix(color, RGB.white, corona * 0.24)
                }

                alpha = clamp(alpha * material.baseOpacity)
                if let contrastBackground, alpha > 0.001 {
                    color = visibilityAdjusted(
                        color,
                        alpha: alpha,
                        background: RGB(contrastBackground),
                        family: material.family
                    )
                }
                write(
                    color: color,
                    alpha: alpha,
                    at: y * bytesPerRow + x * 4,
                    into: bytes
                )
            }
        }
        guard let image = context.makeImage() else { throw MaterialRendererError.cannotCreateImage }
        return image
    }

    private func fieldColor(material: ActorMaterialRecipe, u: Double, v: Double) -> RGB {
        var result = RGB(material.colors[0])
        for field in material.fields {
            let fieldColor = RGB(material.colors[field.colorIndex])
            let weight = radialWeight(
                u: u,
                v: v,
                focusX: field.focus.x,
                focusY: field.focus.y,
                radius: field.radius,
                softness: field.softness
            ) * clamp(field.opacity)
            result = blend(base: result, layer: fieldColor, amount: weight, mode: field.blend)
        }
        return result.clamped
    }

    private func radialWeight(
        u: Double,
        v: Double,
        focusX: Double,
        focusY: Double,
        radius: Double,
        softness: Double
    ) -> Double {
        let distance = hypot(u - focusX, v - focusY)
        let outer = max(radius, 0.000_1)
        let inner = outer * (1 - clamp(softness))
        return 1 - smoothstep(inner, outer, distance)
    }

    private func blend(base: RGB, layer: RGB, amount: Double, mode: RadialBlend) -> RGB {
        let blended: RGB
        switch mode {
        case .normal:
            blended = layer
        case .screen:
            blended = RGB(
                r: 1 - (1 - base.r) * (1 - layer.r),
                g: 1 - (1 - base.g) * (1 - layer.g),
                b: 1 - (1 - base.b) * (1 - layer.b)
            )
        case .multiply:
            blended = RGB(r: base.r * layer.r, g: base.g * layer.g, b: base.b * layer.b)
        case .softLight:
            blended = RGB(
                r: softLight(base.r, layer.r),
                g: softLight(base.g, layer.g),
                b: softLight(base.b, layer.b)
            )
        }
        return mix(base, blended, clamp(amount))
    }

    private func softLight(_ base: Double, _ layer: Double) -> Double {
        if layer <= 0.5 {
            return base - (1 - 2 * layer) * base * (1 - base)
        }
        let d = base <= 0.25
            ? ((16 * base - 12) * base + 4) * base
            : sqrt(base)
        return base + (2 * layer - 1) * (d - base)
    }

    private func visibilityAdjusted(
        _ color: RGB,
        alpha: Double,
        background: RGB,
        family: MaterialFamily
    ) -> RGB {
        let composited = mix(background, color, alpha)
        let contrast = distance(composited, background)
        let visibilityNeed = 1 - smoothstep(0.075, 0.235, contrast)
        // Mid-value editorial grounds gain contrast by shading, not by adding
        // an achromatic white ribbon between complementary radial colors.
        let target = background.luminance > 0.30 ? RGB.black : RGB.white
        let isMidValueGround = (0.30...0.70).contains(background.luminance)
        let strength: Double
        if !isMidValueGround {
            strength = 0.58
        } else {
            strength = switch family {
            case .outline, .counterform: 0.62
            case .glass, .mist, .halo, .luminous: 0.42
            case .gradient, .solid, .sphere: 0.28
            }
        }
        return mix(color, target, strength * visibilityNeed)
    }

    private func blurred(_ image: CGImage, radius: Double) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let output = input
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = context.createCGImage(output, from: input.extent) else {
            throw MaterialRendererError.cannotCreateImage
        }
        return image
    }

    /// A Gaussian depth blur is allowed to soften an actor, but it must not
    /// turn an intentionally open radial topology into a filled disc. This
    /// radial transfer removes only the blur energy that crossed the center
    /// of halo/outline actors. It leaves every field, contour location, scene
    /// position, diameter, draw order, and depth value unchanged.
    private func restoringOpenCenter(
        _ image: CGImage,
        material: ActorMaterialRecipe,
        sourceDiameter: Int,
        blurRadius: Double
    ) throws -> CGImage {
        let openingOuter: Double
        let openingCenter: CompositionPoint
        let contrastGain: Double
        switch material.family {
        case .halo:
            guard let topology = material.organicTopology else {
                throw MaterialRendererError.invalidMaterial("halo topology was not validated")
            }
            openingCenter = topology.innerCenter
            openingOuter = max(0.23, topology.innerRadius * 0.98)
            contrastGain = 1 + min(0.18, blurRadius / Double(sourceDiameter) * 1.6)
        case .outline:
            guard let innermost = material.organicTopology?.contours.last else {
                throw MaterialRendererError.invalidMaterial("outline topology was not validated")
            }
            openingCenter = innermost.innerCenter
            openingOuter = material.contourCount <= 1
                ? max(0.27, innermost.innerRadius * 0.92)
                : max(0.15, innermost.innerRadius * 0.92)
            let contourPixels = max(1, material.contourWidth * Double(sourceDiameter))
            contrastGain = 1 + min(0.32, blurRadius / contourPixels * 0.16)
        default:
            return image
        }

        let context = try makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rawData = context.data else {
            throw MaterialRendererError.cannotCreateBitmap(image.width, image.height)
        }
        let bytes = rawData.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        let actorOriginX = (Double(image.width) - Double(sourceDiameter)) * 0.5
        let actorOriginY = (Double(image.height) - Double(sourceDiameter)) * 0.5
        let centerX = actorOriginX + openingCenter.x * Double(sourceDiameter)
        let centerY = actorOriginY + openingCenter.y * Double(sourceDiameter)
        let openingInner = openingOuter * (material.family == .halo ? 0.48 : 0.67)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let radialDistance = hypot(
                    Double(x) + 0.5 - centerX,
                    Double(y) + 0.5 - centerY
                ) / Double(sourceDiameter)
                let opening = smoothstep(openingInner, openingOuter, radialDistance)
                let transfer = opening * contrastGain
                let offset = y * bytesPerRow + x * 4
                for channel in 0..<4 {
                    bytes[offset + channel] = UInt8(min(
                        255,
                        (Double(bytes[offset + channel]) * transfer).rounded()
                    ))
                }
            }
        }
        guard let restored = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return restored
    }

    private func padded(_ image: CGImage, by padding: Int) throws -> CGImage {
        let width = image.width + padding * 2
        let height = image.height + padding * 2
        let context = try makeContext(width: width, height: height)
        context.draw(image, in: CGRect(
            x: padding,
            y: padding,
            width: image.width,
            height: image.height
        ))
        guard let padded = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return padded
    }

    private func makeContext(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { throw MaterialRendererError.cannotCreateBitmap(width, height) }
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high
        return context
    }

    private func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw MaterialRendererError.cannotEncodePNG }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw MaterialRendererError.cannotEncodePNG
        }
        return data as Data
    }
}

private struct RGB {
    let r: Double
    let g: Double
    let b: Double

    static let black = RGB(r: 0, g: 0, b: 0)
    static let white = RGB(r: 1, g: 1, b: 1)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ color: MaterialColor) {
        self.init(r: color.red, g: color.green, b: color.blue)
    }

    var clamped: RGB { RGB(r: clamp(r), g: clamp(g), b: clamp(b)) }
    var luminance: Double { r * 0.2126 + g * 0.7152 + b * 0.0722 }

    func scaled(_ amount: Double) -> RGB {
        RGB(r: r * amount, g: g * amount, b: b * amount).clamped
    }
}

private func write(color: RGB, alpha: Double, at offset: Int, into bytes: UnsafeMutablePointer<UInt8>) {
    bytes[offset] = UInt8((clamp(color.r) * alpha * 255).rounded())
    bytes[offset + 1] = UInt8((clamp(color.g) * alpha * 255).rounded())
    bytes[offset + 2] = UInt8((clamp(color.b) * alpha * 255).rounded())
    bytes[offset + 3] = UInt8((clamp(alpha) * 255).rounded())
}

private func mix(_ lhs: RGB, _ rhs: RGB, _ amount: Double) -> RGB {
    let t = clamp(amount)
    return RGB(
        r: lhs.r + (rhs.r - lhs.r) * t,
        g: lhs.g + (rhs.g - lhs.g) * t,
        b: lhs.b + (rhs.b - lhs.b) * t
    )
}

private func distance(_ lhs: RGB, _ rhs: RGB) -> Double {
    hypot(lhs.r - rhs.r, hypot(lhs.g - rhs.g, lhs.b - rhs.b))
}

private func smoothstep(_ lower: Double, _ upper: Double, _ value: Double) -> Double {
    guard upper > lower else { return value < lower ? 0 : 1 }
    let t = clamp((value - lower) / (upper - lower))
    return t * t * (3 - 2 * t)
}

private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
}
