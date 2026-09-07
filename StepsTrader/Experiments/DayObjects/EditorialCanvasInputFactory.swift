import Foundation

struct EditorialCanvasMetrics: Equatable {
    let stepsProgress: Double
    let sleepProgress: Double
    let spentProgress: Double
}

struct EditorialCanvasRenderInput: Equatable {
    let sceneInput: DayObjectSceneInput
    let digitalImpact: DayObjectDigitalImpact
}

enum EditorialCanvasInputFactory {
    static func make(
        canvas: DayCanvas,
        metrics: EditorialCanvasMetrics,
        paletteCategories: Set<ModernPaletteCategory>
    ) -> EditorialCanvasRenderInput {
        let steps = clampedProgress(metrics.stepsProgress)
        let sleep = clampedProgress(metrics.sleepProgress)
        let spent = clampedProgress(metrics.spentProgress)

        let eventIDs = canvas.elements.map { $0.id.uuidString.lowercased() }
        let backgrounds = DayObjectEditorialBackground.allCases
        let backgroundSeed = canvas.remixSeed.map {
            var random = SeededRNG.derived(from: $0, domain: "editorial.background")
            return random.next()
        } ?? CanvasElement.makeSeed(
            optionId: "editorial-primary-background",
            dayKey: canvas.dayKey,
            index: 0
        )
        let background = backgrounds[Int(backgroundSeed % UInt64(backgrounds.count))]

        return EditorialCanvasRenderInput(
            sceneInput: DayObjectSceneInput(
                dayKey: canvas.dayKey,
                identity: canvas.remixSeed.map { "primary-canvas:remix:\($0)" } ?? "primary-canvas",
                eventIDs: eventIDs,
                motionEnergy: 0.25 + 0.75 * steps,
                visualClarity: 0.35 + 0.55 * sleep,
                canvasCoverage: .fullCanvas,
                paletteCategories: paletteCategories,
                usesEditorialField: true,
                editorialBackground: background,
                lowSleep: sleep < 0.55,
                editorialLabConfiguration: DayObjectEditorialLabConfiguration(
                    materialMode: .generativeDNA,
                    placement: .depthField
                ),
                actorColorVariants: Dictionary(
                    uniqueKeysWithValues: canvas.elements.compactMap { element in
                        element.editorialColorVariant.map {
                            (element.id.uuidString.lowercased(), $0)
                        }
                    }
                )
            ),
            digitalImpact: DayObjectDigitalImpact(
                spentColors: Int((spent * Double(DayObjectDigitalImpact.maximumSpentColors)).rounded())
            )
        )
    }

    private static func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
