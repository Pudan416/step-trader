import XCTest
@testable import Steps4

final class RichFigureGeometryTests: XCTestCase {
    @MainActor
    func testReduceMotionReturnsCanonicalState() {
        let item = RichAssignmentFixture.previewItems(count: 1, nonce: 0)[0]
        let size = CGSize(width: 390, height: 844)
        let a = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 10, reduceMotion: true
        )
        let b = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 200, reduceMotion: true
        )

        XCTAssertEqual(a, b)
        assertCenterKeepsEffectsInsideCanvas(a.center, item: item, canvasSize: size)
        XCTAssertEqual(a.rotation, .zero)
        XCTAssertEqual(a.scale, 1)
        XCTAssertTrue(a.deformationTime.isFinite)
    }

    @MainActor
    func testFamilyMotionStaysWithinApprovedBounds() {
        let items = RichAssignmentFixture.previewItems(count: 10, nonce: 0)
        let byFamily = items.reduce(into: [RichFigureFamily: RichFigurePreviewItem]()) {
            if $0[$1.style.family] == nil { $0[$1.style.family] = $1 }
        }
        let size = CGSize(width: 390, height: 844)

        let circle = RichFigureRenderer.motionState(
            for: byFamily[.circle]!, canvasSize: size, time: 37, reduceMotion: false
        )
        XCTAssertTrue((0.98...1.02).contains(circle.scale))
        XCTAssertTrue((0...1).contains(circle.highlightPhase))

        let organicItem = byFamily[.luminousOrganic]!
        let organicA = RichFigureRenderer.motionState(
            for: organicItem, canvasSize: size, time: 37, reduceMotion: false
        )
        let organicB = RichFigureRenderer.motionState(
            for: organicItem, canvasSize: size, time: 57, reduceMotion: false
        )
        XCTAssertEqual(organicA.center, organicB.center)
        assertCenterKeepsEffectsInsideCanvas(
            organicA.center, item: organicItem, canvasSize: size
        )
        XCTAssertNotEqual(organicA.deformationTime, organicB.deformationTime)

        let starItem = byFamily[.crystallineStar]!
        let star = RichFigureRenderer.motionState(
            for: starItem, canvasSize: size, time: 37, reduceMotion: false
        )
        let starEnvelope = RichFigureLayout.edgeSafeEnvelope(
            for: starItem.layout,
            canvasSize: size
        )
        XCTAssertEqual(
            star.center,
            starEnvelope.constrainedCenter(
                SnowflakeShapeRenderer.driftPosition(
                    starItem.source, size: size, t: 37,
                    ampScale: 1
                )
            )
        )

        let raysItem = byFamily[.rays]!
        let rays = RichFigureRenderer.motionState(
            for: raysItem, canvasSize: size, time: 37, reduceMotion: false
        )
        assertCenterKeepsEffectsInsideCanvas(
            rays.center, item: raysItem, canvasSize: size
        )
        XCTAssertTrue((0.96...1.04).contains(rays.scale))
        XCTAssertTrue((0...1).contains(rays.highlightPhase))

        let spirographItem = byFamily[.orbitalSpirograph]!
        let spirograph = RichFigureRenderer.motionState(
            for: spirographItem, canvasSize: size, time: 37, reduceMotion: false
        )
        assertCenterKeepsEffectsInsideCanvas(
            spirograph.center, item: spirographItem, canvasSize: size
        )
    }

    @MainActor
    func testCircleOffsetHighlightMovesWithoutParticlesAndFreezesForReduceMotion() {
        let item = RichAssignmentFixture.previewItems(count: 10, nonce: 0)
            .first { $0.style.family == .circle }!
        let size = CGSize(width: 390, height: 844)
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let geometry = RichFigureGeometryFactory.make(
            family: .circle,
            seed: item.style.geometrySeed,
            detailTier: item.style.detailTier,
            canonicalTime: 0,
            budget: budget
        )
        let activeA = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 10, reduceMotion: false
        )
        let activeB = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 11, reduceMotion: false
        )
        let activeEffectA = RichFigureRenderer.highlightEffect(
            for: .circle, in: geometry, phase: activeA.highlightPhase
        )
        let activeEffectB = RichFigureRenderer.highlightEffect(
            for: .circle, in: geometry, phase: activeB.highlightPhase
        )

        XCTAssertNotEqual(activeA.highlightPhase, activeB.highlightPhase)
        XCTAssertNotEqual(activeEffectA, activeEffectB)
        XCTAssertNotEqual(activeEffectA?.point, geometry.core)
        XCTAssertTrue((0...1).contains(try! XCTUnwrap(activeEffectA?.intensity)))

        let reducedA = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 10, reduceMotion: true
        )
        let reducedB = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 200, reduceMotion: true
        )
        XCTAssertEqual(
            RichFigureRenderer.highlightEffect(
                for: .circle, in: geometry, phase: reducedA.highlightPhase
            ),
            RichFigureRenderer.highlightEffect(
                for: .circle, in: geometry, phase: reducedB.highlightPhase
            )
        )
    }

    @MainActor
    func testRayImpulseMovesWithoutParticlesAndFreezesForReduceMotion() {
        let item = RichAssignmentFixture.previewItems(count: 10, nonce: 0)
            .first { $0.style.family == .rays }!
        let size = CGSize(width: 390, height: 844)
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let geometry = RichFigureGeometryFactory.make(
            family: .rays,
            seed: item.style.geometrySeed,
            detailTier: item.style.detailTier,
            canonicalTime: 0,
            budget: budget
        )
        let activeA = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 10, reduceMotion: false
        )
        let activeB = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 11, reduceMotion: false
        )
        let activeEffectA = RichFigureRenderer.highlightEffect(
            for: .rays, in: geometry, phase: activeA.highlightPhase
        )
        let activeEffectB = RichFigureRenderer.highlightEffect(
            for: .rays, in: geometry, phase: activeB.highlightPhase
        )

        XCTAssertNotEqual(activeA.highlightPhase, activeB.highlightPhase)
        XCTAssertNotEqual(activeEffectA, activeEffectB)
        XCTAssertTrue((0...1).contains(try! XCTUnwrap(activeEffectA?.intensity)))

        let reducedA = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 10, reduceMotion: true
        )
        let reducedB = RichFigureRenderer.motionState(
            for: item, canvasSize: size, time: 200, reduceMotion: true
        )
        XCTAssertEqual(
            RichFigureRenderer.highlightEffect(
                for: .rays, in: geometry, phase: reducedA.highlightPhase
            ),
            RichFigureRenderer.highlightEffect(
                for: .rays, in: geometry, phase: reducedB.highlightPhase
            )
        )
    }

    func testInvalidGeometryUsesUnitCircleFallback() {
        let invalid = RichCachedGeometry(
            base: RichFigureGeometry(
                lines: [RichPolyline(
                    points: [CGPoint(x: CGFloat.nan, y: 0)],
                    isClosed: false,
                    role: .structure
                )],
                core: .zero,
                bounds: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1)
            ),
            fill: RichFillGeometry(
                lines: [], translucentSurfaces: [], highlightPoints: []
            )
        )

        let resolved = RichFigureRenderer.validatedGeometry(invalid)

        XCTAssertEqual(resolved.base.bounds, CGRect(x: -1, y: -1, width: 2, height: 2))
        XCTAssertEqual(resolved.base.lines.count, 1)
        XCTAssertTrue(resolved.base.lines[0].isClosed)
        XCTAssertTrue(resolved.base.allPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testFiniteDegenerateGeometryStillUsesUnitCircleFallback() {
        let degenerate = RichCachedGeometry(
            base: RichFigureGeometry(
                lines: [RichPolyline(
                    points: [.zero, .zero, .zero],
                    isClosed: true,
                    role: .silhouette
                )],
                core: .zero,
                bounds: CGRect(x: -1, y: -1, width: 2, height: 2)
            ),
            fill: RichFillGeometry(
                lines: [], translucentSurfaces: [], highlightPoints: []
            )
        )

        let resolved = RichFigureRenderer.validatedGeometry(degenerate)

        XCTAssertEqual(resolved.base.bounds, CGRect(x: -1, y: -1, width: 2, height: 2))
        XCTAssertEqual(resolved.base.lines.count, 1)
        XCTAssertEqual(resolved.base.lines[0].points.count, 64)
    }

    func testAnimatedCrystallineStarsSurviveRendererValidationAcrossSeedsAndBuckets() {
        let budget = RichRenderBudget.resolve(elementCount: 1, lowPowerMode: false)

        for seed in UInt64(0)..<UInt64(64) {
            for bucket in 1...12 {
                let canonicalTime = Double(bucket) * RichTimeBuckets.bucketSeconds
                    - RichTimeBuckets.phase(for: seed)
                let base = RichFigureGeometryFactory.make(
                    family: .crystallineStar,
                    seed: seed,
                    detailTier: .medium,
                    canonicalTime: canonicalTime,
                    budget: budget
                )
                let cached = RichCachedGeometry(
                    base: base,
                    fill: RichFillGeometryFactory.make(
                        fill: .outlineWithCore,
                        base: base,
                        seed: seed,
                        budget: budget
                    )
                )

                let resolved = RichFigureRenderer.validatedGeometry(cached)

                guard resolved.base == base else {
                    XCTFail(
                        "Star became fallback geometry for seed \(seed), bucket \(bucket)"
                    )
                    return
                }
                XCTAssertGreaterThan(
                    resolved.base.lines.filter { $0.role == .structure }.count,
                    1,
                    "Star topology was lost for seed \(seed), bucket \(bucket)"
                )
            }
        }
    }

    func testMalformedSecondaryColorFallsBackToPrimary() {
        let colors = RichFigureRenderer.resolvedColors(
            primaryHex: "#306090", secondaryHex: "not-a-color"
        )
        let nilSecondary = RichFigureRenderer.resolvedColors(
            primaryHex: "#306090", secondaryHex: nil
        )

        XCTAssertEqual(colors.secondary, colors.primary)
        XCTAssertEqual(nilSecondary.secondary, nilSecondary.primary)
        XCTAssertNotEqual(colors.secondary, .white)
    }

    func testParticlePositionsHonorExplicitBoundedCount() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let geometry = RichFigureGeometryFactory.make(
            family: .orbitalSpirograph, seed: 44, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )

        XCTAssertTrue(RichFigureRenderer.particlePoints(
            in: geometry, count: 0, seed: 44, phase: 0.25
        ).isEmpty)
        XCTAssertEqual(RichFigureRenderer.particlePoints(
            in: geometry, count: 7, seed: 44, phase: 0.25
        ).count, 7)
    }

    func testFillGeometryRespectsTenElementBudget() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let base = RichFigureGeometryFactory.make(
            family: .luminousOrganic, seed: 7, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )

        let contours = RichFillGeometryFactory.make(
            fill: .nestedContours, base: base, seed: 7, budget: budget
        )
        let rings = RichFillGeometryFactory.make(
            fill: .orbitalLines, base: base, seed: 7, budget: budget
        )
        let filaments = RichFillGeometryFactory.make(
            fill: .filamentField, base: base, seed: 7, budget: budget
        )

        XCTAssertLessThanOrEqual(contours.lines.count, budget.contourCount)
        XCTAssertLessThanOrEqual(rings.lines.count, budget.orbitalRingCount)
        XCTAssertLessThanOrEqual(filaments.lines.count, budget.filamentCount)
    }

    func testEveryFillIsDeterministicAndFiniteForEveryFamily() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for family in RichFigureFamily.allCases {
            let base = RichFigureGeometryFactory.make(
                family: family, seed: 19, detailTier: .medium,
                canonicalTime: 0, budget: budget
            )

            for fill in RichFillKind.allCases {
                let first = RichFillGeometryFactory.make(
                    fill: fill, base: base, seed: 91, budget: budget
                )
                let second = RichFillGeometryFactory.make(
                    fill: fill, base: base, seed: 91, budget: budget
                )

                XCTAssertEqual(first, second, "\(family) / \(fill)")
                XCTAssertFalse(fillPoints(first).isEmpty, "\(family) / \(fill)")
                XCTAssertTrue(
                    fillPoints(first).allSatisfy { $0.x.isFinite && $0.y.isFinite },
                    "\(family) / \(fill)"
                )
            }
        }
    }

    func testEveryFillStaysInsideNormalizedClosedEnvelopeForEveryFamily() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for family in RichFigureFamily.allCases {
            let base = RichFigureGeometryFactory.make(
                family: family, seed: 19, detailTier: .medium,
                canonicalTime: 0, budget: budget
            )
            let envelope = selectedEnvelope(in: base)

            for fill in RichFillKind.allCases {
                let geometry = RichFillGeometryFactory.make(
                    fill: fill, base: base, seed: 91, budget: budget
                )
                for point in fillPoints(geometry) {
                    XCTAssertTrue(
                        (-1.0...1.0).contains(point.x)
                            && (-1.0...1.0).contains(point.y),
                        "normalized range: \(family) / \(fill) / \(point)"
                    )
                    XCTAssertTrue(
                        pointIsInsideOrOnBoundary(point, polygon: envelope),
                        "envelope point: \(family) / \(fill) / \(point)"
                    )
                }
                for line in geometry.lines {
                    assertSegmentsStayInside(
                        line.points, closed: line.isClosed, polygon: envelope,
                        message: "\(family) / \(fill)"
                    )
                }
                for surface in geometry.translucentSurfaces {
                    assertSegmentsStayInside(
                        surface, closed: true, polygon: envelope,
                        message: "\(family) / \(fill)"
                    )
                }
            }
        }
    }

    func testRayNestedContoursAreStrictInsets() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let base = RichFigureGeometryFactory.make(
            family: .rays, seed: 19, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        let envelope = selectedEnvelope(in: base)
        let contours = RichFillGeometryFactory.make(
            fill: .nestedContours, base: base, seed: 91, budget: budget
        )

        XCTAssertEqual(contours.lines.count, budget.contourCount)
        for contour in contours.lines {
            XCTAssertTrue(contour.isClosed)
            let strictSamples = contour.points.indices.flatMap { index in
                let point = contour.points[index]
                let next = contour.points[(index + 1) % contour.points.count]
                return [point, CGPoint(
                    x: (point.x + next.x) / 2,
                    y: (point.y + next.y) / 2
                )]
            }
            for point in strictSamples {
                XCTAssertTrue(pointIsInside(point, polygon: envelope))
                XCTAssertGreaterThan(
                    minimumDistance(point, to: envelope), 0.000_001
                )
            }
        }
    }

    func testFillKindsHaveTheirRequiredDistinctTopologies() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let base = RichFigureGeometryFactory.make(
            family: .luminousOrganic, seed: 7, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )

        let gradient = RichFillGeometryFactory.make(
            fill: .luminousGradient, base: base, seed: 7, budget: budget
        )
        XCTAssertEqual(gradient.lines.count, budget.contourCount)
        XCTAssertGreaterThanOrEqual(gradient.translucentSurfaces.count, 3)
        XCTAssertEqual(gradient.highlightPoints.count, 1)
        XCTAssertNotEqual(gradient.highlightPoints[0], base.core)

        let contours = RichFillGeometryFactory.make(
            fill: .nestedContours, base: base, seed: 7, budget: budget
        )
        XCTAssertEqual(contours.lines.count, budget.contourCount)
        XCTAssertTrue(contours.lines.allSatisfy { $0.isClosed && $0.points.count > 2 })
        XCTAssertGreaterThanOrEqual(contours.translucentSurfaces.count, 3)
        XCTAssertTrue(contours.highlightPoints.isEmpty)

        let rings = RichFillGeometryFactory.make(
            fill: .orbitalLines, base: base, seed: 7, budget: budget
        )
        XCTAssertEqual(rings.lines.count, budget.orbitalRingCount)
        XCTAssertTrue(rings.lines.allSatisfy { !$0.isClosed && $0.points.count > 2 })
        XCTAssertGreaterThanOrEqual(rings.translucentSurfaces.count, 3)
        XCTAssertTrue(rings.highlightPoints.isEmpty)

        let filaments = RichFillGeometryFactory.make(
            fill: .filamentField, base: base, seed: 7, budget: budget
        )
        XCTAssertEqual(filaments.lines.count, budget.filamentCount)
        XCTAssertTrue(filaments.lines.allSatisfy { !$0.isClosed && $0.points.count == 2 })
        XCTAssertGreaterThanOrEqual(filaments.translucentSurfaces.count, 3)
        XCTAssertTrue(filaments.highlightPoints.isEmpty)

        let outline = RichFillGeometryFactory.make(
            fill: .outlineWithCore, base: base, seed: 7, budget: budget
        )
        XCTAssertEqual(outline.lines.count, 1)
        XCTAssertTrue(outline.lines[0].isClosed)
        XCTAssertGreaterThanOrEqual(outline.translucentSurfaces.count, 3)
        XCTAssertEqual(outline.highlightPoints, [base.core])

        let mass = RichFillGeometryFactory.make(
            fill: .layeredTranslucentMass, base: base, seed: 7, budget: budget
        )
        XCTAssertTrue(mass.lines.isEmpty)
        XCTAssertEqual(mass.translucentSurfaces.count, 4)
        XCTAssertTrue(mass.translucentSurfaces.allSatisfy { $0.count > 2 })
        XCTAssertTrue(mass.highlightPoints.isEmpty)
    }

    func testEveryFillProvidesAVisibleBodyAcrossEveryFamily() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)

        for family in RichFigureFamily.allCases {
            let base = RichFigureGeometryFactory.make(
                family: family, seed: 19, detailTier: .medium,
                canonicalTime: 0, budget: budget
            )

            for fill in RichFillKind.allCases {
                let geometry = RichFillGeometryFactory.make(
                    fill: fill, base: base, seed: 91, budget: budget
                )
                let widestSurface = geometry.translucentSurfaces
                    .map { points -> CGFloat in
                        guard let minimum = points.map(\.x).min(),
                              let maximum = points.map(\.x).max() else { return 0 }
                        return maximum - minimum
                    }
                    .max() ?? 0

                XCTAssertFalse(
                    geometry.translucentSurfaces.isEmpty,
                    "Missing luminous body: \(family) / \(fill)"
                )
                XCTAssertGreaterThan(
                    widestSurface,
                    base.bounds.width * 0.55,
                    "Body collapsed into a line or tiny core: \(family) / \(fill)"
                )
            }
        }
    }

    func testEveryMaterialKeepsBodyBrighterThanItsWireframeBackground() {
        for fill in RichFillKind.allCases {
            let profile = RichFigureMaterialProfile.resolve(fill: fill)

            XCTAssertGreaterThanOrEqual(
                profile.bodyOpacity, fill == .outlineWithCore ? 0.08 : 0.13,
                "Body is visually empty for \(fill)"
            )
            XCTAssertGreaterThanOrEqual(
                profile.coreScale, 0.55,
                "Core collapsed to a dot for \(fill)"
            )
            XCTAssertLessThanOrEqual(
                profile.lineOpacity, 0.82,
                "Wireframe dominates the body for \(fill)"
            )
        }
    }

    func testCrystallineStarHasEnoughCrossBracingToReadAsCrystalNotAsterisk() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)

        for seed in UInt64(0)..<UInt64(32) {
            let star = RichFigureGeometryFactory.make(
                family: .crystallineStar,
                seed: seed,
                detailTier: .medium,
                canonicalTime: 0,
                budget: budget
            )
            let structure = star.lines.filter { $0.role == .structure }

            XCTAssertGreaterThanOrEqual(
                structure.count, 16,
                "Star lacks crystalline chord layers for seed \(seed)"
            )
            XCTAssertTrue(
                structure.contains { $0.isClosed && $0.points.count >= 3 },
                "Star has rays but no crystalline planes for seed \(seed)"
            )
        }
    }

    func testFillGeometryHonorsLowPowerCapsAndUsesClosedEnvelopeFallback() {
        let budget = RichRenderBudget.resolve(elementCount: 3, lowPowerMode: true)
        let base = RichFigureGeometryFactory.make(
            family: .orbitalSpirograph, seed: 23, detailTier: .large,
            canonicalTime: 0, budget: budget
        )
        XCTAssertTrue(base.lines.allSatisfy { $0.role != .silhouette })

        for fill in RichFillKind.allCases {
            let geometry = RichFillGeometryFactory.make(
                fill: fill, base: base, seed: 31, budget: budget
            )
            XCTAssertFalse(fillPoints(geometry).isEmpty, "\(fill)")
        }

        let contours = RichFillGeometryFactory.make(
            fill: .nestedContours, base: base, seed: 31, budget: budget
        )
        let rings = RichFillGeometryFactory.make(
            fill: .orbitalLines, base: base, seed: 31, budget: budget
        )
        let filaments = RichFillGeometryFactory.make(
            fill: .filamentField, base: base, seed: 31, budget: budget
        )
        let mass = RichFillGeometryFactory.make(
            fill: .layeredTranslucentMass, base: base, seed: 31, budget: budget
        )

        XCTAssertLessThanOrEqual(contours.lines.count, budget.contourCount)
        XCTAssertLessThanOrEqual(rings.lines.count, budget.orbitalRingCount)
        XCTAssertLessThanOrEqual(filaments.lines.count, budget.filamentCount)
        XCTAssertEqual(mass.translucentSurfaces.count, 3)
    }

    func testEveryFamilyIsDeterministicFiniteAndNonDegenerate() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for family in RichFigureFamily.allCases {
            let a = RichFigureGeometryFactory.make(
                family: family, seed: 42, detailTier: .medium,
                canonicalTime: 12.0, budget: budget
            )
            let b = RichFigureGeometryFactory.make(
                family: family, seed: 42, detailTier: .medium,
                canonicalTime: 12.0, budget: budget
            )

            XCTAssertEqual(a, b)
            XCTAssertTrue(a.allPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            XCTAssertGreaterThan(a.bounds.width, 0.5)
            XCTAssertGreaterThan(a.bounds.height, 0.5)
        }
    }

    func testCrystallineStarSeedsRemainReadableAfterMeasuredFitting() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for seed in UInt64(0)..<UInt64(128) {
            let geometry = RichFigureGeometryFactory.make(
                family: .crystallineStar, seed: seed, detailTier: .medium,
                canonicalTime: 0, budget: budget
            )
            let scale = RichFigureLayout.fittedScale(
                canonicalBounds: geometry.bounds, targetDiameter: 100,
                opticalScale: RichFigureLayout.opticalScale(for: .crystallineStar)
            )

            XCTAssertGreaterThanOrEqual(
                max(geometry.bounds.width, geometry.bounds.height) * scale,
                100
            )
        }
    }

    func testEveryFamilyFollowsItsExplicitTopologyRules() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)

        let circle = RichFigureGeometryFactory.make(
            family: .circle, seed: 42, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        XCTAssertEqual(circle.lines.count, 3)
        XCTAssertEqual(circle.lines.first?.role, .silhouette)
        XCTAssertEqual(circle.lines.first?.points.count, 96)
        XCTAssertEqual(circle.lines.filter { $0.role == .structure }.count, 2)
        XCTAssertTrue(circle.lines.allSatisfy(\.isClosed))

        let organic = RichFigureGeometryFactory.make(
            family: .luminousOrganic, seed: 42, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        XCTAssertEqual(organic.lines.count, 1)
        XCTAssertEqual(organic.lines[0].role, .silhouette)
        XCTAssertEqual(organic.lines[0].points.count, 96)
        XCTAssertTrue(organic.lines[0].isClosed)
        for point in organic.lines[0].points {
            let radius = hypot(point.x, point.y)
            XCTAssertGreaterThanOrEqual(radius, 0.62)
            XCTAssertLessThanOrEqual(radius, 1.0)
        }

        let star = RichFigureGeometryFactory.make(
            family: .crystallineStar, seed: 42, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        let starSilhouette = try! XCTUnwrap(star.lines.first)
        let axisCount = starSilhouette.points.count / 2
        XCTAssertTrue(starSilhouette.isClosed)
        XCTAssertEqual(starSilhouette.role, .silhouette)
        XCTAssertTrue((8...12).contains(axisCount))
        let starStructure = star.lines.filter { $0.role == .structure }
        XCTAssertEqual(starStructure.count, axisCount * 2)
        XCTAssertEqual(starStructure.filter { !$0.isClosed }.count, axisCount)
        XCTAssertEqual(starStructure.filter(\.isClosed).count, axisCount)
        for (index, point) in starSilhouette.points.enumerated() {
            let radius = hypot(point.x, point.y)
            if index.isMultiple(of: 2) {
                XCTAssertTrue((0.82...1.0).contains(radius))
            } else {
                XCTAssertTrue((0.22...0.38).contains(radius))
            }
        }

        let rays = RichFigureGeometryFactory.make(
            family: .rays, seed: 42, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        let rayLines = rays.lines.filter { $0.role == .structure }
        XCTAssertTrue((18...24).contains(rayLines.count))
        XCTAssertEqual(rays.lines.filter { $0.role == .silhouette && $0.isClosed }.count, 1)
        XCTAssertTrue(rayLines.allSatisfy { $0.points.count == 2 && $0.points[0] == rays.core })
        XCTAssertLessThanOrEqual(abs(rays.core.x + 0.75), 0.15)
        XCTAssertLessThanOrEqual(abs(rays.core.y - 0.55), 0.15)

        let spirograph = RichFigureGeometryFactory.make(
            family: .orbitalSpirograph, seed: 42, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        let orbits = spirograph.lines.filter { $0.role == .orbit }
        XCTAssertTrue((4...6).contains(orbits.count))
        XCTAssertTrue(orbits.allSatisfy(\.isClosed))
        XCTAssertEqual(spirograph.lines.filter { $0.role == .structure }.count, 1)
    }

    func testCrystallineStarTimePreservesTopologyAndLimitsRayLengthChange() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let base = RichFigureGeometryFactory.make(
            family: .crystallineStar, seed: 77, detailTier: .medium,
            canonicalTime: 0, budget: budget
        )
        let changed = RichFigureGeometryFactory.make(
            family: .crystallineStar, seed: 77, detailTier: .medium,
            canonicalTime: 19.5, budget: budget
        )

        XCTAssertEqual(base.lines.map(\.role), changed.lines.map(\.role))
        XCTAssertEqual(base.lines.map(\.isClosed), changed.lines.map(\.isClosed))
        XCTAssertEqual(base.lines.map { $0.points.count }, changed.lines.map { $0.points.count })

        let baseRays = base.lines.filter { $0.role == .structure }
        let changedRays = changed.lines.filter { $0.role == .structure }
        for (baseRay, changedRay) in zip(baseRays, changedRays) {
            let baseTip = baseRay.points[1]
            let changedTip = changedRay.points[1]
            let baseLength = hypot(baseTip.x, baseTip.y)
            let changedLength = hypot(changedTip.x, changedTip.y)
            XCTAssertTrue((0.93...1.07).contains(changedLength / baseLength))
            XCTAssertEqual(
                baseTip.x * changedTip.y - baseTip.y * changedTip.x,
                0,
                accuracy: 0.000_001
            )
        }
    }

    private func fillPoints(_ geometry: RichFillGeometry) -> [CGPoint] {
        geometry.lines.flatMap(\.points)
            + geometry.translucentSurfaces.flatMap { $0 }
            + geometry.highlightPoints
    }

    private func assertCenterKeepsEffectsInsideCanvas(
        _ center: CGPoint,
        item: RichFigurePreviewItem,
        canvasSize: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let envelope = RichFigureLayout.edgeSafeEnvelope(
            for: item.layout,
            canvasSize: canvasSize
        )
        XCTAssertGreaterThanOrEqual(
            center.x - envelope.totalRadius, -0.000_001,
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            center.x + envelope.totalRadius, canvasSize.width + 0.000_001,
            file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(
            center.y - envelope.totalRadius, -0.000_001,
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            center.y + envelope.totalRadius, canvasSize.height + 0.000_001,
            file: file, line: line
        )
    }

    private func selectedEnvelope(in geometry: RichFigureGeometry) -> [CGPoint] {
        let closed = geometry.lines.filter { $0.isClosed && $0.points.count > 2 }
        let silhouettes = closed.filter { $0.role == .silhouette }
        return (silhouettes.isEmpty ? closed : silhouettes).max {
            abs(signedArea($0.points)) < abs(signedArea($1.points))
        }!.points
    }

    private func assertSegmentsStayInside(
        _ points: [CGPoint],
        closed: Bool,
        polygon: [CGPoint],
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard points.count > 1 else { return }
        let segmentCount = closed ? points.count : points.count - 1
        for index in 0..<segmentCount {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let midpoint = CGPoint(
                x: (start.x + end.x) / 2,
                y: (start.y + end.y) / 2
            )
            XCTAssertTrue(
                pointIsInsideOrOnBoundary(midpoint, polygon: polygon),
                "segment: \(message) / \(midpoint)",
                file: file,
                line: line
            )
        }
    }

    private func pointIsInsideOrOnBoundary(
        _ point: CGPoint,
        polygon: [CGPoint]
    ) -> Bool {
        minimumDistance(point, to: polygon) <= 0.000_001
            || pointIsInside(point, polygon: polygon)
    }

    private func pointIsInside(
        _ point: CGPoint,
        polygon: [CGPoint]
    ) -> Bool {
        var isInside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let crossingX = (previous.x - current.x)
                    * (point.y - current.y)
                    / (previous.y - current.y)
                    + current.x
                if point.x < crossingX { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }

    private func minimumDistance(
        _ point: CGPoint,
        to polygon: [CGPoint]
    ) -> CGFloat {
        polygon.indices.map { index in
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let x = end.x - start.x
            let y = end.y - start.y
            let lengthSquared = x * x + y * y
            guard lengthSquared > 0 else {
                return hypot(point.x - start.x, point.y - start.y)
            }
            let progress = max(0, min(1,
                ((point.x - start.x) * x + (point.y - start.y) * y)
                    / lengthSquared
            ))
            let nearest = CGPoint(
                x: start.x + progress * x,
                y: start.y + progress * y
            )
            return hypot(point.x - nearest.x, point.y - nearest.y)
        }.min() ?? .infinity
    }

    private func signedArea(_ points: [CGPoint]) -> CGFloat {
        points.indices.reduce(0) { area, index in
            let point = points[index]
            let next = points[(index + 1) % points.count]
            return area + point.x * next.y - next.x * point.y
        } * 0.5
    }
}
