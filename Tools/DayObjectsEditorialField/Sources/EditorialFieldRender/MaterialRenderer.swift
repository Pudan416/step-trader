import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import EditorialFieldCore

enum MaterialOutlineVisibilityPlacement: Equatable, Sendable {
    case none
    case actorLayerPreComposite
}

enum MaterialOutlineCounterfactualMode: Equatable, Sendable {
    case actorRemovedReference
    case capturedActorReplay
}

public enum MaterialPresentationEvidenceRequest: Equatable, Sendable {
    case none
    case perActor
}

public struct MaterialPresentationOwnership: Sendable {
    public let width: Int
    public let height: Int
    public let ownerEventIDs: [String]
    public let ownerLabels: Data
    public let counterfactualBackgroundRGBA: Data
}

public struct MaterialPresentationEvidenceScene: Sendable {
    public let fullScreen: NeutralRenderedImage
    public let calendarTile: NeutralRenderedImage
    public let tileCrop: PixelRect
    public let drawSequence: [String]
    public let ownership: MaterialPresentationOwnership
}

public struct MaterialActorPresentationEvidence: Sendable {
    public let eventID: String
    public let isolated: MaterialPresentationEvidenceScene
    public let removed: MaterialPresentationEvidenceScene
}

public struct MaterialPresentationEvidence: Sendable {
    public let actors: [MaterialActorPresentationEvidence]
}

struct MaterialOutlineOwnershipTrace: Equatable, Sendable {
    let width: Int
    let height: Int
    let ownerEventIDs: [String]
    let ownerLabels: Data
    let counterfactualBackgroundRGBA: Data
}

final class MaterialRenderInstrumentation: @unchecked Sendable, Equatable {
    var canonicalRawSceneRenders = 0
    var actorRemovedFullSceneRenders = 0
    var capturedActorLayerBuilds = 0
    var counterfactualCompositePasses = 0
    var isolatedPresentationComposites = 0
    var ownershipTrace: MaterialOutlineOwnershipTrace?

    static func == (lhs: MaterialRenderInstrumentation, rhs: MaterialRenderInstrumentation) -> Bool {
        lhs === rhs
    }
}

struct MaterialCapturedActorLayer: @unchecked Sendable {
    let image: CGImage
    let drawRect: CGRect
}

final class MaterialRawSceneCapture: @unchecked Sendable, Equatable {
    var actorLayers = [MaterialCapturedActorLayer]()

    static func == (lhs: MaterialRawSceneCapture, rhs: MaterialRawSceneCapture) -> Bool {
        lhs === rhs
    }
}

public struct MaterialRenderConfiguration: Equatable, Sendable {
    public let scale: Int
    public let supersampling: Int
    public let presentationEvidenceRequest: MaterialPresentationEvidenceRequest
    let presentationScale: Int
    let outlineVisibilityPlacement: MaterialOutlineVisibilityPlacement
    let outlineCounterfactualMode: MaterialOutlineCounterfactualMode
    let instrumentation: MaterialRenderInstrumentation?
    let rawSceneCapture: MaterialRawSceneCapture?

    public init(
        scale: Int = 3,
        supersampling: Int = 1,
        presentationEvidenceRequest: MaterialPresentationEvidenceRequest = .none
    ) {
        self.scale = scale
        self.supersampling = supersampling
        self.presentationEvidenceRequest = presentationEvidenceRequest
        self.presentationScale = scale
        self.outlineVisibilityPlacement = .none
        self.outlineCounterfactualMode = .capturedActorReplay
        self.instrumentation = nil
        self.rawSceneCapture = nil
    }

    init(
        scale: Int,
        supersampling: Int = 1,
        outlineVisibilityPlacement: MaterialOutlineVisibilityPlacement,
        outlineCounterfactualMode: MaterialOutlineCounterfactualMode = .capturedActorReplay,
        instrumentation: MaterialRenderInstrumentation? = nil,
        rawSceneCapture: MaterialRawSceneCapture? = nil,
        presentationEvidenceRequest: MaterialPresentationEvidenceRequest = .none,
        presentationScale: Int? = nil
    ) {
        self.scale = scale
        self.supersampling = supersampling
        self.presentationEvidenceRequest = presentationEvidenceRequest
        self.presentationScale = presentationScale ?? scale
        self.outlineVisibilityPlacement = outlineVisibilityPlacement
        self.outlineCounterfactualMode = outlineCounterfactualMode
        self.instrumentation = instrumentation
        self.rawSceneCapture = rawSceneCapture
    }
}

