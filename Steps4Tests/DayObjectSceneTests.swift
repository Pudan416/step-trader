import XCTest
@testable import Steps4

final class DayObjectSceneTests: XCTestCase {
    private func input(_ ids: [String]) -> DayObjectSceneInput {
        .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: ids,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
    }

    private func editorialInput(
        _ ids: [String],
        background: DayObjectEditorialBackground = .dark
    ) -> DayObjectSceneInput {
        .init(
            dayKey: "2026-09-04",
            identity: "day-objects-lab",
            eventIDs: ids,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            canvasCoverage: .fullCanvas,
            usesEditorialField: true,
            editorialBackground: background
        )
    }

    func testEditorialLabSceneFreezesApprovedContinuityCompositionInSceneRecipeV1() throws {
        let scene = DayObjectScene.make(input: editorialInput(["event-0", "event-1", "event-2"]))
        let recipe = try XCTUnwrap(scene.sceneRecipeV1)

        XCTAssertEqual(recipe.version, "scene-recipe-v1-lab-mvp")
        XCTAssertEqual(recipe.compositionSourceSeed, 5_211_325_511_773_202_532)
        XCTAssertEqual(recipe.actors.count, 3)
        XCTAssertEqual(recipe.actors[0].eventID, "event-0")
        XCTAssertEqual(recipe.actors[0].position.x, 0.21781887822291068, accuracy: 0.000_000_001)
        XCTAssertEqual(recipe.actors[0].position.y, 0.407402342486317, accuracy: 0.000_000_001)
        XCTAssertEqual(recipe.actors[0].diameter, 0.4529606876683834, accuracy: 0.000_000_001)
        XCTAssertEqual(recipe.background, .dark)
    }

    func testEditorialPrefixAddRemovePreservesRetainedRecipeActors() throws {
        let ids = (0..<6).map { "lab-event-\($0)" }
        let five = try XCTUnwrap(DayObjectScene.make(input: editorialInput(Array(ids.prefix(5)))).sceneRecipeV1)
        let six = try XCTUnwrap(DayObjectScene.make(input: editorialInput(ids)).sceneRecipeV1)

        for retained in five.actors {
            XCTAssertEqual(six.actor(retained.eventID), retained)
        }

        let restored = try XCTUnwrap(
            DayObjectScene.make(input: editorialInput(Array(ids.prefix(5)))).sceneRecipeV1
        )
        XCTAssertEqual(restored, five)
    }

    func testLegacyScenesRemainOutsideEditorialField() {
        let scene = DayObjectScene.make(input: input(["walk"]))
        XCTAssertNil(scene.sceneRecipeV1)
        XCTAssertFalse(scene.input.usesEditorialField)
    }

    func testEditorialPreviewCatalogPairsSixSoftMaterialsWithTwoPlacementModes() {
        let specs = DayObjectEditorialPreviewCatalog.all

        XCTAssertEqual(specs.count, 12)
        XCTAssertEqual(Set(specs.map(\.paletteCategory)), Set(ModernPaletteCategory.allCases))
        XCTAssertEqual(Set(specs.map(\.material)), [
            .solid,
            .translucentSolid,
            .softMist,
            .wideGradient,
            .softOutline,
            .hairlineOutline,
        ])
        XCTAssertEqual(Set(specs.map(\.placement)), [.depthField, .equalMedium])
        XCTAssertEqual(Set(specs.map(\.index)).count, 12)
        for material in DayObjectEditorialPreviewMaterial.allCases {
            XCTAssertEqual(specs.filter { $0.material == material }.map(\.placement), [
                .depthField,
                .equalMedium,
            ])
        }
        XCTAssertEqual(specs.first?.paletteCategory, .pastel)
        XCTAssertEqual(specs.first?.material, .solid)
        XCTAssertEqual(specs.first?.placement, .depthField)
        XCTAssertEqual(specs.last?.paletteCategory, .vintage)
        XCTAssertEqual(specs.last?.material, .hairlineOutline)
        XCTAssertEqual(specs.last?.placement, .equalMedium)
    }

