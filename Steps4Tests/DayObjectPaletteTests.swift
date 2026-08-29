import Metal
import simd
import XCTest
@testable import Steps4

final class DayObjectPaletteTests: XCTestCase {
    func testDailyPaletteSetUsesThreeDistinctAllowedCatalogEntries() {
        let allowed: Set<ModernPaletteCategory> = [.pastel, .cold]

        for seed in UInt64(0)..<128 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: allowed
            )
            let palettes = [
                paletteSet.background,
                paletteSet.primaryObjects,
                paletteSet.secondaryObjects,
            ]

            XCTAssertEqual(Set(palettes.map(\.code)).count, 3, "seed=\(seed)")
            XCTAssertTrue(palettes.allSatisfy { !$0.categories.isDisjoint(with: allowed) })
            XCTAssertTrue(palettes.allSatisfy { $0.hexes.count == 4 })
            XCTAssertEqual(
                paletteSet,
                DayObjectPaletteSet.make(rootSeed: seed, categories: allowed),
                "seed=\(seed)"
            )
        }
    }

    func testDailyPaletteSetTreatsEmptyCategorySelectionAsAllCategories() {
        for seed in UInt64(0)..<32 {
            XCTAssertEqual(
                DayObjectPaletteSet.make(rootSeed: seed, categories: []),
                DayObjectPaletteSet.make(
                    rootSeed: seed,
                    categories: ModernPaletteSelection.all
                )
            )
        }
    }

    func testDailyPaletteSelectionStaysBoundedForTheFullCatalog() {
        let startedAt = ProcessInfo.processInfo.systemUptime

        for seed in UInt64(0)..<8 {
            _ = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
        }

        XCTAssertLessThan(
            ProcessInfo.processInfo.systemUptime - startedAt,
            2,
            "eight daily selections must not score every pair in the 340-palette catalog"
        )
    }

    func testObjectPaletteAllocationIsActorLocalAndUsesOneToThreeColors() throws {
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 44,
            categories: [.pastel, .cold, .warm]
        )

        for count in 1...10 {
            let eventIDs = (0..<count).map { "event-\($0)" }
            let assignments = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: 44,
                paletteSet: paletteSet
            )
            let values = Array(assignments.values)

            XCTAssertEqual(assignments.count, count)
            XCTAssertTrue(values.allSatisfy { (1...3).contains($0.colors.count) })
            XCTAssertTrue(values.allSatisfy { $0.colors.count == $0.sourceIndices.count })
            for eventID in eventIDs {
                let alone = DayObjectColorAllocator.assignments(
                    eventIDs: [eventID],
                    rootSeed: 44,
                    paletteSet: paletteSet
                )
                XCTAssertEqual(assignments[eventID], try XCTUnwrap(alone[eventID]))
            }
        }
    }

    func testMostDaysGiveMostObjectsTwoOrThreeColors() {
        var chromaticDays = 0

        for seed in UInt64(0)..<100 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let assignments = DayObjectColorAllocator.assignments(
                eventIDs: (0..<10).map { "event-\($0)" },
                rootSeed: seed,
                paletteSet: paletteSet
            )
            let multicolorCount = assignments.values.filter {
                $0.colors.count >= 2
            }.count
            if multicolorCount >= 7 {
                chromaticDays += 1
            }
        }

        XCTAssertGreaterThanOrEqual(chromaticDays, 75)
    }

    func testEveryGeneratedMaterialKeepsAReadableColorCore() {
        for seed in UInt64(0)..<256 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let language = DayObjectVisualLanguage.make(
                rootSeed: seed,
                paletteSet: paletteSet,
                choreography: DayObjectChoreographyConfiguration.make(seed: seed)
            )
            let appearances = language.appearances(
                eventIDs: (0..<10).map { "event-\($0)" },
                rootSeed: seed
            )

            for appearance in appearances.values {
                XCTAssertGreaterThanOrEqual(
                    appearance.bodyOpacity * appearance.centerOpacity,
                    0.24,
                    "seed=\(seed) material=\(appearance.material)"
                )
            }
        }
    }

    func testArbitraryEventIDsUseBothDailyPalettesAcrossARepresentativeSample() {
        let eventIDs = [
            "id-0x", "id-1x", "id-2x", "id-4x", "id-8x",
            "id-9x", "id-10x", "id-16x", "id-24x", "id-58x",
        ]
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 44,
            categories: [.pastel, .cold, .warm]
        )

        let assignments = DayObjectColorAllocator.assignments(
            eventIDs: eventIDs,
            rootSeed: 44,
            paletteSet: paletteSet
        )
        let values = eventIDs.compactMap { assignments[$0] }
        XCTAssertTrue(values.contains { $0.paletteSlot == .primary })
        XCTAssertTrue(values.contains { $0.paletteSlot == .secondary })
        XCTAssertTrue(values.allSatisfy { (1...3).contains($0.colors.count) })
    }

    func testAssignedObjectColorsRemainReadableAgainstTheRenderedBackgroundPalette() {
        for seed in UInt64(0)..<128 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let renderedBackground = DayObjectPalette.make(
                modernPalette: paletteSet.background
            )
            let backgroundColors = [renderedBackground.backgroundBase]
                + renderedBackground.backgroundFields
            let assignments = DayObjectColorAllocator.assignments(
                eventIDs: (0..<10).map { "uuid-\($0)-x" },
                rootSeed: seed,
                paletteSet: paletteSet
            )

            for assignment in assignments.values {
                for color in assignment.colors {
                    XCTAssertGreaterThanOrEqual(
                        backgroundColors.map {
                            contrastRatio(color.linearRGB, $0)
                        }.min() ?? 0,
                        1.35 - 0.000_001,
                        "seed=\(seed) color=\(color.sRGB) background=\(backgroundColors)"
                    )
                }
            }
        }
    }

    func testColorAssignmentsDoNotRerollWhenAnotherEventIsRemovedOrReordered() throws {
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 73,
            categories: [.pastel, .cold]
        )
        let full = DayObjectColorAllocator.assignments(
            eventIDs: ["walk", "sleep", "read"],
            rootSeed: 73,
            paletteSet: paletteSet
        )
        let removed = DayObjectColorAllocator.assignments(
            eventIDs: ["read", "walk"],
            rootSeed: 73,
            paletteSet: paletteSet
        )

        XCTAssertEqual(try XCTUnwrap(removed["walk"]), try XCTUnwrap(full["walk"]))
        XCTAssertEqual(try XCTUnwrap(removed["read"]), try XCTUnwrap(full["read"]))
    }

    func testArbitraryColorAssignmentsSurvivePreferredPrimaryAddRemoveAndReorder() throws {
        let eventIDs = [
            "alpha-forest", "beta-river", "gamma-stone", "delta-cloud",
            "epsilon-lantern", "zeta-window", "eta-orchard", "theta-bridge",
            "iota-moon", "kappa-harbor", "lambda-meadow", "mu-copper",
        ]

        for rootSeed in [UInt64(3), 44, 73, 991] {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: rootSeed,
                categories: [.pastel, .cold, .warm]
            )
            for retainedID in eventIDs {
                let alone = DayObjectColorAllocator.assignments(
                    eventIDs: [retainedID], rootSeed: rootSeed, paletteSet: paletteSet
                )
                let expected = try XCTUnwrap(alone[retainedID])
                for addedID in eventIDs where addedID != retainedID {
                    let insertedBefore = DayObjectColorAllocator.assignments(
                        eventIDs: [addedID, retainedID],
                        rootSeed: rootSeed,
                        paletteSet: paletteSet
                    )
                    let insertedAfter = DayObjectColorAllocator.assignments(
                        eventIDs: [retainedID, addedID],
                        rootSeed: rootSeed,
                        paletteSet: paletteSet
                    )
                    XCTAssertEqual(
                        try XCTUnwrap(insertedBefore[retainedID]), expected,
                        "rootSeed=\(rootSeed) retained=\(retainedID) added=\(addedID)"
                    )
                    XCTAssertEqual(
                        try XCTUnwrap(insertedAfter[retainedID]), expected,
                        "rootSeed=\(rootSeed) retained=\(retainedID) added=\(addedID)"
                    )
                }
            }
        }
    }

    func testDailyVisualLanguageUsesOneFamilyAndOnlyRelatedMutations() {
        for seed in UInt64(0)..<128 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: [.pastel, .cold, .warm]
            )
            let language = DayObjectVisualLanguage.make(
                rootSeed: seed,
                paletteSet: paletteSet,
                choreography: DayObjectChoreographyConfiguration.make(seed: seed)
            )

            XCTAssertEqual(language.grainIntensity, 0.05)
            XCTAssertEqual(language.maximumElongation, 0.05)

            for count in 1...10 {
                let ids = (0..<count).map { "event-\($0)" }
                let appearances = language.appearances(
                    eventIDs: ids,
                    rootSeed: seed
                )
                XCTAssertTrue(appearances.values.allSatisfy {
                    $0.material == language.family
                        && $0.shape == language.baseShape
                        && abs($0.elongation - language.baseElongation)
                            <= language.maximumElongation + 0.000_001
                })
                XCTAssertLessThanOrEqual(
                    appearances.values.filter { $0.mutationRole == .accent }.count,
                    3,
                    "seed=\(seed) count=\(count)"
                )
                XCTAssertGreaterThanOrEqual(
                    appearances.values.filter { $0.mutationRole != .accent }.count,
                    max(1, Int(ceil(Double(count) * 0.7))),
                    "seed=\(seed) count=\(count)"
                )
            }
        }
    }

    func testDailyVisualLanguageReachesEveryHTMLCircleRecipe() {
        var reached = Set<DayObjectMaterialFamily>()

        for seed in UInt64(0)..<2_048 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            reached.insert(
                DayObjectVisualLanguage.make(
                    rootSeed: seed,
                    paletteSet: paletteSet,
                    choreography: DayObjectChoreographyConfiguration.make(seed: seed)
                ).family
            )
        }

        XCTAssertEqual(
            DayObjectMaterialFamily.allCases.count,
            9,
            "The Metal catalog must expose all nine distinct HTML recipes"
        )
        XCTAssertEqual(reached, Set(DayObjectMaterialFamily.allCases))
    }

    func testHTMLCircleRecipesEmitTheirStructuralParameters() {
        var checked = Set<DayObjectMaterialFamily>()

        for seed in UInt64(0)..<4_096 where checked.count < 9 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let language = DayObjectVisualLanguage.make(
                rootSeed: seed,
                paletteSet: paletteSet,
                choreography: DayObjectChoreographyConfiguration.make(seed: seed)
            )
            let appearances = language.appearances(
                eventIDs: (0..<10).map { "event-\($0)" },
                rootSeed: seed
            ).values

            XCTAssertTrue(appearances.allSatisfy { $0.material == language.family })
            XCTAssertTrue(appearances.allSatisfy {
                $0.colorStopLocations.x >= 0.18
                    && $0.colorStopLocations.x < $0.colorStopLocations.y
                    && $0.colorStopLocations.y <= 0.90
            })
            XCTAssertTrue(appearances.allSatisfy { $0.minimumOpacity >= 0.58 })

            if language.family == .outline {
                XCTAssertTrue(appearances.allSatisfy {
                    (1...3).contains($0.outlineCount)
                        && (0.012...0.075).contains($0.outlineWidth)
                        && (0.02...0.09).contains($0.outlineSpacing)
                        && (0.01...0.08).contains($0.outlineWobble)
                })
            } else {
                XCTAssertTrue(appearances.allSatisfy { $0.outlineCount == 0 })
            }

            if language.family == .counterform {
                XCTAssertTrue(appearances.allSatisfy {
                    (0.44...0.62).contains($0.counterformRadius)
                        && (0.01...0.08).contains($0.counterformSoftness)
                        && (0.14...0.34).contains($0.coronaWidth)
                        && (0.58...0.98).contains($0.coronaIntensity)
                })
            } else {
                XCTAssertTrue(appearances.allSatisfy { $0.counterformRadius == 0 })
            }

            checked.insert(language.family)
        }

        XCTAssertEqual(checked, Set(DayObjectMaterialFamily.allCases))
    }

    func testArbitraryEventIDsStillUseTheDailyFamilyAndMutationBudget() {
        let eventIDs = [
            "id-0x", "id-1x", "id-2x", "id-4x", "id-8x",
            "id-9x", "id-10x", "id-16x", "id-24x", "id-58x",
        ]
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 44,
            categories: [.pastel, .cold, .warm]
        )
        let language = DayObjectVisualLanguage.make(
            rootSeed: 44,
            paletteSet: paletteSet,
            choreography: DayObjectChoreographyConfiguration.make(seed: 44)
        )
        let appearances = language.appearances(eventIDs: eventIDs, rootSeed: 44)

        XCTAssertTrue(appearances.values.allSatisfy { $0.material == language.family })
        XCTAssertLessThanOrEqual(
            appearances.values.filter { $0.mutationRole == .accent }.count,
            3
        )
    }

    func testExistingAppearanceDoesNotChangeWhenLaterHappeningIsAdded() throws {
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 71,
            categories: [.pastel, .cold]
        )
        let language = DayObjectVisualLanguage.make(
            rootSeed: 71,
            paletteSet: paletteSet,
            choreography: DayObjectChoreographyConfiguration.make(seed: 71)
        )
        let one = language.appearances(eventIDs: ["walk"], rootSeed: 71)
        let ten = language.appearances(
            eventIDs: ["walk"] + (1..<10).map { "event-\($0)" },
            rootSeed: 71
        )

        XCTAssertEqual(try XCTUnwrap(one["walk"]), try XCTUnwrap(ten["walk"]))
    }

    func testPerEventAppearancesAreStableBoundedAndVisuallyReachable() {
        var reachedMaterials = Set<DayObjectMaterialFamily>()
        var reachedShapes = Set<DayObjectShape>()
        var reachedColorCounts = Set<Int>()
        var sawShiftedFocalCenter = false
        var sawTranslucentBody = false
        var sawInnerGlow = false
        var sawOuterGlow = false

        for seed in UInt64(0)..<128 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let language = DayObjectVisualLanguage.make(
                rootSeed: seed,
                paletteSet: paletteSet,
                choreography: DayObjectChoreographyConfiguration.make(seed: seed)
            )
            let ids = (0..<10).map { "event-\($0)" }
            let appearances = language.appearances(eventIDs: ids, rootSeed: seed)
            let repeated = language.appearances(eventIDs: ids, rootSeed: seed)

            XCTAssertEqual(appearances, repeated)
            for appearance in appearances.values {
                XCTAssertTrue((1...3).contains(appearance.colorAssignment.colors.count))
                XCTAssertTrue((0...0.18).contains(appearance.distortion))
                XCTAssertTrue((0.8...4).contains(appearance.distortionFrequency))
                XCTAssertTrue((0...1).contains(appearance.localDepthSoftness))
                XCTAssertTrue((0...1).contains(appearance.bodyOpacity))
                XCTAssertTrue((0...1).contains(appearance.centerOpacity))
                XCTAssertTrue((0...1).contains(appearance.rimOpacity))
                XCTAssertTrue((1...3).contains(appearance.layers.count))
                XCTAssertTrue(appearance.layers.allSatisfy {
                    simd_length($0.focalOffset) <= 0.68 + 0.000_001
                        && (0.42...1.18).contains($0.radius)
                        && (0.12...0.48).contains($0.softness)
                        && (0.18...1).contains($0.opacity)
                })
                if appearance.material == .livingGlass {
                    XCTAssertTrue((0.006...0.028).contains(appearance.refractionStrength))
                } else {
                    XCTAssertEqual(appearance.refractionStrength, 0)
                }

                reachedMaterials.insert(appearance.material)
                reachedShapes.insert(appearance.shape)
                reachedColorCounts.insert(appearance.colorAssignment.colors.count)
                sawShiftedFocalCenter = sawShiftedFocalCenter
                    || appearance.layers.contains { simd_length($0.focalOffset) > 0.2 }
                sawTranslucentBody = sawTranslucentBody || appearance.bodyOpacity < 0.75
                sawInnerGlow = sawInnerGlow || appearance.innerGlow > 0.3
                sawOuterGlow = sawOuterGlow || appearance.outerGlow > 0.15
            }
        }

        XCTAssertEqual(reachedMaterials, Set(DayObjectMaterialFamily.allCases))
        XCTAssertEqual(reachedShapes, Set([.sphere]))
        XCTAssertEqual(reachedColorCounts, [1, 2, 3])
        XCTAssertTrue(sawShiftedFocalCenter)
        XCTAssertTrue(sawTranslucentBody)
        XCTAssertTrue(sawInnerGlow)
        XCTAssertTrue(sawOuterGlow)
    }

    func testModernCatalogContainsUniqueFourColorPalettes() {
        let palettes = ModernPaletteCatalog.all

        XCTAssertEqual(palettes.count, 340)
        XCTAssertEqual(Set(palettes.map(\.code)).count, palettes.count)
        XCTAssertTrue(palettes.allSatisfy { $0.hexes.count == 4 })
        XCTAssertTrue(palettes.flatMap(\.hexes).allSatisfy {
            $0.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil
        })
    }

    func testModernCatalogCoversEverySelectableCategory() {
        for category in ModernPaletteCategory.allCases {
            XCTAssertFalse(
                ModernPaletteCatalog.palettes(matching: [category]).isEmpty,
                "missing \(category.rawValue) palettes"
            )
        }
    }

    func testModernCatalogTreatsNoFilterAsAllAndCombinesSelectedCategories() {
        XCTAssertEqual(
            ModernPaletteCatalog.palettes(matching: []),
            ModernPaletteCatalog.all
        )

        let selected: Set<ModernPaletteCategory> = [.pastel, .neon]
        let filtered = ModernPaletteCatalog.palettes(matching: selected)

        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.allSatisfy { !$0.categories.isDisjoint(with: selected) })
        XCTAssertTrue(filtered.contains { $0.categories.contains(.pastel) })
        XCTAssertTrue(filtered.contains { $0.categories.contains(.neon) })
    }

    func testDayObjectPaletteDrawsOnlyFromSelectedModernCategories() {
        let selected: Set<ModernPaletteCategory> = [.neon]
        let allowed = ModernPaletteCatalog.palettes(matching: selected).map { palette in
            palette.hexes.map { DayObjectRGB(hex: $0) }
        }

        for seed in UInt64(0)..<512 {
            let palette = DayObjectPalette.make(seed: seed, categories: selected)
            XCTAssertTrue(allowed.contains(palette.colors), "seed=\(seed)")
            XCTAssertEqual(
                palette,
                DayObjectPalette.make(seed: seed, categories: selected),
                "seed=\(seed)"
            )
        }
    }

    func testModernCategorySelectionDefaultsToAllAndRoundTripsASubset() {
        let all = Set(ModernPaletteCategory.allCases)
        XCTAssertEqual(ModernPaletteSelection.decode(""), all)
        XCTAssertEqual(ModernPaletteSelection.decode("unknown"), all)

        let subset: Set<ModernPaletteCategory> = [.pastel, .warm, .winter]
        XCTAssertEqual(
            ModernPaletteSelection.decode(ModernPaletteSelection.encode(subset)),
            subset
        )
        XCTAssertEqual(ModernPaletteSelection.encode(all), "")
    }

    func testModernCategorySelectionLeavesAllForOneTasteAndNeverBecomesEmpty() {
        let all = Set(ModernPaletteCategory.allCases)
        XCTAssertEqual(
            ModernPaletteSelection.toggling(.neon, in: all),
            [.neon]
        )
        XCTAssertEqual(
            ModernPaletteSelection.toggling(.neon, in: [.neon]),
            all
        )
    }

    func testSceneUsesPaletteCategoriesFromItsInput() {
        let selected: Set<ModernPaletteCategory> = [.winter]
        let input = DayObjectSceneInput(
            dayKey: "winter-scene",
            identity: "tester",
            eventIDs: ["walk"],
            motionEnergy: 0.5,
            visualClarity: 0.5,
            reduceMotion: false,
            paletteCategories: selected
        )
        let scene = DayObjectScene.make(input: input)
        let allowed = ModernPaletteCatalog.palettes(matching: selected).map { palette in
            palette.hexes.map { DayObjectRGB(hex: $0) }
        }

        XCTAssertTrue(allowed.contains(scene.palette.colors))
        XCTAssertEqual(scene.input.paletteCategories, selected)
    }

    func testDailyMeshReachesEveryArchetypeAndBothMotionDirections() {
        let bounds: [DayObjectMeshGradientArchetype:
            (ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>)] = [
            .drift: (0.08...0.24, -0.04...0.04, 0.045...0.085, 0.90...1.24),
            .orbit: (0.20...0.48, -0.42...0.42, 0.045...0.090, 0.92...1.26),
            .tide: (0.20...0.50, -0.08...0.08, 0.040...0.080, 0.88...1.22),
            .islands: (0.08...0.30, -0.12...0.12, 0.050...0.100, 0.96...1.34),
            .bloom: (0.14...0.38, -0.16...0.16, 0.035...0.070, 0.86...1.18),
        ]
        var archetypes = Set<DayObjectMeshGradientArchetype>()
        var directions = Set<Int>()

        for seed in UInt64(0)..<2_048 {
            let palette = DayObjectPalette.make(seed: seed)
            let style = DayObjectMeshGradientStyle.make(seed: seed, palette: palette)

            XCTAssertEqual(style, DayObjectMeshGradientStyle.make(seed: seed, palette: palette))
            archetypes.insert(style.archetype)
            directions.insert(Int(style.motionDirection))
            XCTAssertEqual(style.colors.count, 4, "seed=\(seed)")
            XCTAssertTrue((-0.18...0.18).contains(style.offset.x), "seed=\(seed)")
            XCTAssertTrue((-0.18...0.18).contains(style.offset.y), "seed=\(seed)")

            let (distortion, swirl, speed, scale) = bounds[style.archetype]!
            XCTAssertTrue(distortion.contains(style.distortion), "seed=\(seed) archetype=\(style.archetype)")
            XCTAssertTrue(swirl.contains(style.swirl), "seed=\(seed) archetype=\(style.archetype)")
            XCTAssertTrue(speed.contains(style.speed), "seed=\(seed) archetype=\(style.archetype)")
            XCTAssertTrue(scale.contains(style.scale), "seed=\(seed) archetype=\(style.archetype)")
        }

        XCTAssertEqual(archetypes, Set(DayObjectMeshGradientArchetype.allCases))
        XCTAssertEqual(directions, [-1, 1])
    }

    func testEveryMeshArchetypeProducesADistinctSmoothMovingField() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let vertexFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsFullscreenVertex"))
        let fragmentFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsMeshGradientFragment"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 320, drawableHeight: 240)
        let colors = ["bcecf6", "00aaff", "00f7ff", "ffd447"].map {
            DayObjectRGB(hex: $0).linearRGB
        }

        var firstFrames = [[UInt16]]()
        for archetype in DayObjectMeshGradientArchetype.allCases {
            let style = DayObjectMeshGradientStyle(
                colors: colors,
                archetype: archetype,
                offset: SIMD2(0.08, -0.06),
                distortion: 0.58,
                swirl: 0.31,
                speed: 0.11,
                scale: 1.05,
                phase: 1.25,
                motionDirection: -1
            )
            let first = try renderMeshGradient(
                style: style,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let later = try renderMeshGradient(
                style: style,
                elapsedTime: 20,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let oppositeStyle = DayObjectMeshGradientStyle(
                colors: colors,
                archetype: archetype,
                offset: SIMD2(0.08, -0.06),
                distortion: 0.58,
                swirl: 0.31,
                speed: 0.11,
                scale: 1.05,
                phase: 1.25,
                motionDirection: 1
            )
            let oppositeFirst = try renderMeshGradient(
                style: oppositeStyle,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let oppositeLater = try renderMeshGradient(
                style: oppositeStyle,
                elapsedTime: 20,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let metrics = broadFieldMetrics(
                pixels: first,
                width: plan.background.width,
                height: plan.background.height
            )
            XCTAssertLessThanOrEqual(metrics.centralRowReversals, 10, "\(archetype): \(metrics)")
            XCTAssertLessThan(metrics.strongAdjacentRatio, 0.04, "\(archetype): \(metrics)")
            XCTAssertGreaterThan(metrics.luminanceRange, 0.06, "\(archetype): \(metrics)")
            XCTAssertGreaterThan(
                meanAbsoluteRGBDifference(first, later),
                0.008,
                "\(archetype) must keep moving"
            )
            XCTAssertEqual(first, oppositeFirst, "direction must not reroll the daily topology")
            XCTAssertGreaterThan(
                meanAbsoluteRGBDifference(later, oppositeLater),
                0.008,
                "\(archetype) must visibly move in both directions"
            )
            firstFrames.append(first)
        }

        for lhs in firstFrames.indices {
            for rhs in firstFrames.indices where rhs > lhs {
                XCTAssertGreaterThan(
                    meanAbsoluteRGBDifference(firstFrames[lhs], firstFrames[rhs]),
                    0.012,
                    "archetypes \(lhs) and \(rhs) collapsed into the same topology"
                )
            }
        }
    }

    func testDailyMeshUsesOneCompleteFourColorModernPalette() {
        let applicationPalettes = ModernPaletteCatalog.all.map { palette in
            palette.hexes.map { DayObjectRGB(hex: $0).linearRGB }
        }
        var observedPaletteIndices = Set<Int>()

        for seed in UInt64(0)..<400 {
            let palette = DayObjectPalette.make(seed: seed)
            let mesh = DayObjectMeshGradientStyle.make(seed: seed, palette: palette)

            XCTAssertEqual(palette.colors.count, 4, "seed=\(seed)")
            XCTAssertEqual(mesh.colors.count, 4, "seed=\(seed)")
            guard let paletteIndex = applicationPalettes.firstIndex(of: mesh.colors) else {
                XCTFail("seed=\(seed) mixed colors from outside a complete application palette")
                continue
            }
            observedPaletteIndices.insert(paletteIndex)

            let uniforms = DayObjectsMeshGradientUniforms(
                style: mesh,
                resolution: SIMD2(320, 180),
                elapsedTime: 0
            )
            XCTAssertEqual(uniforms.colorCount, 4, "seed=\(seed)")
        }

        XCTAssertGreaterThan(observedPaletteIndices.count, 100)
    }

    func testMeshGradientUniformLayoutExactlyMatchesMetalABI() {
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.alignment, 16)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.size, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.stride, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color0), 0)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color1), 16)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color2), 32)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color3), 48)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color4), 64)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.resolution), 80)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.offset), 88)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.time), 96)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.distortion), 100)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.swirl), 104)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.scale), 108)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.phase), 112)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.colorCount), 116)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.archetype), 120)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.motionDirection), 124)
    }

    func testMeshGradientGPUProducesSmoothColorSpotsThatKeepMoving() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let vertexFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsFullscreenVertex"))
        let fragmentFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsMeshGradientFragment"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 320, drawableHeight: 240)
        let style = DayObjectMeshGradientStyle(
            colors: [
                DayObjectRGB(hex: "bcecf6").linearRGB,
                DayObjectRGB(hex: "00aaff").linearRGB,
                DayObjectRGB(hex: "00f7ff").linearRGB,
                DayObjectRGB(hex: "ffd447").linearRGB,
            ],
            distortion: 0.8,
            swirl: 0.35,
            speed: 0.1,
            scale: 1,
            phase: 1.25
        )

        let first = try renderMeshGradient(
            style: style,
            elapsedTime: 0,
            plan: plan,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        )
        let later = try renderMeshGradient(
            style: style,
            elapsedTime: 20,
            plan: plan,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        )
        let metrics = broadFieldMetrics(
            pixels: first,
            width: plan.background.width,
            height: plan.background.height
        )
        XCTAssertLessThanOrEqual(metrics.centralRowReversals, 8, "metrics=\(metrics)")
        XCTAssertLessThan(metrics.strongAdjacentRatio, 0.03, "metrics=\(metrics)")
        XCTAssertGreaterThan(metrics.luminanceRange, 0.08, "metrics=\(metrics)")
        XCTAssertGreaterThan(
            meanAbsoluteRGBDifference(first, later),
            0.01,
            "The background must keep moving even when no Day Objects actors exist"
        )
    }

    func testMeshGradientStyleUsesCuratedDailyParametersAndUnmutedDayColors() {
        let palette = DayObjectPalette.make(seed: 42)
        let style = DayObjectMeshGradientStyle.make(seed: 42, palette: palette)

        XCTAssertEqual(style, DayObjectMeshGradientStyle.make(seed: 42, palette: palette))
        XCTAssertEqual(style.colors, palette.colors.map(\.linearRGB))
        XCTAssertTrue((0..<(2 * Double.pi)).contains(style.phase))
        XCTAssertTrue([-1.0, 1.0].contains(style.motionDirection))

        let anotherDay = DayObjectMeshGradientStyle.make(seed: 43, palette: palette)
        XCTAssertNotEqual(anotherDay, style)
        XCTAssertEqual(anotherDay.colors, style.colors)
    }

    func testFigureRolesContrastWithBackgroundBase() {
        for seed in UInt64(0)..<400 {
            let palette = DayObjectPalette.make(seed: seed)
            XCTAssertGreaterThanOrEqual(palette.minimumFigureContrast, 1.35)
        }
    }

    func testSceneAndRendererUseTheDailyMeshGradientStyle() {
        let base = DayObjectScene.make(input: input(eventIDs: ["walk"]))
        let enriched = DayObjectScene.make(input: input(eventIDs: ["walk", "sleep", "read"]))

        XCTAssertEqual(
            base.meshGradientStyle,
            DayObjectMeshGradientStyle.make(seed: base.rootSeed, palette: base.palette)
        )
        XCTAssertEqual(enriched.meshGradientStyle, base.meshGradientStyle)

        let earlier = DayObjectsMeshGradientUniforms(
            scene: base,
            resolution: SIMD2(320, 180),
            elapsedTime: 10
        )
        let later = DayObjectsMeshGradientUniforms(
            scene: base,
            resolution: SIMD2(320, 180),
            elapsedTime: 12
        )
        XCTAssertEqual(
            later.time - earlier.time,
            Float(2 * base.meshGradientStyle.speed),
            accuracy: 0.0001
        )
        XCTAssertEqual(earlier.phase, Float(base.meshGradientStyle.phase), accuracy: 0.0001)
        XCTAssertEqual(
            earlier.offset,
            SIMD2(Float(base.meshGradientStyle.offset.x), Float(base.meshGradientStyle.offset.y))
        )
        XCTAssertEqual(earlier.archetype, base.meshGradientStyle.archetype.rawValue)
        XCTAssertEqual(earlier.motionDirection, Float(base.meshGradientStyle.motionDirection))
    }

    private func input(eventIDs: [String]) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: eventIDs,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
    }

    private func renderMeshGradient(
        style: DayObjectMeshGradientStyle,
        elapsedTime: TimeInterval,
        plan: DayObjectsRenderTargetPlan,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState
    ) throws -> [UInt16] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: plan.background.width,
            height: plan.background.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: renderPass))
        var uniforms = DayObjectsMeshGradientUniforms(
            style: style,
            resolution: SIMD2(Float(plan.background.width), Float(plan.background.height)),
            elapsedTime: elapsedTime
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsMeshGradientUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        var pixels = [UInt16](
            repeating: 0,
            count: plan.background.width * plan.background.height * 4
        )
        texture.getBytes(
            &pixels,
            bytesPerRow: plan.background.width * 4 * MemoryLayout<UInt16>.stride,
            from: MTLRegionMake2D(0, 0, plan.background.width, plan.background.height),
            mipmapLevel: 0
        )
        return pixels
    }

    private func meanAbsoluteRGBDifference(_ lhs: [UInt16], _ rhs: [UInt16]) -> Double {
        precondition(lhs.count == rhs.count)
        var total = 0.0
        var componentCount = 0
        for index in stride(from: 0, to: lhs.count, by: 4) {
            for component in 0..<3 {
                total += abs(
                    Double(Float(Float16(bitPattern: lhs[index + component])))
                        - Double(Float(Float16(bitPattern: rhs[index + component])))
                )
                componentCount += 1
            }
        }
        return total / Double(max(componentCount, 1))
    }

    private func broadFieldMetrics(
        pixels: [UInt16],
        width: Int,
        height: Int
    ) -> (centralRowReversals: Int, strongAdjacentRatio: Double, luminanceRange: Float) {
        func luminance(x: Int, y: Int) -> Float {
            let index = (y * width + x) * 4
            let red = Float(Float16(bitPattern: pixels[index]))
            let green = Float(Float16(bitPattern: pixels[index + 1]))
            let blue = Float(Float16(bitPattern: pixels[index + 2]))
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }

        let centerY = height / 2
        var reversals = 0
        var previousDirection = 0
        for x in 1..<width {
            let delta = luminance(x: x, y: centerY) - luminance(x: x - 1, y: centerY)
            let direction = delta > 0.002 ? 1 : (delta < -0.002 ? -1 : 0)
            if direction != 0 {
                if previousDirection != 0, direction != previousDirection {
                    reversals += 1
                }
                previousDirection = direction
            }
        }

        var strongAdjacent = 0
        var adjacentCount = 0
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        for y in 0..<height {
            for x in 0..<width {
                let value = luminance(x: x, y: y)
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                if x > 0 {
                    adjacentCount += 1
                    if abs(value - luminance(x: x - 1, y: y)) > 0.04 {
                        strongAdjacent += 1
                    }
                }
            }
        }

        return (
            centralRowReversals: reversals,
            strongAdjacentRatio: Double(strongAdjacent) / Double(max(adjacentCount, 1)),
            luminanceRange: maximum - minimum
        )
    }
}
