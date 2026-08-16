import XCTest
@testable import Steps4

final class RichFigureGeometryTests: XCTestCase {
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
        XCTAssertEqual(star.lines.filter { $0.role == .structure }.count, axisCount)
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
}