    func testEditorialPreviewScenesUseUniqueTenActorProductCompositions() throws {
        var fingerprints = Set<String>()

        for spec in DayObjectEditorialPreviewCatalog.all {
            let scene = DayObjectScene.make(input: editorialPreviewInput(spec))
            let recipe = try XCTUnwrap(scene.sceneRecipeV1)
            XCTAssertEqual(recipe.actors.count, 10)
            XCTAssertTrue(recipe.actors.allSatisfy { $0.eventID.hasPrefix("preview-event-") })
            fingerprints.insert(recipe.actors.map {
                String(format: "%.8f:%.8f:%.8f", $0.position.x, $0.position.y, $0.diameter)
            }.joined(separator: "|"))
        }

        XCTAssertEqual(fingerprints.count, 12)
    }

    func testEditorialPreviewUsesCatalogPaletteMeshAndRequestedMaterial() throws {
        let expectedFamilies: [DayObjectEditorialPreviewMaterial: DayObjectEditorialMaterialFamily] = [
            .solid: .solid,
            .translucentSolid: .solid,
            .softMist: .mist,
            .wideGradient: .gradient,
            .softOutline: .outline,
            .hairlineOutline: .outline,
        ]

        for material in DayObjectEditorialPreviewMaterial.allCases {
            let spec = try XCTUnwrap(
                DayObjectEditorialPreviewCatalog.all.first { $0.material == material }
            )
            let scene = DayObjectScene.make(input: editorialPreviewInput(spec))
            let recipe = try XCTUnwrap(scene.sceneRecipeV1)
            XCTAssertEqual(Set(recipe.actors.map(\.material.family)), [expectedFamilies[material]!])
            XCTAssertEqual(scene.meshGradientStyle.colors.count, 4)
            XCTAssertGreaterThan(Set(scene.meshGradientStyle.colors.map(String.init(describing:))).count, 1)
            XCTAssertGreaterThan(scene.meshGradientStyle.distortion, 0)
        }
    }

    func testWideGradientUsesOnePaletteColourAndAHueStableTonalVariation() throws {
        let specs = DayObjectEditorialPreviewCatalog.all.filter { $0.material == .wideGradient }
        XCTAssertEqual(specs.count, 2)

        for spec in specs {
            let scene = DayObjectScene.make(input: editorialPreviewInput(spec))
            let recipe = try XCTUnwrap(scene.sceneRecipeV1)
            let shift = scene.paletteSet.actorLightnessShift ?? 0
            let palettes = [
                scene.paletteSet.primaryObjects,
                scene.paletteSet.secondaryObjects,
            ].map { palette in
                palette.hexes.map {
                    DayObjectRGB(hex: $0)
                        .shiftingPerceptualLightness(by: shift)
                        .sRGB
                }
            }

            for actor in recipe.actors {
                let colours = actor.material.colors
                XCTAssertEqual(colours.count, 2)
                XCTAssertTrue(
                    palettes.contains { $0.contains(colours[0]) },
                    "The base colour must come directly from an approved object palette"
                )
                let source = try XCTUnwrap(palettes.first { $0.contains(colours[0]) })
                let base = DayObjectRGB(sRGB: colours[0]).perceptualOKLab
                let variation = DayObjectRGB(sRGB: colours[1]).perceptualOKLab
                let chromaDelta = hypot(
                    Double(base.y - variation.y),
                    Double(base.z - variation.z)
                )
                let lightnessDelta = abs(Double(base.x - variation.x))

                XCTAssertLessThanOrEqual(chromaDelta, 0.025)
                XCTAssertGreaterThanOrEqual(lightnessDelta, 0.045)
                XCTAssertLessThanOrEqual(lightnessDelta, 0.10)
                let cleanPaletteThreshold = source.map {
                    let lab = DayObjectRGB(sRGB: $0).perceptualOKLab
                    return hypot(Double(lab.y), Double(lab.z))
                }.sorted(by: >)[min(1, source.count - 1)]
                let baseChroma = hypot(Double(base.y), Double(base.z))
                XCTAssertGreaterThanOrEqual(baseChroma, cleanPaletteThreshold - 0.000_001)
                XCTAssertEqual(actor.material.baseOpacity, 1)
            }
        }
    }

