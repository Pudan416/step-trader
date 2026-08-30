import Metal
import simd
import XCTest
@testable import Steps4

final class DayObjectPaletteTests: XCTestCase {
    func testProductionLabBackgroundDoesNotRepeatOnConsecutiveCalendarDays() {
        let filters: [(name: String, categories: Set<ModernPaletteCategory>)] = [
            ("all", ModernPaletteSelection.all),
            ("pastel-cold", [.pastel, .cold]),
            ("warm-fall", [.warm, .fall]),
            ("neon-summer", [.neon, .summer]),
        ]
        let dayKeys = isoDayKeys(from: 2026, through: 2035)

        for filter in filters {
            var previousBackgroundCode: String?
            for dayKey in dayKeys {
                let rootSeed = CanvasElement.makeSeed(
                    optionId: "dayObjects:day-objects-lab",
                    dayKey: dayKey,
                    index: 0
                )
                let background = DayObjectPaletteSet.backgroundPalette(
                    rootSeed: rootSeed,
                    categories: filter.categories,
                    dayKey: dayKey,
                    identity: "day-objects-lab"
                )

                XCTAssertNotEqual(
                    background.code,
                    previousBackgroundCode,
                    "filter=\(filter.name) day=\(dayKey)"
                )
                previousBackgroundCode = background.code
            }
        }
    }

    func testCalendarPaletteSelectionIsDeterministicAndDistinctWithinDay() {
        var consecutiveBackgrounds = [String]()
        for dayKey in [
            "2026-01-01", "2027-01-11", "2027-01-12",
            "2028-02-29", "2031-07-14", "2035-12-31",
        ] {
            let input = DayObjectSceneInput(
                dayKey: dayKey,
                identity: "day-objects-lab",
                eventIDs: [],
                motionEnergy: 0.55,
                visualClarity: 0.95,
                reduceMotion: false,
                paletteCategories: ModernPaletteSelection.all
            )
            let first = DayObjectScene.make(input: input).paletteSet
            let second = DayObjectScene.make(input: input).paletteSet

            XCTAssertEqual(first, second, dayKey)
            XCTAssertEqual(
                Set([
                    first.background.code,
                    first.primaryObjects.code,
                    first.secondaryObjects.code,
                ]).count,
                3,
                dayKey
            )
            if dayKey == "2027-01-11" || dayKey == "2027-01-12" {
                consecutiveBackgrounds.append(first.background.code)
            }
        }
        XCTAssertEqual(Set(consecutiveBackgrounds).count, 2)
    }