public struct MaterialRenderedScene: Sendable {
    public let fullScreen: NeutralRenderedImage
    public let calendarTile: NeutralRenderedImage
    public let tileCrop: PixelRect
    public let drawSequence: [String]
    public let presentationEvidence: MaterialPresentationEvidence?
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
        background: BackgroundCondition? = nil,
        supersampling: Int = 1
    ) throws -> NeutralRenderedImage {
        guard pixelSize > 0 else { throw MaterialRendererError.invalidPixelSize(pixelSize) }
        guard supersampling > 0 else { throw MaterialRendererError.invalidScale(supersampling) }
        if supersampling > 1 {
            return try renderSupersampledActor(
                material,
                pixelSize: pixelSize,
                background: background,
                supersampling: supersampling
            )
        }
        return try renderActorAtSource(
            material,
            sourcePixelSize: pixelSize,
            presentationPixelSize: pixelSize,
            background: background
        )
    }

    private func renderActorAtSource(
        _ material: ActorMaterialRecipe,
        sourcePixelSize: Int,
        presentationPixelSize: Int,
        background: BackgroundCondition?
    ) throws -> NeutralRenderedImage {
        try validate(material)
        let backgroundColor = background.map(Self.backgroundColor(for:))
        var actorImage = try makeActorImage(
            material,
            pixelSize: sourcePixelSize,
            contrastBackground: backgroundColor
        )
        if material.family == .mist {
            actorImage = try applyingMistGrain(
                actorImage,
                material: material,
                sourceDiameter: sourcePixelSize,
                presentationDiameter: presentationPixelSize,
                background: backgroundColor.map(RGB.init) ?? .black
            )
        }
        let finalImage: CGImage
        if let backgroundColor {
            let context = try makeContext(width: sourcePixelSize, height: sourcePixelSize)
            context.setFillColor(
                red: backgroundColor.red,
                green: backgroundColor.green,
                blue: backgroundColor.blue,
                alpha: 1
            )
            context.fill(CGRect(x: 0, y: 0, width: sourcePixelSize, height: sourcePixelSize))
            context.draw(actorImage, in: CGRect(
                x: 0,
                y: 0,
                width: sourcePixelSize,
                height: sourcePixelSize
            ))
            guard let image = context.makeImage() else { throw MaterialRendererError.cannotCreateImage }
            finalImage = image
        } else {
            finalImage = actorImage
        }
        return NeutralRenderedImage(
            pngData: try pngData(finalImage),
            pixelWidth: sourcePixelSize,
            pixelHeight: sourcePixelSize
        )
    }

    /// Transparent structural masks rendered through the actor-local Gaussian
    /// blur and contour-only topology path. Outline contours are returned
    /// separately so evidence can measure each alpha band without allowing
    /// palette chroma to impersonate topology.
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
                isolatedContourIndex: contourIndex,
                structuralAlphaLayer: true
            )
            if blurRadius >= 0.5 {
                image = try padded(image, by: max(2, Int(ceil(blurRadius * 3))))
                image = try blurred(image, radius: blurRadius)
                image = try restoringStructuralOpening(
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
        guard configuration.supersampling > 0 else {
            throw MaterialRendererError.invalidScale(configuration.supersampling)
        }
        if configuration.supersampling > 1 {
            return try renderSupersampled(
                recipe: recipe,
                material: material,
                background: background,
                configuration: configuration
            )
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
        let presentationShortSide = Double(min(
            Int(recipe.viewport.width) * configuration.presentationScale,
            Int(recipe.viewport.height) * configuration.presentationScale
        ))
        for actor in ordered {
            guard let actorMaterial = material.actor(actor.eventID) else {
                throw MaterialRendererError.missingActorMaterial(actor.eventID)
            }
            try validate(actorMaterial)
            let diameter = max(1, Int(ceil(actor.diameter * shortSide)))
            let presentationDiameter = max(
                1,
                Int(ceil(actor.diameter * presentationShortSide))
            )
            var actorImage = try makeActorImage(
                actorMaterial,
                pixelSize: diameter,
                contrastBackground: backgroundColor
            )
            let outlineAccentImage = actorMaterial.family == .outline
                ? try makeActorImage(
                    actorMaterial,
                    pixelSize: diameter,
                    contrastBackground: backgroundColor,
                    outlineAccentLayer: true
                )
                : nil
            let blur = max(0, actor.localBlur * shortSide)
            if blur >= 0.5 {
                actorImage = try padded(
                    actorImage,
                    by: max(2, Int(ceil(blur * 3)))
                )
                actorImage = try blurred(actorImage, radius: blur)
            }
            if actorMaterial.family == .mist {
                actorImage = try applyingMistGrain(
                    actorImage,
                    material: actorMaterial,
                    sourceDiameter: diameter,
                    presentationDiameter: presentationDiameter,
                    background: RGB(backgroundColor)
                )
            }
            if let outlineAccentImage {
                actorImage = try compositedCentered(
                    outlineAccentImage,
                    over: actorImage,
                    sourceDiameter: diameter
                )
            }
            if actorMaterial.family == .outline,
               configuration.outlineVisibilityPlacement == .actorLayerPreComposite {
                actorImage = try applyingFinalVisibility(
                    actorImage,
                    background: backgroundColor
                )
            }
            let center = CGPoint(
                x: actor.position.x * Double(width),
                y: (1 - actor.position.y) * Double(height)
            )
            let layerWidth = Double(actorImage.width)
            let layerHeight = Double(actorImage.height)
            let layerRect = CGRect(
                x: center.x - layerWidth * 0.5,
                y: center.y - layerHeight * 0.5,
                width: layerWidth,
                height: layerHeight
            )
            if let rawSceneCapture = configuration.rawSceneCapture {
                rawSceneCapture.actorLayers.append(MaterialCapturedActorLayer(
                    image: actorImage,
                    drawRect: layerRect
                ))
                configuration.instrumentation?.capturedActorLayerBuilds += 1
            }
            context.draw(actorImage, in: layerRect)
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
            drawSequence: ordered.map(\.eventID),
            presentationEvidence: nil
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

    private struct FinalOutlineOwnership {
        let eventID: String
        let isolatedAlpha: CGImage
        let actorRemoved: CGImage
    }

    private func renderSupersampled(
        recipe: CompositionRecipe,
        material: DailyMaterialDNA,
        background: BackgroundCondition,
        configuration: MaterialRenderConfiguration
    ) throws -> MaterialRenderedScene {
        let sourceScale = configuration.scale * configuration.supersampling
        let rawSceneCapture = material.family == .outline
            && configuration.outlineVisibilityPlacement == .none
            && configuration.outlineCounterfactualMode == .capturedActorReplay
            ? MaterialRawSceneCapture()
            : nil
        let sourceConfiguration = MaterialRenderConfiguration(
            scale: sourceScale,
            outlineVisibilityPlacement: configuration.outlineVisibilityPlacement,
            instrumentation: configuration.instrumentation,
            rawSceneCapture: rawSceneCapture,
            presentationScale: configuration.presentationScale
        )
        configuration.instrumentation?.canonicalRawSceneRenders += 1
        let source = try render(
            recipe: recipe,
            material: material,
            background: background,
            configuration: sourceConfiguration
        )
        let outputWidth = Int(recipe.viewport.width) * configuration.scale
        let outputHeight = Int(recipe.viewport.height) * configuration.scale
        var fullImage = try downsampled(
            try decodedPNG(source.fullScreen.pngData),
            width: outputWidth,
            height: outputHeight
        )
        var presentationEvidence: MaterialPresentationEvidence?

        if material.family == .outline,
           configuration.outlineVisibilityPlacement == .none {
            var owners = [FinalOutlineOwnership]()
            owners.reserveCapacity(source.drawSequence.count)
            switch configuration.outlineCounterfactualMode {
            case .actorRemovedReference:
                for eventID in source.drawSequence {
                    guard let actor = recipe.actors.first(where: { $0.eventID == eventID }),
                          let actorMaterial = material.actor(eventID)
                    else { throw MaterialRendererError.missingActorMaterial(eventID) }
                    let removedRecipe = CompositionRecipe(
                        daySeed: recipe.daySeed,
                        grammar: recipe.grammar,
                        viewport: recipe.viewport,
                        actors: recipe.actors.filter { $0.eventID != eventID }
                    )
                    configuration.instrumentation?.actorRemovedFullSceneRenders += 1
                    let removed = try render(
                        recipe: removedRecipe,
                        material: material,
                        background: background,
                        configuration: .init(scale: sourceScale)
                    )
                    let actorRemoved = try downsampled(
                        try decodedPNG(removed.fullScreen.pngData),
                        width: outputWidth,
                        height: outputHeight
                    )
                    configuration.instrumentation?.capturedActorLayerBuilds += 1
                    let isolatedAlpha = try downsampled(
                        try outlineActorLayerScene(
                            actor: actor,
                            material: actorMaterial,
                            background: Self.backgroundColor(for: background),
                            width: Int(recipe.viewport.width) * sourceScale,
                            height: Int(recipe.viewport.height) * sourceScale
                        ),
                        width: outputWidth,
                        height: outputHeight
                    )
                    owners.append(FinalOutlineOwnership(
                        eventID: eventID,
                        isolatedAlpha: isolatedAlpha,
                        actorRemoved: actorRemoved
                    ))
                }
            case .capturedActorReplay:
                guard let rawSceneCapture,
                      rawSceneCapture.actorLayers.count == source.drawSequence.count
                else { throw MaterialRendererError.cannotCreateImage }
                var isolatedImages = [CGImage]()
                var singleRemovedImages = [CGImage]()
                isolatedImages.reserveCapacity(source.drawSequence.count)
                singleRemovedImages.reserveCapacity(source.drawSequence.count)
                for actorIndex in source.drawSequence.indices {
                    let isolatedContext = try makeContext(
                        width: Int(recipe.viewport.width) * sourceScale,
                        height: Int(recipe.viewport.height) * sourceScale
                    )
                    isolatedContext.clear(CGRect(
                        x: 0,
                        y: 0,
                        width: isolatedContext.width,
                        height: isolatedContext.height
                    ))
                    let isolatedLayer = rawSceneCapture.actorLayers[actorIndex]
                    isolatedContext.draw(isolatedLayer.image, in: isolatedLayer.drawRect)
                    guard let isolatedAlphaSource = isolatedContext.makeImage() else {
                        throw MaterialRendererError.cannotCreateImage
                    }

                    let removedContext = try makeContext(
                        width: Int(recipe.viewport.width) * sourceScale,
                        height: Int(recipe.viewport.height) * sourceScale
                    )
                    let backgroundColor = Self.backgroundColor(for: background)
                    removedContext.setFillColor(
                        red: backgroundColor.red,
                        green: backgroundColor.green,
                        blue: backgroundColor.blue,
                        alpha: 1
                    )
                    removedContext.fill(CGRect(
                        x: 0,
                        y: 0,
                        width: removedContext.width,
                        height: removedContext.height
                    ))
                    for replayIndex in rawSceneCapture.actorLayers.indices
                    where replayIndex != actorIndex {
                        let layer = rawSceneCapture.actorLayers[replayIndex]
                        removedContext.draw(layer.image, in: layer.drawRect)
                    }
                    guard let actorRemovedSource = removedContext.makeImage() else {
                        throw MaterialRendererError.cannotCreateImage
                    }
                    configuration.instrumentation?.counterfactualCompositePasses += 1
                    let isolatedImage = try downsampled(
                        isolatedAlphaSource,
                        width: outputWidth,
                        height: outputHeight
                    )
                    let singleRemovedImage = try downsampled(
                        actorRemovedSource,
                        width: outputWidth,
                        height: outputHeight
                    )
                    isolatedImages.append(isolatedImage)
                    singleRemovedImages.append(singleRemovedImage)
                    owners.append(FinalOutlineOwnership(
                        eventID: source.drawSequence[actorIndex],
                        isolatedAlpha: isolatedImage,
                        actorRemoved: singleRemovedImage
                    ))
                }
                if configuration.presentationEvidenceRequest == .perActor {
                    let sourceWidth = Int(recipe.viewport.width) * sourceScale
                    let sourceHeight = Int(recipe.viewport.height) * sourceScale
                    let backgroundColor = Self.backgroundColor(for: background)
                    let flatBackground = try downsampled(
                        try compositedCapturedScene(
                            layers: [],
                            excluding: [],
                            width: sourceWidth,
                            height: sourceHeight,
                            background: backgroundColor
                        ),
                        width: outputWidth,
                        height: outputHeight
                    )
                    var doubleRemovedImages = [Int: CGImage]()
                    for firstIndex in source.drawSequence.indices {
                        for secondIndex in source.drawSequence.indices where secondIndex > firstIndex {
                            let pairKey = firstIndex * source.drawSequence.count + secondIndex
                            doubleRemovedImages[pairKey] = try downsampled(
                                try compositedCapturedScene(
                                    layers: rawSceneCapture.actorLayers,
                                    excluding: [firstIndex, secondIndex],
                                    width: sourceWidth,
                                    height: sourceHeight,
                                    background: backgroundColor
                                ),
                                width: outputWidth,
                                height: outputHeight
                            )
                            configuration.instrumentation?.counterfactualCompositePasses += 1
                        }
                    }

                    var actorEvidence = [MaterialActorPresentationEvidence]()
                    actorEvidence.reserveCapacity(source.drawSequence.count)
                    for actorIndex in source.drawSequence.indices {
                        let isolatedSource = try compositedCapturedScene(
                            layers: [rawSceneCapture.actorLayers[actorIndex]],
                            excluding: [],
                            width: sourceWidth,
                            height: sourceHeight,
                            background: backgroundColor
                        )
                        configuration.instrumentation?.isolatedPresentationComposites += 1
                        let isolatedCanonical = try downsampled(
                            isolatedSource,
                            width: outputWidth,
                            height: outputHeight
                        )
                        let isolatedInstrumentation = MaterialRenderInstrumentation()
                        let isolatedPresented = try applyingActorOwnedFinalVisibility(
                            isolatedCanonical,
                            owners: [FinalOutlineOwnership(
                                eventID: source.drawSequence[actorIndex],
                                isolatedAlpha: isolatedImages[actorIndex],
                                actorRemoved: flatBackground
                            )],
                            instrumentation: isolatedInstrumentation
                        )
                        let isolatedTrace = try requiredOwnershipTrace(isolatedInstrumentation)

                        let removedOrder = source.drawSequence.enumerated().compactMap {
                            index, eventID in index == actorIndex ? nil : eventID
                        }
                        var removedOwners = [FinalOutlineOwnership]()
                        removedOwners.reserveCapacity(removedOrder.count)
                        for ownerIndex in source.drawSequence.indices where ownerIndex != actorIndex {
                            let firstIndex = min(actorIndex, ownerIndex)
                            let secondIndex = max(actorIndex, ownerIndex)
                            let pairKey = firstIndex * source.drawSequence.count + secondIndex
                            guard let doubleRemoved = doubleRemovedImages[pairKey] else {
                                throw MaterialRendererError.cannotCreateImage
                            }
                            removedOwners.append(FinalOutlineOwnership(
                                eventID: source.drawSequence[ownerIndex],
                                isolatedAlpha: isolatedImages[ownerIndex],
                                actorRemoved: doubleRemoved
                            ))
                        }
                        let removedInstrumentation = MaterialRenderInstrumentation()
                        let removedPresented = try applyingActorOwnedFinalVisibility(
                            singleRemovedImages[actorIndex],
                            owners: removedOwners,
                            instrumentation: removedInstrumentation
                        )
                        let removedTrace = try requiredOwnershipTrace(removedInstrumentation)
                        actorEvidence.append(MaterialActorPresentationEvidence(
                            eventID: source.drawSequence[actorIndex],
                            isolated: try presentationEvidenceScene(
                                image: isolatedPresented,
                                drawSequence: [source.drawSequence[actorIndex]],
                                ownership: isolatedTrace,
                                outputWidth: outputWidth,
                                outputHeight: outputHeight
                            ),
                            removed: try presentationEvidenceScene(
                                image: removedPresented,
                                drawSequence: removedOrder,
                                ownership: removedTrace,
                                outputWidth: outputWidth,
                                outputHeight: outputHeight
                            )
                        ))
                    }
                    presentationEvidence = MaterialPresentationEvidence(actors: actorEvidence)
                }
            }
            fullImage = try applyingActorOwnedFinalVisibility(
                fullImage,
                owners: owners,
                instrumentation: configuration.instrumentation
            )
        }

        let tileSide = outputWidth
        let tileCrop = PixelRect(
            x: 0,
            y: (outputHeight - tileSide) / 2,
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
                pixelWidth: outputWidth,
                pixelHeight: outputHeight
            ),
            calendarTile: NeutralRenderedImage(
                pngData: try pngData(tileImage),
                pixelWidth: tileSide,
                pixelHeight: tileSide
            ),
            tileCrop: tileCrop,
            drawSequence: source.drawSequence,
            presentationEvidence: presentationEvidence
        )
    }

    private func compositedCapturedScene(
        layers: [MaterialCapturedActorLayer],
        excluding excludedIndices: Set<Int>,
        width: Int,
        height: Int,
        background: MaterialColor
    ) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(
            red: background.red,
            green: background.green,
            blue: background.blue,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for index in layers.indices where !excludedIndices.contains(index) {
            context.draw(layers[index].image, in: layers[index].drawRect)
        }
        guard let image = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return image
    }

    private func requiredOwnershipTrace(
        _ instrumentation: MaterialRenderInstrumentation
    ) throws -> MaterialOutlineOwnershipTrace {
        guard let trace = instrumentation.ownershipTrace else {
            throw MaterialRendererError.cannotCreateImage
        }
        return trace
    }

    private func presentationEvidenceScene(
        image: CGImage,
        drawSequence: [String],
        ownership: MaterialOutlineOwnershipTrace,
        outputWidth: Int,
        outputHeight: Int
    ) throws -> MaterialPresentationEvidenceScene {
        let tileCrop = PixelRect(
            x: 0,
            y: (outputHeight - outputWidth) / 2,
            width: outputWidth,
            height: outputWidth
        )
        guard let tileImage = image.cropping(to: CGRect(
            x: tileCrop.x,
            y: tileCrop.y,
            width: tileCrop.width,
            height: tileCrop.height
        )) else { throw MaterialRendererError.cannotCreateImage }
        return MaterialPresentationEvidenceScene(
            fullScreen: NeutralRenderedImage(
                pngData: try pngData(image),
                pixelWidth: outputWidth,
                pixelHeight: outputHeight
            ),
            calendarTile: NeutralRenderedImage(
                pngData: try pngData(tileImage),
                pixelWidth: outputWidth,
                pixelHeight: outputWidth
            ),
            tileCrop: tileCrop,
            drawSequence: drawSequence,
            ownership: MaterialPresentationOwnership(
                width: ownership.width,
                height: ownership.height,
                ownerEventIDs: ownership.ownerEventIDs,
                ownerLabels: ownership.ownerLabels,
                counterfactualBackgroundRGBA: ownership.counterfactualBackgroundRGBA
            )
        )
    }

    private func renderSupersampledActor(
        _ material: ActorMaterialRecipe,
        pixelSize: Int,
        background: BackgroundCondition?,
        supersampling: Int
    ) throws -> NeutralRenderedImage {
        let sourceSize = pixelSize * supersampling
        let source = try renderActorAtSource(
            material,
            sourcePixelSize: sourceSize,
            presentationPixelSize: pixelSize,
            background: background
        )
        var image = try downsampled(
            try decodedPNG(source.pngData),
            width: pixelSize,
            height: pixelSize
        )
        if material.family == .outline, let background {
            let isolated = try renderActor(material, pixelSize: sourceSize)
            let isolatedAlpha = try downsampled(
                try decodedPNG(isolated.pngData),
                width: pixelSize,
                height: pixelSize
            )
            let actorRemoved = try flatImage(
                width: pixelSize,
                height: pixelSize,
                color: Self.backgroundColor(for: background)
            )
            image = try applyingActorOwnedFinalVisibility(
                image,
                owners: [FinalOutlineOwnership(
                    eventID: material.eventID,
                    isolatedAlpha: isolatedAlpha,
                    actorRemoved: actorRemoved
                )],
                instrumentation: nil
            )
        }
        return NeutralRenderedImage(
            pngData: try pngData(image),
            pixelWidth: pixelSize,
            pixelHeight: pixelSize
        )
    }

    private func outlineActorLayerScene(
        actor: ActorCompositionRecipe,
        material: ActorMaterialRecipe,
        background: MaterialColor,
        width: Int,
        height: Int
    ) throws -> CGImage {
        let shortSide = Double(min(width, height))
        let diameter = max(1, Int(ceil(actor.diameter * shortSide)))
        var actorImage = try makeActorImage(
            material,
            pixelSize: diameter,
            contrastBackground: background
        )
        let accent = try makeActorImage(
            material,
            pixelSize: diameter,
            contrastBackground: background,
            outlineAccentLayer: true
        )
        let blur = max(0, actor.localBlur * shortSide)
        if blur >= 0.5 {
            actorImage = try padded(actorImage, by: max(2, Int(ceil(blur * 3))))
            actorImage = try blurred(actorImage, radius: blur)
        }
        actorImage = try compositedCentered(
            accent,
            over: actorImage,
            sourceDiameter: diameter
        )
        let context = try makeContext(width: width, height: height)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
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
        guard let image = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return image
    }

    /// Final-resolution outline presentation. Ownership is resolved from the
    /// already-downsampled actor layers in reverse canonical draw order. This
    /// stage changes RGB only; canonical alpha and compositing stay untouched.
    private func applyingActorOwnedFinalVisibility(
        _ image: CGImage,
        owners: [FinalOutlineOwnership],
        instrumentation: MaterialRenderInstrumentation?
    ) throws -> CGImage {
        let output = try makeContext(width: image.width, height: image.height)
        output.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let outputData = output.data else {
            throw MaterialRendererError.cannotCreateBitmap(image.width, image.height)
        }
        let outputBytes = outputData.assumingMemoryBound(to: UInt8.self)
        let outputRow = output.bytesPerRow
        let ownerContexts = try owners.map { owner -> (CGContext, CGContext) in
            let isolated = try makeContext(width: image.width, height: image.height)
            isolated.draw(
                owner.isolatedAlpha,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            let removed = try makeContext(width: image.width, height: image.height)
            removed.draw(
                owner.actorRemoved,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
            return (isolated, removed)
        }
        var ownerLabels = instrumentation.map { _ in
            Data(repeating: 255, count: image.width * image.height)
        }
        var counterfactualBackground = instrumentation.map { _ in
            Data(repeating: 0, count: image.width * image.height * 4)
        }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * outputRow + x * 4
                guard outputBytes[offset + 3] > 0 else { continue }
                for ownerIndex in ownerContexts.indices.reversed() {
                    let (isolated, removed) = ownerContexts[ownerIndex]
                    guard let isolatedData = isolated.data, let removedData = removed.data else {
                        throw MaterialRendererError.cannotCreateBitmap(image.width, image.height)
                    }
                    let isolatedOffset = y * isolated.bytesPerRow + x * 4
                    let isolatedBytes = isolatedData.assumingMemoryBound(to: UInt8.self)
                    guard isolatedBytes[isolatedOffset + 3] > 0 else { continue }
                    let removedOffset = y * removed.bytesPerRow + x * 4
                    let removedBytes = removedData.assumingMemoryBound(to: UInt8.self)
                    let pixelIndex = y * image.width + x
                    ownerLabels?[pixelIndex] = UInt8(ownerIndex)
                    for channel in 0..<4 {
                        counterfactualBackground?[pixelIndex * 4 + channel] =
                            removedBytes[removedOffset + channel]
                    }
                    if outputBytes[offset] != removedBytes[removedOffset]
                        || outputBytes[offset + 1] != removedBytes[removedOffset + 1]
                        || outputBytes[offset + 2] != removedBytes[removedOffset + 2] {
                        let adjusted = Self.outlineVisibilityPixel(
                            OutlineVisibilityPixel(
                                red: outputBytes[offset],
                                green: outputBytes[offset + 1],
                                blue: outputBytes[offset + 2],
                                alpha: outputBytes[offset + 3]
                            ),
                            background: MaterialColor(
                                red: Double(removedBytes[removedOffset]) / 255,
                                green: Double(removedBytes[removedOffset + 1]) / 255,
                                blue: Double(removedBytes[removedOffset + 2]) / 255
                            )
                        )
                        outputBytes[offset] = adjusted.red
                        outputBytes[offset + 1] = adjusted.green
                        outputBytes[offset + 2] = adjusted.blue
                    }
                    break
                }
            }
        }
        if let ownerLabels, let counterfactualBackground {
            instrumentation?.ownershipTrace = MaterialOutlineOwnershipTrace(
                width: image.width,
                height: image.height,
                ownerEventIDs: owners.map(\.eventID),
                ownerLabels: ownerLabels,
                counterfactualBackgroundRGBA: counterfactualBackground
            )
        }
        guard let adjusted = output.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return adjusted
    }

    private func downsampled(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return result
    }

    private func decodedPNG(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw MaterialRendererError.cannotCreateImage }
        return image
    }

    private func flatImage(width: Int, height: Int, color: MaterialColor) throws -> CGImage {
        let context = try makeContext(width: width, height: height)
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return image
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
        isolatedContourIndex: Int? = nil,
        structuralAlphaLayer: Bool = false,
        outlineAccentLayer: Bool = false
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
                    if structuralAlphaLayer {
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
                    } else {
                        let fieldVolume = material.fields.map { field in
                            radialWeight(
                                u: u,
                                v: v,
                                focusX: field.focus.x,
                                focusY: field.focus.y,
                                radius: max(0.42, field.radius * 0.72),
                                softness: max(0.74, field.softness),
                            ) * clamp(field.opacity)
                        }.reduce(0, +) / Double(max(material.fields.count, 1))
                        let innerBloom = radialWeight(
                            u: u,
                            v: v,
                            focusX: innerCenter.x,
                            focusY: innerCenter.y,
                            radius: max(0.34, organicInnerRadius * 1.75),
                            softness: 0.86
                        )
                        let outerBloom = radialWeight(
                            u: u,
                            v: v,
                            focusX: outerCenter.x,
                            focusY: outerCenter.y,
                            radius: organicOuterRadius,
                            softness: 0.82
                        )
                        let aura = clamp(0.52 + fieldVolume * 0.18 + innerBloom * 0.17 + outerBloom * 0.13)
                        alpha = min(alpha, body) * aura * (0.78 + outerBloom * 0.22)
                        color = mix(color, RGB.white, min(0.14, innerBloom * 0.08 + fieldVolume * 0.06))
                        if let contrastBackground {
                            let nucleus = exp(
                                -pow(innerDistance / organicInnerRadius, 2)
                            )
                            let background = RGB(contrastBackground)
                            let nucleusTarget = Self.outlineVisibilityTargetRGB(
                                color,
                                background: background
                            )
                            color = mix(
                                color,
                                nucleusTarget,
                                min(1, nucleus + outerBloom * 0.18)
                            )
                        }
                    }
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
                    var ridgeAlpha = 0.0
                    guard let topology = material.organicTopology else {
                        throw MaterialRendererError.invalidMaterial("outline topology was not validated")
                    }
                    let contours: ArraySlice<OrganicRadialContour>
                    if let isolatedContourIndex {
                        guard topology.contours.indices.contains(isolatedContourIndex) else {
                            throw MaterialRendererError.invalidMaterial("outline contour index is invalid")
                        }
                        contours = topology.contours[isolatedContourIndex...isolatedContourIndex]
                    } else if outlineAccentLayer {
                        contours = topology.contours.prefix(1)
                    } else {
                        contours = topology.contours[...]
                    }
                    let fieldVolume = material.fields.map { field in
                        radialWeight(
                            u: u,
                            v: v,
                            focusX: field.focus.x,
                            focusY: field.focus.y,
                            radius: max(0.36, field.radius * 0.66),
                            softness: max(0.72, field.softness)
                        ) * clamp(field.opacity)
                    }.reduce(0, +) / Double(max(material.fields.count, 1))
                    let minimumContourWidth = 2 / Double(pixelSize)
                    let envelopeOuterRadius = topology.contours.first?.outerRadius
                        ?? topology.outerRadius
                    let envelopeInnerRadius = topology.contours.last?.innerRadius
                        ?? topology.innerRadius
                    for contour in contours {
                        let authoredWidth = contour.outerRadius - contour.innerRadius
                        let presentedWidth = max(authoredWidth, minimumContourWidth)
                        let midpoint = (contour.outerRadius + contour.innerRadius) * 0.5
                        var presentedOuterRadius = min(
                            envelopeOuterRadius,
                            midpoint + presentedWidth * 0.5
                        )
                        var presentedInnerRadius = max(
                            envelopeInnerRadius,
                            midpoint - presentedWidth * 0.5
                        )
                        if presentedOuterRadius - presentedInnerRadius < presentedWidth {
                            if presentedOuterRadius == envelopeOuterRadius {
                                presentedInnerRadius = max(
                                    envelopeInnerRadius,
                                    presentedOuterRadius - presentedWidth
                                )
                            } else {
                                presentedOuterRadius = min(
                                    envelopeOuterRadius,
                                    presentedInnerRadius + presentedWidth
                                )
                            }
                        }
                        let outerDistance = hypot(
                            u - contour.outerCenter.x,
                            v - contour.outerCenter.y
                        )
                        let innerDistance = hypot(
                            u - contour.innerCenter.x,
                            v - contour.innerCenter.y
                        )
                        let outerFill = 1 - smoothstep(
                            presentedOuterRadius - antialias * 1.8,
                            presentedOuterRadius + antialias * 1.2,
                            outerDistance
                        )
                        let innerCut = smoothstep(
                            presentedInnerRadius - antialias * 1.4,
                            presentedInnerRadius + antialias * 1.8,
                            innerDistance
                        )
                        let contourPresence: Double
                        if structuralAlphaLayer {
                            contourPresence = 1
                        } else if outlineAccentLayer {
                            contourPresence = 0.18 + pow(fieldVolume, 1.7) * 0.82
                        } else {
                            contourPresence = 0.56 + fieldVolume * 0.44
                        }
                        let ringAlpha = outerFill * innerCut * contour.opacity * contourPresence
                        contourAlpha = max(
                            contourAlpha,
                            ringAlpha
                        )
                        if !structuralAlphaLayer || outlineAccentLayer {
                            let ridgeWidth = max(
                                antialias * 2.0,
                                (presentedOuterRadius - presentedInnerRadius) * 0.22
                            )
                            let outerRidge = 1 - smoothstep(
                                ridgeWidth * 0.36,
                                ridgeWidth * 1.35,
                                abs(outerDistance - presentedOuterRadius)
                            )
                            let innerRidge = 1 - smoothstep(
                                ridgeWidth * 0.36,
                                ridgeWidth * 1.35,
                                abs(innerDistance - presentedInnerRadius)
                            )
                            let ridge = outlineAccentLayer
                                ? outerRidge * innerCut
                                : max(outerRidge * innerCut, innerRidge * outerFill)
                            ridgeAlpha = max(
                                ridgeAlpha,
                                ridge
                                    * contour.opacity
                                    * contourPresence
                            )
                        }
                    }
                    if structuralAlphaLayer {
                        alpha = contourAlpha
                    } else if outlineAccentLayer {
                        let baseInk = RGB(material.colors[0])
                        let ridgeInk = if material.colors.count > 1 {
                            color
                        } else {
                            baseInk.scaled(baseInk.luminance > 0.58 ? 0.72 : 1.45)
                        }
                        alpha = clamp(contourAlpha * 0.06 + ridgeAlpha * 0.82)
                        color = mix(
                            color,
                            ridgeInk,
                            min(0.82, ridgeAlpha * 0.74 + contourAlpha * 0.05)
                        )
                    } else {
                        alpha = clamp(contourAlpha * 0.72 + ridgeAlpha * 0.82)
                        let baseInk = RGB(material.colors[0])
                        let ridgeInk = if material.colors.count > 1 {
                            color
                        } else {
                            baseInk.scaled(baseInk.luminance > 0.58 ? 0.72 : 1.45)
                        }
                        color = mix(
                            color,
                            ridgeInk,
                            min(0.82, ridgeAlpha * 0.68 + contourAlpha * 0.16)
                        )
                    }
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

    private func mistSeed(material: ActorMaterialRecipe) -> UInt64 {
        var bytes = Data("editorial-mist-grain-seed-v1\0".utf8)

        func appendUInt32(_ value: UInt32) {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
        }
        func appendString(_ value: String) {
            let encoded = Data(value.utf8)
            appendUInt32(UInt32(encoded.count))
            bytes.append(encoded)
        }
        func appendDouble(_ value: Double) {
            let canonical = value == 0 ? 0.0 : value
            var bigEndian = canonical.bitPattern.bigEndian
            withUnsafeBytes(of: &bigEndian) { bytes.append(contentsOf: $0) }
        }

        appendString(material.family.rawValue)
        appendUInt32(UInt32(material.colors.count))
        for color in material.colors {
            appendDouble(color.red)
            appendDouble(color.green)
            appendDouble(color.blue)
        }
        appendUInt32(UInt32(material.fields.count))
        for field in material.fields {
            appendDouble(field.focus.x)
            appendDouble(field.focus.y)
            appendDouble(field.radius)
            appendDouble(field.softness)
            appendDouble(field.opacity)
            appendUInt32(UInt32(field.colorIndex))
            appendString(field.blend.rawValue)
        }
        appendDouble(material.baseOpacity)
        appendDouble(material.edgeSoftness)

        return SHA256.hash(data: bytes).prefix(8).reduce(UInt64(0)) { seed, byte in
            (seed << 8) | UInt64(byte)
        }
    }

    private func mistGradient(x: Int, y: Int, seed: UInt64) -> (Double, Double) {
        var value = seed
            ^ UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
            ^ UInt64(bitPattern: Int64(y)) &* 0xBF58_476D_1CE4_E5B9
        value ^= value >> 30
        value &*= 0xBF58_476D_1CE4_E5B9
        value ^= value >> 27
        value &*= 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        let angle = Double(value >> 11) / 9_007_199_254_740_992 * Double.pi * 2
        return (cos(angle), sin(angle))
    }

    private func mistSimplexGradientNoise(x: Double, y: Double, seed: UInt64) -> Double {
        let skew = (sqrt(3) - 1) * 0.5
        let unskew = (3 - sqrt(3)) / 6
        let cellX = Int(floor(x + (x + y) * skew))
        let cellY = Int(floor(y + (x + y) * skew))
        let origin = Double(cellX + cellY) * unskew
        let x0 = x - (Double(cellX) - origin)
        let y0 = y - (Double(cellY) - origin)
        let first = x0 > y0 ? (1, 0) : (0, 1)
        let x1 = x0 - Double(first.0) + unskew
        let y1 = y0 - Double(first.1) + unskew
        let x2 = x0 - 1 + 2 * unskew
        let y2 = y0 - 1 + 2 * unskew

        func contribution(_ dx: Double, _ dy: Double, _ ix: Int, _ iy: Int) -> Double {
            let kernel = 0.5 - dx * dx - dy * dy
            guard kernel > 0 else { return 0 }
            let gradient = mistGradient(x: ix, y: iy, seed: seed)
            let compact = kernel * kernel * kernel * kernel
            return compact * (gradient.0 * dx + gradient.1 * dy)
        }
        return 70 * (
            contribution(x0, y0, cellX, cellY)
                + contribution(x1, y1, cellX + first.0, cellY + first.1)
                + contribution(x2, y2, cellX + 1, cellY + 1)
        )
    }

    private func mistFineField(
        x: Double,
        y: Double,
        seed: UInt64
    ) -> Double {
        // A final presentation pixel has a Nyquist period of two pixels. The
        // two positive compact-gradient octaves sit at 2x Nyquist and Nyquist,
        // independent of actor diameter and supersampling source scale.
        let nyquistPeriod = 2.0
        let broad = mistSimplexGradientNoise(
            x: x / (nyquistPeriod * 2),
            y: y / (nyquistPeriod * 2),
            seed: seed
        )
        let fine = mistSimplexGradientNoise(
            x: x / nyquistPeriod,
            y: y / nyquistPeriod,
            seed: seed ^ 0xA5A5_7E57
        )
        let broadFrequency = 1 / (nyquistPeriod * 2)
        let fineFrequency = 1 / nyquistPeriod
        let frequencySum = broadFrequency + fineFrequency
        return broad * (broadFrequency / frequencySum)
            + fine * (fineFrequency / frequencySum)
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
        if family == .outline {
            return Self.outlineVisibilityAdjustedRGB(
                color,
                alpha: alpha,
                background: background
            )
        }
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

    static func outlineVisibilityTarget(
        color: MaterialColor,
        background: MaterialColor
    ) -> MaterialColor {
        let target = outlineVisibilityTargetRGB(RGB(color), background: RGB(background))
        return MaterialColor(red: target.r, green: target.g, blue: target.b)
    }

    static func outlineVisibilityAdjustedColor(
        _ color: MaterialColor,
        alpha: Double,
        background: MaterialColor
    ) -> MaterialColor {
        let adjusted = outlineVisibilityAdjustedRGB(
            RGB(color),
            alpha: alpha,
            background: RGB(background)
        )
        return MaterialColor(red: adjusted.r, green: adjusted.g, blue: adjusted.b)
    }

    static func outlineVisibilityPixel(
        _ pixel: OutlineVisibilityPixel,
        background: MaterialColor
    ) -> OutlineVisibilityPixel {
        guard pixel.alpha > 0 else { return pixel }
        let alphaByte = Double(pixel.alpha)
        let adjusted = outlineVisibilityAdjustedRGB(
            RGB(
                r: Double(pixel.red) / alphaByte,
                g: Double(pixel.green) / alphaByte,
                b: Double(pixel.blue) / alphaByte
            ),
            alpha: alphaByte / 255,
            background: RGB(background)
        )
        return OutlineVisibilityPixel(
            red: UInt8((clamp(adjusted.r) * alphaByte).rounded()),
            green: UInt8((clamp(adjusted.g) * alphaByte).rounded()),
            blue: UInt8((clamp(adjusted.b) * alphaByte).rounded()),
            alpha: pixel.alpha
        )
    }

    private static func outlineVisibilityAdjustedRGB(
        _ color: RGB,
        alpha: Double,
        background: RGB
    ) -> RGB {
        let composited = mix(background, color, alpha)
        let contrast = distance(composited, background)
        let visibilityNeed = 1 - smoothstep(0.075, 0.235, contrast)
        let target = outlineVisibilityTargetRGB(color, background: background)
        return mix(color, target, 0.62 * visibilityNeed)
    }

    private static func outlineVisibilityTargetRGB(
        _ color: RGB,
        background: RGB
    ) -> RGB {
        let direction = RGB(
            r: color.r - background.r,
            g: color.g - background.g,
            b: color.b - background.b
        )
        let limits = [
            projectionLimit(background: background.r, direction: direction.r),
            projectionLimit(background: background.g, direction: direction.g),
            projectionLimit(background: background.b, direction: direction.b),
        ].filter(\.isFinite)
        guard let furthest = limits.min(), furthest >= 1 else { return color }
        return RGB(
            r: background.r + direction.r * furthest,
            g: background.g + direction.g * furthest,
            b: background.b + direction.b * furthest
        ).clamped
    }

    private static func projectionLimit(background: Double, direction: Double) -> Double {
        if direction > 0 { return (1 - background) / direction }
        if direction < 0 { return (0 - background) / direction }
        return .infinity
    }

    private static func projectionLowerLimit(background: Double, direction: Double) -> Double {
        if direction > 0 { return (0 - background) / direction }
        if direction < 0 { return (1 - background) / direction }
        return -.infinity
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

    /// Structural alpha evidence is allowed to stay contour-only even when the
    /// normal scene render has a filled material body. This radial transfer is
    /// used only by `renderStructuralAlphaLayers` after blur so evidence can
    /// keep measuring the authored contour topology independently of RGB.
    private func restoringStructuralOpening(
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

    private func compositedCentered(
        _ overlay: CGImage,
        over base: CGImage,
        sourceDiameter: Int
    ) throws -> CGImage {
        let context = try makeContext(width: base.width, height: base.height)
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        let originX = (Double(base.width) - Double(sourceDiameter)) * 0.5
        let originY = (Double(base.height) - Double(sourceDiameter)) * 0.5
        context.draw(overlay, in: CGRect(
            x: originX,
            y: originY,
            width: Double(sourceDiameter),
            height: Double(sourceDiameter)
        ))
        guard let composited = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return composited
    }

    private func compositedCenteredSourceAtop(
        _ overlay: CGImage,
        over base: CGImage,
        sourceDiameter: Int
    ) throws -> CGImage {
        let context = try makeContext(width: base.width, height: base.height)
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard let rawData = context.data else {
            throw MaterialRendererError.cannotCreateBitmap(base.width, base.height)
        }
        let bytes = rawData.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        let overlayContext = try makeContext(width: overlay.width, height: overlay.height)
        overlayContext.draw(overlay, in: CGRect(
            x: 0,
            y: 0,
            width: overlay.width,
            height: overlay.height
        ))
        guard let overlayData = overlayContext.data else {
            throw MaterialRendererError.cannotCreateBitmap(overlay.width, overlay.height)
        }
        let overlayBytes = overlayData.assumingMemoryBound(to: UInt8.self)
        let overlayBytesPerRow = overlayContext.bytesPerRow
        let originX = (base.width - sourceDiameter) / 2
        let originY = (base.height - sourceDiameter) / 2

        for sourceY in 0..<sourceDiameter {
            let destinationY = originY + sourceY
            guard (0..<base.height).contains(destinationY) else { continue }
            for sourceX in 0..<sourceDiameter {
                let destinationX = originX + sourceX
                guard (0..<base.width).contains(destinationX) else { continue }
                let sourceOffset = sourceY * overlayBytesPerRow + sourceX * 4
                let sourceAlpha = Double(overlayBytes[sourceOffset + 3]) / 255
                guard sourceAlpha > 0 else { continue }
                let destinationOffset = destinationY * bytesPerRow + destinationX * 4
                let destinationAlpha = Double(bytes[destinationOffset + 3]) / 255
                for channel in 0..<3 {
                    let source = Double(overlayBytes[sourceOffset + channel])
                    let destination = Double(bytes[destinationOffset + channel])
                    bytes[destinationOffset + channel] = UInt8(clamping: Int(
                        (source * destinationAlpha + destination * (1 - sourceAlpha)).rounded()
                    ))
                }
            }
        }
        guard let composited = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return composited
    }

    private func applyingMistGrain(
        _ image: CGImage,
        material: ActorMaterialRecipe,
        sourceDiameter: Int,
        presentationDiameter: Int,
        background: RGB
    ) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rawData = context.data else {
            throw MaterialRendererError.cannotCreateBitmap(image.width, image.height)
        }
        let bytes = rawData.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        let originX = (Double(image.width) - Double(sourceDiameter)) * 0.5
        let originY = (Double(image.height) - Double(sourceDiameter)) * 0.5
        let presentationRatio = Double(sourceDiameter) / Double(max(presentationDiameter, 1))
        let seed = mistSeed(material: material)
        var field = [Double](repeating: 0, count: image.width * image.height)
        var weightedSum = 0.0
        var alphaWeight = 0.0

        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * 4
                let alpha = Double(bytes[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let presentationX = (Double(x) + 0.5 - originX) / presentationRatio
                let presentationY = (Double(y) + 0.5 - originY) / presentationRatio
                let value = mistFineField(x: presentationX, y: presentationY, seed: seed)
                field[y * image.width + x] = value
                weightedSum += value * alpha
                alphaWeight += alpha
            }
        }
        let supportMean = weightedSum / max(alphaWeight, Double.ulpOfOne)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * 4
                let alpha = bytes[offset + 3]
                guard alpha > 0 else { continue }
                let alphaValue = Double(alpha)
                let color = RGB(
                    r: Double(bytes[offset]) / alphaValue,
                    g: Double(bytes[offset + 1]) / alphaValue,
                    b: Double(bytes[offset + 2]) / alphaValue
                )
                let direction = RGB(
                    r: color.r - background.r,
                    g: color.g - background.g,
                    b: color.b - background.b
                )
                let lower = max(
                    Self.projectionLowerLimit(background: background.r, direction: direction.r),
                    Self.projectionLowerLimit(background: background.g, direction: direction.g),
                    Self.projectionLowerLimit(background: background.b, direction: direction.b)
                )
                let upper = min(
                    Self.projectionLimit(background: background.r, direction: direction.r),
                    Self.projectionLimit(background: background.g, direction: direction.g),
                    Self.projectionLimit(background: background.b, direction: direction.b)
                )
                let symmetricSpan = max(0, min(1 - lower, upper - 1))
                let delta = max(
                    -symmetricSpan,
                    min(symmetricSpan, (field[y * image.width + x] - supportMean) * 0.16)
                )
                let adjusted = RGB(
                    r: background.r + direction.r * (1 + delta),
                    g: background.g + direction.g * (1 + delta),
                    b: background.b + direction.b * (1 + delta)
                ).clamped
                bytes[offset] = UInt8((adjusted.r * alphaValue).rounded())
                bytes[offset + 1] = UInt8((adjusted.g * alphaValue).rounded())
                bytes[offset + 2] = UInt8((adjusted.b * alphaValue).rounded())
            }
        }
        guard let textured = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return textured
    }

    /// Local blur works on premultiplied pixels and can reduce a thin contour's
    /// final contrast after the authored visibility adjustment. Reapply the
    /// same background-aware RGB transfer to the presented outline layer while
    /// leaving every alpha byte untouched.
    private func applyingFinalVisibility(
        _ image: CGImage,
        background: MaterialColor
    ) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rawData = context.data else {
            throw MaterialRendererError.cannotCreateBitmap(image.width, image.height)
        }
        let bytes = rawData.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = y * bytesPerRow + x * 4
                let adjusted = Self.outlineVisibilityPixel(
                    OutlineVisibilityPixel(
                        red: bytes[offset],
                        green: bytes[offset + 1],
                        blue: bytes[offset + 2],
                        alpha: bytes[offset + 3]
                    ),
                    background: background
                )
                bytes[offset] = adjusted.red
                bytes[offset + 1] = adjusted.green
                bytes[offset + 2] = adjusted.blue
            }
        }
        guard let adjusted = context.makeImage() else {
            throw MaterialRendererError.cannotCreateImage
        }
        return adjusted
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

struct OutlineVisibilityPixel: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
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