    func testEditorialPreviewsUseBroadVisiblePaletteFieldsInTheBackground() throws {
        for spec in DayObjectEditorialPreviewCatalog.all {
            let scene = DayObjectScene.make(input: editorialPreviewInput(spec))
            let style = try XCTUnwrap(scene.sceneRecipeV1?.backgroundStyle)
            let uniqueColours = Set(style.colors.map { colour in
                "\(colour.x),\(colour.y),\(colour.z)"
            })

            XCTAssertGreaterThanOrEqual(uniqueColours.count, 3)
            XCTAssertGreaterThanOrEqual(
                style.distortion,
                0.24,
                "Lab previews need visible overlapping background fields"
            )
            XCTAssertLessThanOrEqual(
                style.scale,
                0.90,
                "Background fields must remain broad enough to read in one still"
            )
        }
    }

    func testDepthFieldPreviewMakesLargerActorsCloserAndMoreOutOfFocus() throws {
        let spec = try XCTUnwrap(
            DayObjectEditorialPreviewCatalog.all.first { $0.placement == .depthField }
        )
        let recipe = try XCTUnwrap(
            DayObjectScene.make(input: editorialPreviewInput(spec)).sceneRecipeV1
        )
        let actors = recipe.actors.sorted { $0.diameter < $1.diameter }

        XCTAssertGreaterThan(try XCTUnwrap(actors.last).diameter / actors[0].diameter, 5)
        for pair in zip(actors, actors.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.depth, pair.1.depth)
            XCTAssertLessThanOrEqual(pair.0.localBlur, pair.1.localBlur)
        }
        XCTAssertLessThan(actors[0].localBlur, 0.006)
        XCTAssertGreaterThan(try XCTUnwrap(actors.last).localBlur, 0.045)
    }

    func testEqualMediumPreviewKeepsScaleDepthAndFocusInOneNarrowBand() throws {
        let spec = try XCTUnwrap(
            DayObjectEditorialPreviewCatalog.all.first { $0.placement == .equalMedium }
        )
        let recipe = try XCTUnwrap(
            DayObjectScene.make(input: editorialPreviewInput(spec)).sceneRecipeV1
        )
        let diameters = recipe.actors.map(\.diameter)
        let depths = recipe.actors.map(\.depth)
        let blurs = recipe.actors.map(\.localBlur)
        let minDiameter = try XCTUnwrap(diameters.min())
        let maxDiameter = try XCTUnwrap(diameters.max())
        let minDepth = try XCTUnwrap(depths.min())
        let maxDepth = try XCTUnwrap(depths.max())
        let minBlur = try XCTUnwrap(blurs.min())
        let maxBlur = try XCTUnwrap(blurs.max())
        let minX = try XCTUnwrap(recipe.actors.map { $0.position.x }.min())
        let maxX = try XCTUnwrap(recipe.actors.map { $0.position.x }.max())
        let minY = try XCTUnwrap(recipe.actors.map { $0.position.y }.min())
        let maxY = try XCTUnwrap(recipe.actors.map { $0.position.y }.max())

        XCTAssertLessThanOrEqual(maxDiameter - minDiameter, 0.015)
        XCTAssertLessThanOrEqual(maxDepth - minDepth, 0.03)
        XCTAssertLessThanOrEqual(maxBlur - minBlur, 0.003)
        XCTAssertGreaterThan(maxX - minX, 0.55)
        XCTAssertGreaterThan(maxY - minY, 0.55)
    }

    func testHairlineOutlineIsStructurallyDistinctFromSoftOutline() throws {
        let hairlineSpec = try XCTUnwrap(
            DayObjectEditorialPreviewCatalog.all.first { $0.material == .hairlineOutline }
        )
        let softSpec = try XCTUnwrap(
            DayObjectEditorialPreviewCatalog.all.first { $0.material == .softOutline }
        )
        let hairline = try XCTUnwrap(
            DayObjectScene.make(input: editorialPreviewInput(hairlineSpec)).sceneRecipeV1?.actors.first?.material
        )
        let soft = try XCTUnwrap(
            DayObjectScene.make(input: editorialPreviewInput(softSpec)).sceneRecipeV1?.actors.first?.material
        )

        XCTAssertEqual(hairline.family, .outline)
        XCTAssertEqual(hairline.colors.count, 1)
        XCTAssertTrue(hairline.fields.isEmpty)
        XCTAssertLessThan(hairline.contourWidth, 0.012)
        XCTAssertGreaterThan(soft.contourWidth, hairline.contourWidth * 5)
    }

    func testSolidPreviewRequestsNoLightingOrInternalColorField() throws {
        let spec = try XCTUnwrap(
            DayObjectEditorialPreviewCatalog.all.first { $0.material == .solid }
        )
        let material = try XCTUnwrap(
            DayObjectScene.make(input: editorialPreviewInput(spec)).sceneRecipeV1?.actors.first?.material
        )

        XCTAssertEqual(material.family, .solid)
        XCTAssertEqual(material.colors.count, 1)
        XCTAssertTrue(material.fields.isEmpty)
        XCTAssertEqual(material.gpuAppearance.light.x, 0)
    }

    func testEditorialPreviewDisablesGlobalBlurSoDepthControlsFocus() {
        XCTAssertEqual(
            DayObjectsLabView.resolvedVisualClarity(0.55, isEditorialPreview: true),
            1
        )
        XCTAssertEqual(
            DayObjectsLabView.resolvedVisualClarity(0.55, isEditorialPreview: false),
            0.55
        )
    }

    func testAddingEventPreservesExistingActors() {
        let before = DayObjectScene.make(input: input(["walk", "sleep"]))
        let after = DayObjectScene.make(input: input(["walk", "sleep", "read"]))
        let retained = after.actors.filter { before.actorIDs.contains($0.id) }
        XCTAssertEqual(retained, before.actors)
    }

    func testSceneUsesOnePresetAndOneMaterialForTheWholeDay() {
        let scene = DayObjectScene.make(input: input((0..<10).map { "event-\($0)" }))
        XCTAssertEqual(scene.motionPlan.configuration, scene.choreographyConfiguration)
        XCTAssertEqual(Set(scene.actors.map { $0.appearance.material }), [scene.visualLanguage.family])
        XCTAssertEqual(Set(scene.actors.map { $0.choreographySlot.ordinal }).count,
                       Set(scene.actors.map { $0.id }).count)
    }

    func testAddingAnEventDoesNotRerollRetainedActors() {
        let five = DayObjectScene.make(input: input((0..<5).map { "event-\($0)" }))
        let six = DayObjectScene.make(input: input((0..<6).map { "event-\($0)" }))
        for actor in five.actors {
            let retained = six.actors.first { $0.id == actor.id }!
            XCTAssertEqual(retained.appearance, actor.appearance)
            XCTAssertEqual(retained.route, actor.route)
            XCTAssertEqual(retained.choreographySlot, actor.choreographySlot)
        }
    }

    func testArbitraryActorAppearanceIsIndependentOfPreferredPrimaryAddRemoveAndOrder() throws {
        let eventIDs = [
            "alpha-forest", "beta-river", "gamma-stone", "delta-cloud",
            "epsilon-lantern", "zeta-window", "eta-orchard", "theta-bridge",
        ]

        for retainedID in eventIDs {
            let alone = DayObjectScene.make(input: input([retainedID]))
            let expected = try XCTUnwrap(alone.actors.first)
            for addedID in eventIDs where addedID != retainedID {
                for order in [[addedID, retainedID], [retainedID, addedID]] {
                    let expanded = DayObjectScene.make(input: input(order))
                    let retained = try XCTUnwrap(
                        expanded.actors.first { $0.eventID == retainedID }
                    )
                    XCTAssertEqual(retained.appearance, expected.appearance)
                    XCTAssertEqual(retained.choreographySlot, expected.choreographySlot)
                    XCTAssertEqual(retained.route, expected.route)
                }
            }
        }
    }

    func testEventOrderDoesNotChangeActors() {
        let a = DayObjectScene.make(input: input(["walk", "sleep"]))
        let b = DayObjectScene.make(input: input(["sleep", "walk"]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: a.actors.map { ($0.id, $0) }),
            Dictionary(uniqueKeysWithValues: b.actors.map { ($0.id, $0) })
        )
    }

    func testDuplicateEventsAreDeduplicatedAndBudgeted() {
        let uniqueIDs = (0..<80).map { "event-\($0)" }
        let duplicateIDs = uniqueIDs.flatMap { [$0, $0] }
        let uniqueScene = DayObjectScene.make(input: input(uniqueIDs))
        let duplicateScene = DayObjectScene.make(input: input(duplicateIDs))

        XCTAssertEqual(duplicateScene.actors, uniqueScene.actors)
        XCTAssertEqual(duplicateScene.actors.count, 10)
        XCTAssertEqual(DayObjectScene.maxActors, 10)
        XCTAssertEqual(Set(duplicateScene.actorIDs).count, duplicateScene.actors.count)
    }

    func testSceneOwnsThreeDailyPalettesAndOneAppearancePerActor() {
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: (0..<10).map { "event-\($0)" },
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            paletteCategories: [.pastel, .cold]
        ))

        XCTAssertEqual(
            Set([
                scene.paletteSet.background.code,
                scene.paletteSet.primaryObjects.code,
                scene.paletteSet.secondaryObjects.code,
            ]).count,
            3
        )
        XCTAssertEqual(scene.visualLanguage.paletteSet, scene.paletteSet)
        XCTAssertEqual(
            scene.palette.colors,
            scene.paletteSet.background.hexes.map(DayObjectRGB.init(hex:))
        )
        XCTAssertEqual(scene.actors.count, 10)
        XCTAssertEqual(
            scene.actors.map(\.appearance),
            scene.actors.compactMap {
                scene.visualLanguage.appearances(
                    eventIDs: scene.input.eventIDs,
                    rootSeed: scene.rootSeed
                )[$0.eventID]
            }
        )
        XCTAssertTrue(scene.actors.allSatisfy { $0.id.memberIndex == 0 })
    }

    func testOneUniqueHappeningProducesOneStableOrb() {
        let scene = DayObjectScene.make(input: input(["walk", "walk", "sleep", "read"]))

        XCTAssertEqual(scene.actors.map(\.eventID), ["walk", "sleep", "read"])
        XCTAssertEqual(scene.composition.flockSize, 1)
    }

    func testEmptyEventIDIsDeduplicatedWithoutDisplacingLaterEvents() {
        let withDuplicate = DayObjectScene.make(input: input(["", "", "walk"]))
        let withSingle = DayObjectScene.make(input: input(["", "walk"]))

        XCTAssertEqual(withDuplicate.actors, withSingle.actors)
        XCTAssertTrue(withDuplicate.actorIDs.contains { $0.eventID.isEmpty })
        XCTAssertTrue(withDuplicate.actorIDs.contains { $0.eventID == "walk" })
    }

    func testZeroEventsProduceStableDailySceneWithoutActors() {
        let first = DayObjectScene.make(input: input([]))
        let second = DayObjectScene.make(input: input([]))

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.actors.isEmpty)
        XCTAssertTrue(first.actorIDs.isEmpty)
        XCTAssertFalse(first.meshGradientStyle.colors.isEmpty)
    }

    func testRemovingAndReaddingEventRestoresIdenticalActors() {
        let original = DayObjectScene.make(input: input(["walk", "sleep", "read"]))
        let withoutSleep = DayObjectScene.make(input: input(["walk", "read"]))
        let restored = DayObjectScene.make(input: input(["walk", "sleep", "read"]))

        XCTAssertEqual(restored, original)
        XCTAssertEqual(
            withoutSleep.actors,
            original.actors.filter { $0.eventID != "sleep" }
        )
    }

    func testSceneInputDefaultsToLabExclusionAndPreservesCustomRegion() {
        let defaultInput = input(["walk"])
        XCTAssertEqual(defaultInput.uiExclusionRegion, .dayObjectsLabControls)
        XCTAssertEqual(DayObjectsLabView.uiExclusionRegion, .dayObjectsLabControls)

        let custom = DayObjectNormalizedRect(
            minX: 0.72,
            minY: 0.05,
            maxX: 0.98,
            maxY: 0.46
        )
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: ["walk"],
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            uiExclusionRegion: custom
        ))
        XCTAssertEqual(scene.input.uiExclusionRegion, custom)
        XCTAssertEqual(scene.compositionPlan.uiExclusionRegion, custom)
    }

    func testLabUsesFullCanvasCoverageInsteadOfBottomControlExclusion() {
        XCTAssertEqual(DayObjectsLabView.canvasCoverage, .fullCanvas)
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-08-20",
            identity: "day-objects-lab",
            eventIDs: (0..<10).map { "event-\($0)" },
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            canvasCoverage: .fullCanvas
        ))

        XCTAssertEqual(scene.input.canvasCoverage, .fullCanvas)
        XCTAssertEqual(scene.compositionPlan.uiExclusionRegion.area, 0)
    }

    func testEditorialLabMixedModeUsesAllSixApprovedObjectFormatsAtTenHappenings() throws {
        let recipe = try XCTUnwrap(
            DayObjectScene.make(
                input: editorialLabInput(
                    eventIDs: (0..<10).map { "lab-event-\($0)" },
                    materialMode: .mixed
                )
            ).sceneRecipeV1
        )
        let materials = recipe.actors.map(\.material)

        XCTAssertEqual(recipe.editorialLabConfiguration?.materialMode, .mixed)
        XCTAssertTrue(materials.contains { $0.family == .solid && $0.baseOpacity == 1 })
        XCTAssertTrue(materials.contains { $0.family == .solid && $0.baseOpacity < 0.7 })
        XCTAssertTrue(materials.contains { $0.family == .mist })
        XCTAssertTrue(materials.contains { $0.family == .gradient })
        XCTAssertTrue(materials.contains {
            $0.family == .outline && $0.contourWidth >= 0.05
        })
        XCTAssertTrue(materials.contains {
            $0.family == .outline && $0.contourWidth < 0.012
        })

        let outlineSlots = recipe.actors.filter {
            $0.material.family == .outline
        }.map(\.slot)
        XCTAssertGreaterThanOrEqual(outlineSlots.count, 3)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(outlineSlots.max()) - XCTUnwrap(outlineSlots.min()),
            5,
            "Outline formats must be distributed across the field, not hidden in one overlap cluster"
        )
    }

    func testEditorialLabSingleMaterialModesRemainAvailable() throws {
        for mode in DayObjectEditorialLabMaterialMode.allCases where mode != .mixed {
            let recipe = try XCTUnwrap(
                DayObjectScene.make(
                    input: editorialLabInput(
                        eventIDs: (0..<4).map { "lab-event-\($0)" },
                        materialMode: mode
                    )
                ).sceneRecipeV1
            )

            XCTAssertEqual(recipe.editorialLabConfiguration?.materialMode, mode)
            XCTAssertEqual(recipe.actors.count, 4)
            XCTAssertTrue(recipe.actors.allSatisfy {
                material($0.material, matches: mode)
            })
        }
    }

    func testEditorialLabMixedMaterialIdentitySurvivesActorRemovalAndReinsertion() throws {
        let tenIDs = (0..<10).map { "lab-event-\($0)" }
        let fullRecipe = try XCTUnwrap(
            DayObjectScene.make(
                input: editorialLabInput(eventIDs: tenIDs, materialMode: .mixed)
            ).sceneRecipeV1
        )
        let reducedRecipe = try XCTUnwrap(
            DayObjectScene.make(
                input: editorialLabInput(
                    eventIDs: Array(tenIDs.prefix(5)),
                    materialMode: .mixed
                )
            ).sceneRecipeV1
        )

        for eventID in tenIDs.prefix(5) {
            XCTAssertEqual(
                fullRecipe.actor(eventID)?.material,
                reducedRecipe.actor(eventID)?.material,
                "Mixed material selection must be a stable function of actor identity"
            )
        }
    }

    func testEditorialLabPlacementModesPreserveApprovedDepthBehaviors() throws {
        let eventIDs = (0..<10).map { "lab-event-\($0)" }
        let depthActors = try XCTUnwrap(
            DayObjectScene.make(
                input: editorialLabInput(
                    eventIDs: eventIDs,
                    materialMode: .mixed,
                    placement: .depthField
                )
            ).sceneRecipeV1
        ).actors
        let equalActors = try XCTUnwrap(
            DayObjectScene.make(
                input: editorialLabInput(
                    eventIDs: eventIDs,
                    materialMode: .mixed,
                    placement: .equalMedium
                )
            ).sceneRecipeV1
        ).actors

        let depthDiameters = depthActors.map(\.diameter)
        let equalDiameters = equalActors.map(\.diameter)
        XCTAssertGreaterThan(
            try XCTUnwrap(depthDiameters.max()) / XCTUnwrap(depthDiameters.min()),
            5
        )
        XCTAssertLessThan(
            try XCTUnwrap(equalDiameters.max()) - XCTUnwrap(equalDiameters.min()),
            0.015
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(depthActors.max(by: { $0.diameter < $1.diameter }))?.localBlur ?? 0,
            try XCTUnwrap(depthActors.min(by: { $0.diameter < $1.diameter }))?.localBlur ?? 0
        )
    }

    func testGenerativeDNASchedulesCoherentVariedReproducibleDays() {
        let dayKeys = (1...28).map { String(format: "2026-09-%02d", $0) }
        let forward = dayKeys.map {
            DayObjectArtDirectionScheduler.make(
                dayKey: $0,
                identity: "day-objects-lab"
            )
        }
        let reverseByDay = Dictionary(uniqueKeysWithValues: dayKeys.reversed().map {
            (
                $0,
                DayObjectArtDirectionScheduler.make(
                    dayKey: $0,
                    identity: "day-objects-lab"
                )
            )
        })

        XCTAssertEqual(
            forward,
            dayKeys.compactMap { reverseByDay[$0] },
            "request order must not become mutable generation history"
        )
        for (previous, current) in zip(forward, forward.dropFirst()) {
            XCTAssertNotEqual(
                previous.fingerprint.primaryFamily,
                current.fingerprint.primaryFamily,
                "adjacent dates need a visibly different primary process"
            )
            XCTAssertGreaterThanOrEqual(
                previous.fingerprint.distance(to: current.fingerprint),
                2,
                "palette-only variation is not a new daily art direction"
            )
        }
        for windowStart in 0...(forward.count - 7) {
            let combinations = forward[windowStart..<(windowStart + 7)]
                .map(\.fingerprint.coreCombination)
            XCTAssertEqual(
                Set(combinations).count,
                combinations.count,
                "core composition/geometry/material combinations cannot repeat in seven days"
            )
        }
    }

    func testActorDNAResolutionIsIndependentOfCountAndOrder() {
        let direction = DayObjectArtDirectionScheduler.make(
            dayKey: "2026-09-05",
            identity: "day-objects-lab"
        )
        let ids = (0..<10).map { "lab-event-\($0)" }
        let forward = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, direction.resolution(eventID: $0))
        })
        let reverse = Dictionary(uniqueKeysWithValues: ids.reversed().map {
            ($0, direction.resolution(eventID: $0))
        })

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(
            direction.resolution(eventID: ids[4]),
            direction.resolution(eventID: ids[4])
        )
    }

    private func editorialPreviewInput(
        _ spec: DayObjectEditorialPreviewSpec
    ) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: spec.dayKey,
            identity: "day-objects-palette-atlas",
            eventIDs: (0..<10).map { "preview-event-\($0)" },
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: true,
            canvasCoverage: .fullCanvas,
            paletteCategories: [spec.paletteCategory],
            usesEditorialField: true,
            editorialPreview: spec
        )
    }

    private func editorialLabInput(
        eventIDs: [String],
        materialMode: DayObjectEditorialLabMaterialMode,
        placement: DayObjectEditorialPreviewPlacement = .depthField
    ) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "2026-09-05",
            identity: "day-objects-lab",
            eventIDs: eventIDs,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false,
            canvasCoverage: .fullCanvas,
            paletteCategories: [.pastel],
            usesEditorialField: true,
            editorialLabConfiguration: .init(
                materialMode: materialMode,
                placement: placement
            )
        )
    }

    private func material(
        _ material: DayObjectEditorialMaterialV1,
        matches mode: DayObjectEditorialLabMaterialMode
    ) -> Bool {
        switch mode {
        case .mixed:
            true
        case .solid:
            material.family == .solid && material.baseOpacity == 1
        case .translucentSolid:
            material.family == .solid && material.baseOpacity < 0.7
        case .softMist:
            material.family == .mist
        case .wideGradient:
            material.family == .gradient
        case .softOutline:
            material.family == .outline && material.contourWidth >= 0.05
        case .hairlineOutline:
            material.family == .outline && material.contourWidth < 0.012
        }
    }

}

