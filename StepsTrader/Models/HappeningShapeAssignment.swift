import Foundation

/// The figure a happening takes for one custom day: which shape type, which
/// colour, the seed that gives it its own silhouette within that type, and the
/// rotation that turns it.
struct HappeningShapeAssignment: Hashable {
    let shapeType: CanvasShapeType
    let colorHex: String
    let seed: UInt64
    /// Radians. Carried rather than left to the renderer because
    /// `RayShapeRenderer` derives its cone direction from the vector between the
    /// element and the canvas centre — and a palette tile puts the element *at*
    /// the centre, where that vector is zero and every tile came out pointing
    /// the same way.
    let rotation: Double
}

/// The exact Editorial actor promised by a palette item. The UUID and color
/// variation are persisted with the eventual canvas element, so the preview
/// and the committed object travel through the same production recipe.
struct HappeningEditorialAssignment: Equatable {
    let elementID: UUID
    let shape: DayObjectShape
    let material: DayObjectEditorialMaterialV1
    let colorVariant: Int
}

enum HappeningEditorialAssignmentResolver {
    private static let colorVariationCount = 97

    static func assignments(
        happenings: [Happening],
        baseInput: DayObjectSceneInput,
        colorNonce: UInt64
    ) -> [String: HappeningEditorialAssignment] {
        happenings.reduce(into: [:]) { result, happening in
            let elementID = stableElementID(happeningID: happening.id, dayKey: baseInput.dayKey)
            let eventID = elementID.uuidString.lowercased()
            let colorVariant = colorVariant(
                happeningID: happening.id,
                dayKey: baseInput.dayKey,
                nonce: colorNonce
            )
            var variants = baseInput.actorColorVariants
            variants[eventID] = colorVariant
            let eventIDs = baseInput.eventIDs.contains(eventID)
                ? baseInput.eventIDs
                : baseInput.eventIDs + [eventID]
            let input = DayObjectSceneInput(
                dayKey: baseInput.dayKey,
                identity: baseInput.identity,
                eventIDs: eventIDs,
                motionEnergy: baseInput.motionEnergy,
                visualClarity: baseInput.visualClarity,
                uiExclusionRegion: baseInput.uiExclusionRegion,
                canvasCoverage: baseInput.canvasCoverage,
                paletteCategories: baseInput.paletteCategories,
                usesEditorialField: baseInput.usesEditorialField,
                editorialBackground: baseInput.editorialBackground,
                lowSleep: baseInput.lowSleep,
                editorialPreview: baseInput.editorialPreview,
                editorialLabConfiguration: baseInput.editorialLabConfiguration,
                actorColorVariants: variants
            )
            guard let actor = DayObjectScene.make(input: input).sceneRecipeV1?.actor(eventID) else {
                return
            }
            result[happening.id] = HappeningEditorialAssignment(
                elementID: elementID,
                shape: actor.shape,
                material: actor.material,
                colorVariant: colorVariant
            )
        }
    }

    private static func colorVariant(happeningID: String, dayKey: String, nonce: UInt64) -> Int {
        let base = CanvasElement.makeSeed(
            optionId: "editorial-color:\(happeningID)",
            dayKey: dayKey,
            index: 0
        )
        return Int((base &+ nonce) % UInt64(colorVariationCount))
    }

    private static func stableElementID(happeningID: String, dayKey: String) -> UUID {
        let high = CanvasElement.makeSeed(
            optionId: "editorial-element-high:\(happeningID)",
            dayKey: dayKey,
            index: 0
        )
        let low = CanvasElement.makeSeed(
            optionId: "editorial-element-low:\(happeningID)",
            dayKey: dayKey,
            index: 0
        )
        var bytes = withUnsafeBytes(of: high.bigEndian, Array.init)
            + withUnsafeBytes(of: low.bigEndian, Array.init)
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Deterministic, storage-free derivation of a day's figures.
///
/// Nothing is persisted but the nonce: the same `(id, dayKey, nonce)` always
/// gives the same figure, so a stored map would only be a second source of
/// truth to go stale when the configured ten change mid-day.
enum HappeningShapeRoll {

    /// Small, fast, and — unlike `SystemRandomNumberGenerator` — reproducible,
    /// which is what lets a test assert anything about a roll at all.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func assignments(
        for ids: [String],
        dayKey: String,
        nonce: UInt64,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        palette: [String] = CanvasColorPalette.paletteHex
    ) -> [String: HappeningShapeAssignment] {
        let shapes = allowedShapes.isEmpty ? [.circle] : allowedShapes
        let colours = distinctColours(count: ids.count, dayKey: dayKey, nonce: nonce, palette: palette)

        return ids.enumerated().reduce(into: [:]) { result, pair in
            let (index, id) = pair
            let seed = figureSeed(optionId: id, dayKey: dayKey, nonce: nonce)
            var generator = SplitMix64(seed: seed)
            let shapeType = shapes.randomElement(using: &generator) ?? .circle
            let rotation = Double.random(in: 0..<(2 * .pi), using: &generator)
            result[id] = HappeningShapeAssignment(
                shapeType: shapeType,
                colorHex: colours[index % colours.count],
                seed: seed,
                rotation: rotation
            )
        }
    }

    /// Index-independent, unlike `CanvasElement.spawn`'s own derivation, which
    /// mixes in how many elements are already on the canvas. Index 0 is passed
    /// deliberately: a tile must not change silhouette as other tiles are
    /// picked.
    static func figureSeed(optionId: String, dayKey: String, nonce: UInt64) -> UInt64 {
        let base = CanvasElement.makeSeed(optionId: optionId, dayKey: dayKey, index: 0)
        var mixed = base ^ (nonce &* 0x9E37_79B9_7F4A_7C15)
        mixed = (mixed ^ (mixed >> 29)) &* 0xBF58_476D_1CE4_E5B9
        return mixed ^ (mixed >> 32)
    }

    /// Shuffle and take a prefix rather than picking independently: ten tiles
    /// have to carry ten different colours, and independent picks collide.
    private static func distinctColours(
        count: Int,
        dayKey: String,
        nonce: UInt64,
        palette: [String]
    ) -> [String] {
        guard !palette.isEmpty else { return [AppColors.goldFallbackHex] }
        var generator = SplitMix64(
            seed: CanvasElement.makeSeed(optionId: "palette-colours", dayKey: dayKey, index: 0) ^ nonce
        )
        let shuffled = palette.shuffled(using: &generator)
        guard count <= shuffled.count else { return shuffled }
        return Array(shuffled.prefix(count))
    }
}