    func testNonCalendarFixturePaletteSelectionRemainsDeterministicAndDistinct() {
        let input = DayObjectSceneInput(
            dayKey: "render-fixture-palette-safety",
            identity: "day-objects-lab",
            eventIDs: [],
            motionEnergy: 0.55,
            visualClarity: 0.95,
            reduceMotion: false,
            paletteCategories: [.pastel, .cold]
        )

        let first = DayObjectScene.make(input: input).paletteSet
        let second = DayObjectScene.make(input: input).paletteSet

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            Set([
                first.background.code,
                first.primaryObjects.code,
                first.secondaryObjects.code,
            ]).count,
            3
        )
    }

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

    func testCanonicalGalleryUUIDCorporaEmitBothPalettesAndThreeReadableColors() {
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: 44,
            categories: [.pastel, .cold, .warm]
        )

        for (name, eventIDs) in canonicalGalleryUUIDCorpora {
            XCTAssertEqual(
                eventIDs.compactMap(UUID.init(uuidString:)).count,
                eventIDs.count,
                "fixture must contain only canonical UUID strings: \(name)"
            )
            let assignments = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: 44,
                paletteSet: paletteSet
            )

            XCTAssertEqual(
                Set(assignments.values.map(\.paletteSlot)),
                Set([.primary, .secondary]),
                "both daily palettes must reach emitted actors: \(name)"
            )
            XCTAssertGreaterThanOrEqual(
                perceptuallyDistinctCount(assignments.values.flatMap(\.colors)),
                3,
                "three readable colors must reach emitted actors: \(name)"
            )
        }
    }

    func testCanonicalGalleryUUIDAssignmentsStayActorLocalAcrossRemovalAndReorder() throws {
        for (name, eventIDs) in canonicalGalleryUUIDCorpora {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: 73,
                categories: [.pastel, .cold, .warm]
            )
            let full = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: 73,
                paletteSet: paletteSet
            )
            let reordered = DayObjectColorAllocator.assignments(
                eventIDs: Array(eventIDs.reversed()),
                rootSeed: 73,
                paletteSet: paletteSet
            )
            let removed = DayObjectColorAllocator.assignments(
                eventIDs: Array(eventIDs.dropFirst().dropLast()),
                rootSeed: 73,
                paletteSet: paletteSet
            )

            for eventID in eventIDs {
                let alone = DayObjectColorAllocator.assignments(
                    eventIDs: [eventID],
                    rootSeed: 73,
                    paletteSet: paletteSet
                )
                XCTAssertEqual(
                    try XCTUnwrap(full[eventID]),
                    try XCTUnwrap(alone[eventID]),
                    "actor-local assignment: \(name) \(eventID)"
                )
                XCTAssertEqual(
                    try XCTUnwrap(reordered[eventID]),
                    try XCTUnwrap(full[eventID]),
                    "reorder invariance: \(name) \(eventID)"
                )
                if removed[eventID] != nil {
                    XCTAssertEqual(
                        try XCTUnwrap(removed[eventID]),
                        try XCTUnwrap(full[eventID]),
                        "removal invariance: \(name) \(eventID)"
                    )
                }
            }
        }
    }

    func testAssignedObjectColorsRemainReadableAcrossRepresentativeRawMeshFields() {
        let filters = [ModernPaletteSelection.all]
            + ModernPaletteCategory.allCases.map { Set([$0]) }

        for categories in filters {
            for seed in UInt64(0)..<16 {
                let paletteSet = DayObjectPaletteSet.make(
                    rootSeed: seed,
                    categories: categories
                )
                let backgroundSamples = representativeMeshSamples(
                    palette: paletteSet.background
                )
                let assignments = DayObjectColorAllocator.assignments(
                    eventIDs: (0..<10).map { "uuid-\($0)-x" },
                    rootSeed: seed,
                    paletteSet: paletteSet
                )

                for assignment in assignments.values {
                    for color in assignment.colors {
                        XCTAssertGreaterThanOrEqual(
                            lowPercentileContrast(
                                actor: color.linearRGB,
                                backgrounds: backgroundSamples
                            ),
                            1.35 - 0.000_001,
                            "categories=\(categories) seed=\(seed) "
                                + "color=\(color.sRGB) background=\(paletteSet.background.code)"
                        )
                    }
                }
            }
        }
    }

    func testEveryCatalogPaletteCanBackVisibleDeterministicActorColors() {
        let catalog = ModernPaletteCatalog.all
        for (index, background) in catalog.enumerated() {
            let paletteSet = DayObjectPaletteSet(
                background: background,
                primaryObjects: catalog[(index + 1) % catalog.count],
                secondaryObjects: catalog[(index + 2) % catalog.count]
            )
            let eventIDs = (0..<10).map { "catalog-\($0)" }
            let first = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: UInt64(index),
                paletteSet: paletteSet
            )
            let repeated = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: UInt64(index),
                paletteSet: paletteSet
            )
            let samples = representativeMeshSamples(palette: background)
            let sourceColors: [DayObjectObjectPaletteSlot: [DayObjectRGB]] = [
                .primary: paletteSet.primaryObjects.hexes.map(DayObjectRGB.init(hex:)),
                .secondary: paletteSet.secondaryObjects.hexes.map(DayObjectRGB.init(hex:)),
            ]

            XCTAssertEqual(first, repeated, "background=\(background.code)")
            XCTAssertEqual(first.count, 10, "background=\(background.code)")
            for assignment in first.values {
                XCTAssertTrue((1...3).contains(assignment.colors.count))
                for (sourceIndex, color) in zip(
                    assignment.sourceIndices,
                    assignment.colors
                ) {
                    let source = sourceColors[assignment.paletteSlot]![sourceIndex]
                    let sourcePerceptual = testOKLab(source.linearRGB)
                    let adjustedPerceptual = testOKLab(color.linearRGB)
                    XCTAssertTrue(
                        color.linearRGB.x.isFinite
                            && color.linearRGB.y.isFinite
                            && color.linearRGB.z.isFinite
                            && (0...1).contains(color.linearRGB.x)
                            && (0...1).contains(color.linearRGB.y)
                            && (0...1).contains(color.linearRGB.z),
                        "background=\(background.code) actor=\(color.linearRGB)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        lowPercentileContrast(
                            actor: color.linearRGB,
                            backgrounds: samples
                        ),
                        1.05,
                        "best-effort background=\(background.code) actor=\(color.sRGB)"
                    )
                    XCTAssertLessThanOrEqual(
                        abs(adjustedPerceptual.x - sourcePerceptual.x),
                        0.25 + 0.000_1,
                        "bounded lightness background=\(background.code)"
                    )
                    XCTAssertTrue(
                        (0.06...0.94).contains(adjustedPerceptual.x),
                        "bounded output background=\(background.code) actor=\(color.sRGB)"
                    )
                    let sourceChroma = simd_length(SIMD2(sourcePerceptual.y, sourcePerceptual.z))
                    let adjustedChroma = simd_length(
                        SIMD2(adjustedPerceptual.y, adjustedPerceptual.z)
                    )
                    if sourceChroma >= 0.025 {
                        XCTAssertGreaterThanOrEqual(
                            adjustedChroma,
                            sourceChroma * 0.55 - 0.000_1,
                            "chroma background=\(background.code) actor=\(color.sRGB)"
                        )
                    }
                }
            }
        }
    }

    func testProductionSelectionFindsBoundedVisiblePairsForEveryCatalogBackground() {
        let identity = "catalog-contrast-cycle"
        let dayKeys = Array(isoDayKeys(from: 2026, through: 2026).prefix(340))
        var backgrounds = Set<String>()

        for (index, dayKey) in dayKeys.enumerated() {
            let rootSeed = CanvasElement.makeSeed(
                optionId: "dayObjects:\(identity)",
                dayKey: dayKey,
                index: 0
            )
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: rootSeed,
                categories: ModernPaletteSelection.all,
                dayKey: dayKey,
                identity: identity
            )
            backgrounds.insert(paletteSet.background.code)
            let samples = representativeMeshSamples(palette: paletteSet.background)
            let assignments = DayObjectColorAllocator.assignments(
                eventIDs: canonicalGalleryUUIDsWithSameTrailingDecimal,
                rootSeed: rootSeed,
                paletteSet: paletteSet
            )
            XCTAssertEqual(
                Set(assignments.values.map(\.paletteSlot)),
                Set([.primary, .secondary]),
                "both actor palettes must remain represented for day=\(dayKey)"
            )
            XCTAssertGreaterThanOrEqual(
                perceptuallyDistinctCount(assignments.values.flatMap(\.colors)),
                3,
                "three readable colors required for day=\(dayKey)"
            )
            let sourceColors: [DayObjectObjectPaletteSlot: [DayObjectRGB]] = [
                .primary: paletteSet.primaryObjects.hexes.map(DayObjectRGB.init(hex:)),
                .secondary: paletteSet.secondaryObjects.hexes.map(DayObjectRGB.init(hex:)),
            ]

            for assignment in assignments.values {
                for (sourceIndex, color) in zip(
                    assignment.sourceIndices,
                    assignment.colors
                ) {
                    let source = sourceColors[assignment.paletteSlot]![sourceIndex]
                    let sourcePerceptual = testOKLab(source.linearRGB)
                    let adjustedPerceptual = testOKLab(color.linearRGB)
                    XCTAssertGreaterThanOrEqual(
                        lowPercentileContrast(
                            actor: color.linearRGB,
                            backgrounds: samples
                        ),
                        1.35 - 0.000_001,
                        "index=\(index) day=\(dayKey) background=\(paletteSet.background.code)"
                    )
                    XCTAssertLessThanOrEqual(
                        abs(adjustedPerceptual.x - sourcePerceptual.x),
                        0.25 + 0.000_1,
                        "day=\(dayKey) background=\(paletteSet.background.code)"
                    )
                    XCTAssertTrue((0.06...0.94).contains(adjustedPerceptual.x))
                    let sourceChroma = simd_length(SIMD2(sourcePerceptual.y, sourcePerceptual.z))
                    let adjustedChroma = simd_length(
                        SIMD2(adjustedPerceptual.y, adjustedPerceptual.z)
                    )
                    if sourceChroma >= 0.025 {
                        XCTAssertGreaterThanOrEqual(
                            adjustedChroma,
                            sourceChroma * 0.55 - 0.000_1
                        )
                    }
                }
            }
        }

        XCTAssertEqual(backgrounds, Set(ModernPaletteCatalog.all.map(\.code)))
    }

    func testAllocatorOmitsUnreadableMembersButKeepsBothRelatedPalettes() {
        let paletteSet = DayObjectPaletteSet(
            background: ModernPalette(
                code: "202020707070C8C8C8F0F0F0",
                categories: [.pastel]
            ),
            primaryObjects: ModernPalette(
                code: "202020747474F04A6AF5C542",
                categories: [.warm]
            ),
            secondaryObjects: ModernPalette(
                code: "3030308080804AC8F05C65F5",
                categories: [.cold]
            )
        )
        let samples = representativeMeshSamples(palette: paletteSet.background)
        let assignments = DayObjectColorAllocator.assignments(
            eventIDs: (0..<10).map { "readable-subset-\($0)" },
            rootSeed: 0xB0A_D3D,
            paletteSet: paletteSet
        )

        XCTAssertEqual(Set(assignments.values.map(\.paletteSlot)), Set([.primary, .secondary]))
        XCTAssertTrue(assignments.values.allSatisfy { (1...3).contains($0.colors.count) })
        XCTAssertTrue(assignments.values.flatMap(\.colors).allSatisfy {
            lowPercentileContrast(actor: $0.linearRGB, backgrounds: samples)
                >= 1.35 - 0.000_001
        })
        XCTAssertGreaterThanOrEqual(
            perceptuallyDistinctCount(assignments.values.flatMap(\.colors)),
            3
        )
    }

    func testCoherentAdjustmentFixesPaletteWhoseBestNodeContrastHidesItsWorstField() {
        let paletteSet = DayObjectPaletteSet(
            background: ModernPalette(
                code: "202020707070C8C8C8F0F0F0",
                categories: [.pastel]
            ),
            primaryObjects: ModernPalette(
                code: "6868687474748080808C8C8C",
                categories: [.pastel]
            ),
            secondaryObjects: ModernPalette(
                code: "6070807080908090A090A0B0",
                categories: [.cold]
            )
        )
        let rawActor = DayObjectRGB(hex: "747474")
        let samples = representativeMeshSamples(palette: paletteSet.background)
        XCTAssertGreaterThan(
            samples.map { contrastRatio(rawActor.linearRGB, $0) }.max() ?? 0,
            1.35
        )
        XCTAssertLessThan(
            lowPercentileContrast(actor: rawActor.linearRGB, backgrounds: samples),
            1.35
        )

        let assignments = DayObjectColorAllocator.assignments(
            eventIDs: (0..<10).map { "adversarial-\($0)" },
            rootSeed: 91,
            paletteSet: paletteSet
        )
        let colors = assignments.values.flatMap(\.colors)

        XCTAssertFalse(colors.isEmpty)
        XCTAssertTrue(colors.allSatisfy {
            lowPercentileContrast(actor: $0.linearRGB, backgrounds: samples)
                >= 1.35 - 0.000_001
        })
        XCTAssertTrue(colors.allSatisfy {
            $0.linearRGB.x.isFinite && $0.linearRGB.y.isFinite && $0.linearRGB.z.isFinite
                && (0...1).contains($0.linearRGB.x)
                && (0...1).contains($0.linearRGB.y)
                && (0...1).contains($0.linearRGB.z)
        })
    }

    func testDailyActorColorAdjustmentIsDeterministicAndCoherentAcrossBothPalettes() {
        for seed in UInt64(0)..<64 {
            let paletteSet = DayObjectPaletteSet.make(
                rootSeed: seed,
                categories: ModernPaletteSelection.all
            )
            let eventIDs = (0..<10).map { "coherent-\($0)" }
            let first = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: seed,
                paletteSet: paletteSet
            )
            let repeated = DayObjectColorAllocator.assignments(
                eventIDs: eventIDs,
                rootSeed: seed,
                paletteSet: paletteSet
            )
            XCTAssertEqual(first, repeated, "seed=\(seed)")

            let source = [
                DayObjectObjectPaletteSlot.primary:
                    paletteSet.primaryObjects.hexes.map(DayObjectRGB.init(hex:)),
                DayObjectObjectPaletteSlot.secondary:
                    paletteSet.secondaryObjects.hexes.map(DayObjectRGB.init(hex:)),
            ]
            var directions = Set<Int>()
            for assignment in first.values {
                let raw = source[assignment.paletteSlot]!
                for (index, adjusted) in zip(assignment.sourceIndices, assignment.colors) {
                    let delta = relativeLuminance(adjusted.linearRGB)
                        - relativeLuminance(raw[index].linearRGB)
                    if abs(delta) > 0.000_001 {
                        directions.insert(delta > 0 ? 1 : -1)
                    }
                }
            }
            XCTAssertLessThanOrEqual(directions.count, 1, "seed=\(seed)")
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
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 80, drawableHeight: 60)
        let colors = ["000000", "ff0000", "ffff00", "00ffff"].map {
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
                palette: style.colors,
                width: plan.background.width,
                height: plan.background.height
            )
            XCTAssertLessThanOrEqual(metrics.centralRowReversals, 6, "\(archetype): \(metrics)")
            XCTAssertLessThanOrEqual(metrics.centralColumnReversals, 6, "\(archetype): \(metrics)")
            XCTAssertLessThan(metrics.strongAdjacentRatio, 0.015, "\(archetype): \(metrics)")
            XCTAssertLessThan(metrics.maximumAdjacentLuminanceDelta, 0.18, "\(archetype): \(metrics)")
            XCTAssertGreaterThan(metrics.luminanceRange, 0.055, "\(archetype): \(metrics)")
            XCTAssertTrue(metrics.paletteCoverage.allSatisfy { $0 > 0.02 }, "\(archetype): \(metrics)")
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

    func testEveryMeshArchetypeMovesContinuouslyWithoutFlashing() throws {
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
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 80, drawableHeight: 60)
        struct ProductionSample {
            let archetype: DayObjectMeshGradientArchetype
            let seed: UInt64
            let paletteCode: String
            let phase: Double
            let offset: SIMD2<Double>
            let motionDirection: Double
            let speed: Double
            let distortion: Double
            let swirl: Double
            let scale: Double
        }
        let samples: [ProductionSample] = [
            ProductionSample(
                archetype: .drift,
                seed: 9,
                paletteCode: "fbe4d6261fb31611790c0950",
                phase: 0.3342437857622169,
                offset: SIMD2(-0.061515760031825115, 0.15669136671557865),
                motionDirection: -1,
                speed: 0.05667018910757374,
                distortion: 0.09772469198316976,
                swirl: -0.02812940477327963,
                scale: 1.1266914788115472
            ),
            ProductionSample(
                archetype: .orbit,
                seed: 5,
                paletteCode: "1f6f5f2fa0846fcf97eeeeee",
                phase: 5.793237263670018,
                offset: SIMD2(0.060535677611837924, -0.026964133027720855),
                motionDirection: -1,
                speed: 0.06963054318298634,
                distortion: 0.35276991894408083,
                swirl: -0.26857879109355753,
                scale: 1.2306537698124989
            ),
            ProductionSample(
                archetype: .tide,
                seed: 0,
                paletteCode: "d2ff7273ec8b54c39215b392",
                phase: 3.6192557437130937,
                offset: SIMD2(-0.05718957802923064, -0.09489767378223239),
                motionDirection: 1,
                speed: 0.07107144436470772,
                distortion: 0.3815711795469606,
                swirl: -0.012204924698197284,
                scale: 1.0333248272942093
            ),
            ProductionSample(
                archetype: .islands,
                seed: 10,
                paletteCode: "914f1edeac80f7dcb9b5c18e",
                phase: 0.23057307904709248,
                offset: SIMD2(-0.13043781338829147, -0.07487085736809763),
                motionDirection: -1,
                speed: 0.08080084296248385,
                distortion: 0.16835330640967378,
                swirl: -0.05543680157378307,
                scale: 1.3065003444766914
            ),
            ProductionSample(
                archetype: .bloom,
                seed: 2,
                paletteCode: "a0937de7d4b5f6e6cbb6c7aa",
                phase: 3.4771381603265383,
                offset: SIMD2(0.16550632165939833, -0.060173329084549934),
                motionDirection: -1,
                speed: 0.0408662342167714,
                distortion: 0.271070799945461,
                swirl: 0.12226389197267654,
                scale: 0.9708499485223571
            ),
        ]

        XCTAssertEqual(
            Set(samples.map(\.archetype)),
            Set(DayObjectMeshGradientArchetype.allCases)
        )

        for sample in samples {
            let palette = DayObjectPalette.make(seed: sample.seed)
            let style = DayObjectMeshGradientStyle.make(seed: sample.seed, palette: palette)
            let expectedPalette = try XCTUnwrap(
                ModernPaletteCatalog.all.first { $0.code == sample.paletteCode }
            )
            XCTAssertEqual(
                palette.colors,
                expectedPalette.hexes.map(DayObjectRGB.init(hex:)),
                "seed=\(sample.seed)"
            )
            XCTAssertEqual(style.archetype, sample.archetype, "seed=\(sample.seed)")
            XCTAssertEqual(style.colors, palette.colors.map(\.linearRGB), "seed=\(sample.seed)")
            XCTAssertEqual(style.phase, sample.phase, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.offset.x, sample.offset.x, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.offset.y, sample.offset.y, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.motionDirection, sample.motionDirection, "seed=\(sample.seed)")
            XCTAssertEqual(style.speed, sample.speed, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.distortion, sample.distortion, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.swirl, sample.swirl, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")
            XCTAssertEqual(style.scale, sample.scale, accuracy: 0.000_000_000_001, "seed=\(sample.seed)")

            let first = try renderMeshGradient(
                style: style,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let nextFrame = try renderMeshGradient(
                style: style,
                elapsedTime: 1.0 / 30.0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let later = try renderMeshGradient(
                style: style,
                elapsedTime: 12,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let shortDelta = meanAbsoluteRGBDifference(first, nextFrame)
            let longDelta = meanAbsoluteRGBDifference(first, later)

            XCTAssertLessThan(shortDelta, 0.0025, "\(sample.archetype) flashes between frames")
            XCTAssertGreaterThan(longDelta, 0.004, "\(sample.archetype) appears static")
            XCTAssertLessThan(longDelta, 0.20, "\(sample.archetype) changes too abruptly")
        }
    }

    func testSeparatedProductionPalettesKeepEachColorVisibleAcrossArchetypes() throws {
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
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 80, drawableHeight: 60)
        // Nearest-palette coverage is meaningful only when catalog colors are
        // sufficiently distinct. These are real production palettes with a
        // minimum linear-RGB pair distance above 0.50, one for each family.
        let productionSamples: [(archetype: DayObjectMeshGradientArchetype, paletteCode: String)] = [
            (.drift, "211951836fff15f5baf0f3ff"),
            (.orbit, "001bb70046ffff8040f5f1dc"),
            (.tide, "211951836fff15f5baf0f3ff"),
            (.islands, "211951836fff15f5baf0f3ff"),
            (.bloom, "211951836fff15f5baf0f3ff"),
        ]
        XCTAssertEqual(
            Set(productionSamples.map(\.archetype)),
            Set(DayObjectMeshGradientArchetype.allCases)
        )
        var minimumCoverage = 1.0
        var minimumDetail = ""
        for sample in productionSamples {
            let productionPalette = try XCTUnwrap(
                ModernPaletteCatalog.all.first { $0.code == sample.paletteCode }
            )
            let colors = productionPalette.hexes.map { DayObjectRGB(hex: $0).linearRGB }
            let separation = minimumPairwiseRGBDistance(colors)
            XCTAssertGreaterThan(
                separation,
                0.50,
                "palette=\(productionPalette.code) must remain spatially unambiguous"
            )
            let style = productionCoverageStyle(colors: colors, archetype: sample.archetype)
            let pixels = try renderMeshGradient(
                style: style,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let coverage = paletteCoverage(pixels: pixels, palette: style.colors)
            guard let leastCoveredIndex = coverage.indices.min(by: {
                coverage[$0] < coverage[$1]
            }) else {
                XCTFail("palette coverage requires four colors")
                continue
            }
            let leastCoverage = coverage[leastCoveredIndex]
            if leastCoverage < minimumCoverage {
                minimumCoverage = leastCoverage
                minimumDetail = "palette=\(productionPalette.code) archetype=\(sample.archetype) color=\(leastCoveredIndex) coverage=\(coverage)"
            }
            XCTAssertTrue(
                coverage.allSatisfy { $0 > 0.02 },
                "palette=\(productionPalette.code) archetype=\(sample.archetype) coverage=\(coverage)"
            )
        }
        XCTAssertGreaterThan(minimumCoverage, 0.02, minimumDetail)
    }

    func testEveryMeshNodeHasVisibleBasisSupportAcrossArchetypes() throws {
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
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 80, drawableHeight: 60)

        var minimumVisibleShare = 1.0
        var minimumDetail = ""
        for archetype in DayObjectMeshGradientArchetype.allCases {
            for nodeIndex in 0..<4 {
                var colors = Array(repeating: SIMD3<Float>(repeating: 0), count: 4)
                colors[nodeIndex] = SIMD3<Float>(repeating: 1)
                let pixels = try renderMeshGradient(
                    style: productionCoverageStyle(colors: colors, archetype: archetype),
                    elapsedTime: 0,
                    plan: plan,
                    device: device,
                    commandQueue: commandQueue,
                    pipeline: pipeline
                )
                let visibleShare = brightPixelCoverage(pixels: pixels, minimumLuminance: 0.12)
                if visibleShare < minimumVisibleShare {
                    minimumVisibleShare = visibleShare
                    minimumDetail = "archetype=\(archetype) node=\(nodeIndex) visibleShare=\(visibleShare)"
                }
                XCTAssertGreaterThan(
                    visibleShare,
                    0.02,
                    "archetype=\(archetype) node=\(nodeIndex) visibleShare=\(visibleShare)"
                )
            }
        }
        XCTAssertGreaterThan(minimumVisibleShare, 0.02, minimumDetail)
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
            palette: style.colors,
            width: plan.background.width,
            height: plan.background.height
        )
        XCTAssertLessThanOrEqual(metrics.centralRowReversals, 8, "metrics=\(metrics)")
        XCTAssertLessThanOrEqual(metrics.centralColumnReversals, 8, "metrics=\(metrics)")
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

    func testBroadFieldMetricsIncludeVerticalAdjacentPixels() {
        let width = 8
        let height = 8
        var pixels = Array(repeating: UInt16(0), count: width * height * 4)
        for y in 0..<height {
            let value = Float16(y.isMultiple(of: 2) ? 0 : 1).bitPattern
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = value
                pixels[index + 1] = value
                pixels[index + 2] = value
                pixels[index + 3] = Float16(1).bitPattern
            }
        }

        let metrics = broadFieldMetrics(
            pixels: pixels,
            palette: [SIMD3(repeating: 0), SIMD3(repeating: 1)],
            width: width,
            height: height
        )

        XCTAssertGreaterThan(metrics.strongAdjacentRatio, 0.45)
        XCTAssertGreaterThan(metrics.maximumAdjacentLuminanceDelta, 0.9)
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

    private func isoDayKeys(from firstYear: Int, through lastYear: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var result = [String]()
        for year in firstYear...lastYear {
            for month in 1...12 {
                let days = calendar.range(
                    of: .day,
                    in: .month,
                    for: calendar.date(from: DateComponents(year: year, month: month, day: 1))!
                )!
                for day in days {
                    result.append(String(format: "%04d-%02d-%02d", year, month, day))
                }
            }
        }
        return result
    }

    private func broadFieldMetrics(
        pixels: [UInt16],
        palette: [SIMD3<Float>],
        width: Int,
        height: Int
    ) -> (
        centralRowReversals: Int,
        centralColumnReversals: Int,
        strongAdjacentRatio: Double,
        maximumAdjacentLuminanceDelta: Float,
        luminanceRange: Float,
        paletteCoverage: [Double]
    ) {
        func luminance(x: Int, y: Int) -> Float {
            let index = (y * width + x) * 4
            let red = Float(Float16(bitPattern: pixels[index]))
            let green = Float(Float16(bitPattern: pixels[index + 1]))
            let blue = Float(Float16(bitPattern: pixels[index + 2]))
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }

        func reversalCount(_ values: [Float]) -> Int {
            var reversals = 0
            var previousDirection = 0
            for index in 1..<values.count {
                let delta = values[index] - values[index - 1]
                let direction = delta > 0.002 ? 1 : (delta < -0.002 ? -1 : 0)
                if direction != 0 {
                    if previousDirection != 0, direction != previousDirection {
                        reversals += 1
                    }
                    previousDirection = direction
                }
            }
            return reversals
        }
        let centerY = height / 2
        let centerX = width / 2
        let centralRowReversals = reversalCount(
            (0..<width).map { luminance(x: $0, y: centerY) }
        )
        let centralColumnReversals = reversalCount(
            (0..<height).map { luminance(x: centerX, y: $0) }
        )

        var strongAdjacent = 0
        var adjacentCount = 0
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var maximumAdjacentLuminanceDelta: Float = 0
        for y in 0..<height {
            for x in 0..<width {
                let value = luminance(x: x, y: y)
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                if x > 0 {
                    adjacentCount += 1
                    let adjacentDelta = abs(value - luminance(x: x - 1, y: y))
                    maximumAdjacentLuminanceDelta = max(maximumAdjacentLuminanceDelta, adjacentDelta)
                    if adjacentDelta > 0.04 {
                        strongAdjacent += 1
                    }
                }
                if y > 0 {
                    adjacentCount += 1
                    let adjacentDelta = abs(value - luminance(x: x, y: y - 1))
                    maximumAdjacentLuminanceDelta = max(maximumAdjacentLuminanceDelta, adjacentDelta)
                    if adjacentDelta > 0.04 {
                        strongAdjacent += 1
                    }
                }
            }
        }

        return (
            centralRowReversals: centralRowReversals,
            centralColumnReversals: centralColumnReversals,
            strongAdjacentRatio: Double(strongAdjacent) / Double(max(adjacentCount, 1)),
            maximumAdjacentLuminanceDelta: maximumAdjacentLuminanceDelta,
            luminanceRange: maximum - minimum,
            paletteCoverage: paletteCoverage(pixels: pixels, palette: palette)
        )
    }

    private func paletteCoverage(
        pixels: [UInt16],
        palette: [SIMD3<Float>]
    ) -> [Double] {
        var counts = Array(repeating: 0, count: palette.count)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let sample = SIMD3(
                Float(Float16(bitPattern: pixels[index])),
                Float(Float16(bitPattern: pixels[index + 1])),
                Float(Float16(bitPattern: pixels[index + 2]))
            )
            let nearest = palette.indices.min {
                simd_distance_squared(sample, palette[$0])
                    < simd_distance_squared(sample, palette[$1])
            }!
            counts[nearest] += 1
        }
        let total = Double(max(counts.reduce(0, +), 1))
        return counts.map { Double($0) / total }
    }

    private func brightPixelCoverage(
        pixels: [UInt16],
        minimumLuminance: Float
    ) -> Double {
        var brightCount = 0
        var pixelCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Float(Float16(bitPattern: pixels[index]))
            let green = Float(Float16(bitPattern: pixels[index + 1]))
            let blue = Float(Float16(bitPattern: pixels[index + 2]))
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            if luminance > minimumLuminance {
                brightCount += 1
            }
            pixelCount += 1
        }
        return Double(brightCount) / Double(max(pixelCount, 1))
    }

    private func productionCoverageStyle(
        colors: [SIMD3<Float>],
        archetype: DayObjectMeshGradientArchetype
    ) -> DayObjectMeshGradientStyle {
        let parameters: (distortion: Double, swirl: Double, speed: Double, scale: Double)
        switch archetype {
        case .drift:
            parameters = (0.16, 0.00, 0.065, 1.05)
        case .orbit:
            parameters = (0.30, 0.24, 0.065, 1.05)
        case .tide:
            parameters = (0.30, 0.00, 0.060, 1.05)
        case .islands:
            parameters = (0.18, 0.00, 0.075, 1.05)
        case .bloom:
            parameters = (0.26, 0.00, 0.055, 1.05)
        }
        return DayObjectMeshGradientStyle(
            colors: colors,
            archetype: archetype,
            offset: SIMD2(0.08, -0.06),
            distortion: parameters.distortion,
            swirl: parameters.swirl,
            speed: parameters.speed,
            scale: parameters.scale,
            phase: 1.25,
            motionDirection: -1
        )
    }

    private var canonicalGalleryUUIDCorpora: [(name: String, eventIDs: [String])] {
        [
            (name: "representative", eventIDs: representativeCanonicalGalleryUUIDs),
            (
                name: "same-trailing-decimal",
                eventIDs: canonicalGalleryUUIDsWithSameTrailingDecimal
            ),
        ]
    }

    private var representativeCanonicalGalleryUUIDs: [String] {
        [
            "B08F75C2-149A-4D31-8AC6-7E92F103BA10",
            "1E4A92D7-C5B0-4768-91FD-20AB34CE5721",
            "7C31E5A9-08DF-42B6-A174-9D60F2BC8E32",
            "D2640BA1-7E53-49C8-BF20-516A93ED4C43",
            "38AD7F20-61C9-45E4-8B32-E7501C96DA54",
            "A9502E6C-3D17-4B84-906F-C28AD5713E65",
            "4F83C1D6-A209-47BE-9D50-36E8B74AC176",
            "E71B46A3-5C80-429D-AF16-8D302CE95787",
            "26D9A074-F13E-48C5-B762-401EAC83D998",
            "93C5E218-6AB4-4F70-8D29-B1475E60CA09",
        ]
    }

    private var canonicalGalleryUUIDsWithSameTrailingDecimal: [String] {
        [
            "0F4C9B1A-2D3E-4A50-8B61-7C8D9E0F1AA7",
            "1A2B3C4D-5E6F-4789-9ABC-DEF0123456B7",
            "2B7E41C9-8A30-4D65-AF12-903C5E7B14C7",
            "3C8F52DA-9B41-4E76-B023-A14D6F8C25D7",
            "4D9063EB-AC52-4F87-8134-B25E709D36E7",
            "5EA174FC-BD63-4098-9245-C36F81AE47F7",
            "6FB2850D-CE74-41A9-A356-D47092BF58A7",
            "70C3961E-DF85-42BA-B467-E581A3C069B7",
            "81D4A72F-E096-43CB-8578-F692B4D17AC7",
            "92E5B830-F1A7-44DC-9689-07A3C5E28BD7",
        ]
    }

    /// Broad positive mesh weights keep the rendered field inside the convex
    /// hull of the four raw catalog colors. These node, transition, and center
    /// samples cover the regions a moving production mesh repeatedly exposes
    /// without relying on the old darkened SwiftUI fallback palette.
    private func representativeMeshSamples(palette: ModernPalette) -> [SIMD3<Float>] {
        let colors = palette.hexes.map { DayObjectRGB(hex: $0).linearRGB }
        var samples = colors
        for lhs in colors.indices {
            for rhs in colors.indices where lhs < rhs {
                for amount: Float in [0.25, 0.5, 0.75] {
                    samples.append(colors[lhs] + (colors[rhs] - colors[lhs]) * amount)
                }
            }
        }
        samples.append(
            colors.reduce(into: SIMD3<Float>.zero, +=) / Float(max(colors.count, 1))
        )
        return samples
    }

    private func lowPercentileContrast(
        actor: SIMD3<Float>,
        backgrounds: [SIMD3<Float>]
    ) -> Double {
        let contrasts = backgrounds.map { contrastRatio(actor, $0) }.sorted()
        guard !contrasts.isEmpty else { return 0 }
        return contrasts[Int(floor(Double(contrasts.count - 1) * 0.15))]
    }

    private func testOKLab(_ linearRGB: SIMD3<Float>) -> SIMD3<Double> {
        let red = Double(linearRGB.x)
        let green = Double(linearRGB.y)
        let blue = Double(linearRGB.z)
        let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)
        return SIMD3(
            0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }

    private func perceptuallyDistinctCount(_ colors: [DayObjectRGB]) -> Int {
        var representatives = [SIMD3<Double>]()
        for color in colors {
            let perceptual = testOKLab(color.linearRGB)
            if representatives.allSatisfy({ simd_distance($0, perceptual) >= 0.055 }) {
                representatives.append(perceptual)
            }
        }
        return representatives.count
    }

    private func minimumPairwiseRGBDistance(_ colors: [SIMD3<Float>]) -> Float {
        colors.indices.flatMap { lhs in
            colors.indices.filter { $0 < lhs }.map { rhs in
                simd_distance(colors[lhs], colors[rhs])
            }
        }.min() ?? 0
    }
}