final class DayObjectCompositionTests: XCTestCase {
    func testDayObjectsOnlyExposeCircleDerivedShapes() {
        XCTAssertEqual(DayObjectShape.allCases, [.sphere, .ellipse, .lens, .softBlob])
    }

    func testRestingSizeBandsUseApprovedDiameterRanges() {
        XCTAssertEqual(DayObjectSizeBand.focal.diameterRange, 0.28...0.42)
        XCTAssertEqual(DayObjectSizeBand.support.diameterRange, 0.15...0.26)
        XCTAssertEqual(DayObjectSizeBand.satellite.diameterRange, 0.065...0.13)
    }

    func testOrbElongationNeverProducesThinLegacyParticles() {
        XCTAssertEqual(DayObjectElongation.allCases, [.round, .oval])
        XCTAssertEqual(DayObjectElongation.round.aspectRange, 0.92...1.0)
        XCTAssertEqual(DayObjectElongation.oval.aspectRange, 0.72...0.90)
    }

    func testAllShapeFamiliesAreReachableAcrossBroadDailySample() {
        var reached = Set<DayObjectShape>()

        for index in 0..<2_048 {
            reached.insert(DayObjectComposition.forDay(
                dayKey: "shape-reachability-\(index)",
                identity: "tester"
            ).shape)
        }

        XCTAssertEqual(reached, Set(DayObjectShape.allCases))
    }

