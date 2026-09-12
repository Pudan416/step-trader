import Foundation

/// Restyles every decorative element on a canvas in one pass.
///
/// Remix is a request for a different-looking day, not a different day. Shape,
/// silhouette seed, colours, size and motion personality are re-rolled inside
/// the day's own composition; identity, arrangement and count are carried
/// through untouched, so the canvas still records the same happenings in the
/// same places.
enum CanvasRemix {
    /// Unified Remix rethrows the arrangement as well as its appearance.
    /// The older overload remains the single-element-era restyling contract.
    static func remixed(
        _ elements: [CanvasElement],
        composition: DayComposition,
        remixSeed: UInt64,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        at date: Date = .now
    ) -> [CanvasElement] {
        var remixed: [CanvasElement] = []
        let choices = allowedShapes.isEmpty ? [.circle] : allowedShapes
        for (rank, element) in elements.enumerated() {
            let identitySeed = CanvasElement.makeSeed(
                optionId: element.id.uuidString.lowercased(), dayKey: String(remixSeed), index: rank
            )
            var shape = SeededRNG.derived(from: identitySeed, domain: "shape")
            let shapeType = choices[shape.nextInt(in: 0...(choices.count - 1))]
            var position = SeededRNG.derived(from: identitySeed, domain: "placement")
            let point = PoissonDiscSampler.nextPoint(
                existing: remixed.map(\.basePosition), bounds: CanvasElement.spawnBounds,
                minDistance: CanvasElement.spawnMinDistance(existingCount: rank),
                weight: { composition.archetype.weight(at: $0) }, using: &position
            )
            var size = SeededRNG.derived(from: identitySeed, domain: "size")
            let scaledSize = size.nextDouble(in: CanvasElement.baseSizeRange(for: shapeType))
                * composition.archetype.sizeMultiplier(rank: rank, count: DayComposition.nominalDayCount)
            var color = SeededRNG.derived(from: identitySeed, domain: "color")
            var motion = SeededRNG.derived(from: identitySeed, domain: "motion")
            remixed.append(CanvasElement(
                id: element.id, kind: shapeType == .rays ? .ray : .circle,
                optionId: element.optionId, label: element.label,
                hexColor: composition.color(forRank: rank),
                hexColor2: color.nextDouble() < 0.6 ? composition.color(forRank: rank + 1) : nil,
                size: min(0.48, max(0.04, scaledSize)), basePosition: point,
                phaseOffset: motion.nextDouble(in: 0...(2 * .pi)),
                driftSpeed: motion.nextDouble(in: 0.08...0.2),
                driftAmplitude: motion.nextCGFloat(in: 0.01...0.03),
                pulseFrequency: motion.nextDouble(in: shapeType == .rays ? 0.3...0.8 : 0.08...0.2),
                pulseAmplitude: motion.nextCGFloat(in: 0.01...0.03),
                rotationSpeed: motion.nextDouble(in: 3...10),
                opacity: motion.nextDouble(in: composition.opacityRange(forRank: rank)),
                createdAt: element.createdAt, assetVariant: element.assetVariant,
                shapeSeed: identitySeed, activityCount: element.activityCount,
                editorialColorVariant: element.editorialColorVariant,
                lastEditedAt: date, frozenShapeType: shapeType
            ))
        }
        return remixed
    }

    /// - Parameters:
    ///   - elements: the canvas in arrival order. Order is preserved because
    ///     rank drives size, colour and texture.
    ///   - composition: the day's composition, so a remix cannot leave the
    ///     day's palette or archetype.
    ///   - allowedShapes: the user's allowed shape set.
    ///   - date: one instant stamped on the whole batch, so last-write-wins
    ///     merging treats the remix as a single edit.
    static func remixed(
        _ elements: [CanvasElement],
        composition: DayComposition,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        at date: Date = .now
    ) -> [CanvasElement] {
        elements.enumerated().map { rank, element in
            var copy = element
            copy.reroll(
                rank: rank,
                composition: composition,
                allowedShapes: allowedShapes,
                at: date
            )
            return copy
        }
    }
}