    func testProductionSphereAndAppearanceColorCountNumericValuesMatchMetalShaderABI() {
        let expectedShapes: [DayObjectShape: UInt32] = [
            .sphere: 0,
        ]
        let expectedColorCounts: Set<UInt32> = [1, 2, 3]
        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
        var observedShapes = [DayObjectShape: UInt32]()
        var observedColorCounts = Set<UInt32>()

        for index in 0..<2_048
        where observedShapes.count < expectedShapes.count
            || observedColorCounts.count < expectedColorCounts.count {
            let scene = DayObjectScene.make(input: .init(
                dayKey: "shape-abi-\(index)",
                identity: "tester",
                eventIDs: ["event"],
                motionEnergy: 0.55,
                visualClarity: 0.55,
                reduceMotion: false
            ))
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: environment,
                elapsed: 0,
                insertions: [:]
            )
            guard let actor = scene.actors.first,
                  let renderActor = frame.actors.first else {
                XCTFail("A one-event scene must provide an actor")
                return
            }
            observedShapes[actor.appearance.shape] = renderActor.gpuActor.shape
            observedColorCounts.insert(renderActor.gpuAppearance.metadata.y)
        }

        XCTAssertEqual(observedShapes, expectedShapes)
        XCTAssertEqual(observedColorCounts, expectedColorCounts)
    }

    func testOrbShapeNumericValuesAreExplicitAndStable() {
        XCTAssertEqual(DayObjectShape.sphere.numericValue, 0)
        XCTAssertEqual(DayObjectShape.ellipse.numericValue, 1)
        XCTAssertEqual(DayObjectShape.lens.numericValue, 2)
        XCTAssertEqual(DayObjectShape.softBlob.numericValue, 3)
    }
}
