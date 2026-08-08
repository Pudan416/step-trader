import XCTest
@testable import Steps4

/// The three per-category shape keys collapse into one user-configured set.
///
/// Organic stays Pro, but is filtered at *spawn* time rather than removed from
/// storage — so a lapsed subscriber's saved preference survives and reactivates
/// on resubscribe.
final class AllowedCanvasShapesTests: XCTestCase {

    private let keys = [
        SharedKeys.allowedCanvasShapes,
        SharedKeys.bodyCanvasShape,
        SharedKeys.mindCanvasShape,
        SharedKeys.heartCanvasShape
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        CanvasShapeType.isProProvider = { true }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        CanvasShapeType.resetProProviderForTesting()
        super.tearDown()
    }

    // MARK: - Seeding from the legacy keys

    func testSeedsFromTheUnionOfTheThreeLegacyKeys() {
        UserDefaults.standard.set(CanvasShapeType.circle.rawValue, forKey: SharedKeys.bodyCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.snowflake.rawValue, forKey: SharedKeys.mindCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.snowflake.rawValue, forKey: SharedKeys.heartCanvasShape)

        XCTAssertEqual(
            Set(CanvasShapeType.allowedByUser), [.circle, .snowflake],
            "Union of the three, deduplicated"
        )
    }

    func testSeedMigratesHiddenLegacyShapesToCircle() {
        UserDefaults.standard.set(CanvasShapeType.blob.rawValue, forKey: SharedKeys.bodyCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.spirograph.rawValue, forKey: SharedKeys.mindCanvasShape)
        UserDefaults.standard.set(CanvasShapeType.rays.rawValue, forKey: SharedKeys.heartCanvasShape)

        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.circle, .rays])
    }

    func testSeedPersistsSoItHappensOnlyOnce() {
        UserDefaults.standard.set(CanvasShapeType.rays.rawValue, forKey: SharedKeys.bodyCanvasShape)
        _ = CanvasShapeType.allowedByUser

        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: SharedKeys.allowedCanvasShapes),
            [CanvasShapeType.rays.rawValue]
        )
    }

    func testFallsBackToAllSelectableWhenNothingIsSaved() {
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), Set(CanvasShapeType.selectableCases))
    }

    // MARK: - Reading and writing

    func testSetAllowedRoundTrips() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.rays, .circle]))
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.rays, .circle])
    }

    func testAllowedIsReturnedInPickerOrder() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.rays, .circle, .snowflake]))
        XCTAssertEqual(CanvasShapeType.allowedByUser, [.circle, .snowflake, .rays])
    }

    func testHiddenLegacyShapesCannotBeSet() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.circle]))
        XCTAssertFalse(
            CanvasShapeType.setAllowed([.blob, .spirograph]),
            "A set of only hidden shapes is empty once filtered, so it must be rejected"
        )
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.circle])
    }

    // MARK: - The set may never be empty

    func testCannotEmptyTheSet() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.rays]))
        XCTAssertFalse(CanvasShapeType.setAllowed([]), "Emptying must be rejected")
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), [.rays], "And must not have written")
    }

    func testNeverReturnsEmptyEvenIfStorageIsCorrupt() {
        UserDefaults.standard.set(["not-a-shape"], forKey: SharedKeys.allowedCanvasShapes)
        XCTAssertEqual(Set(CanvasShapeType.allowedByUser), Set(CanvasShapeType.selectableCases))
    }

    // MARK: - Pro gating

    func testNonProNeverSpawnsOrganicButKeepsThePreference() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.organicBlob, .circle]))

        CanvasShapeType.isProProvider = { false }
        XCTAssertEqual(
            Set(CanvasShapeType.allowedByUser), [.circle],
            "Organic is filtered at spawn time"
        )
        XCTAssertEqual(
            Set(UserDefaults.standard.stringArray(forKey: SharedKeys.allowedCanvasShapes) ?? []),
            [CanvasShapeType.organicBlob.rawValue, CanvasShapeType.circle.rawValue],
            "But the saved preference survives"
        )

        CanvasShapeType.isProProvider = { true }
        XCTAssertEqual(
            Set(CanvasShapeType.allowedByUser), [.organicBlob, .circle],
            "And reactivates on resubscribe"
        )
    }

    func testNonProWithOnlyOrganicSavedStillGetsAShape() {
        XCTAssertTrue(CanvasShapeType.setAllowed([.organicBlob]))
        CanvasShapeType.isProProvider = { false }

        let allowed = CanvasShapeType.allowedByUser
        XCTAssertFalse(allowed.isEmpty, "Spawn must always have something to pick")
        XCTAssertFalse(allowed.contains(.organicBlob))
    }

    /// `spawn` calls `allowedByUser.randomElement()`, so an empty return would
    /// crash or silently fall back. Cover every gate/storage combination.
    func testAllowedByUserIsNeverEmpty() {
        for isPro in [true, false] {
            CanvasShapeType.isProProvider = { isPro }
            for stored in [[], ["organicBlob"], ["blob"], ["garbage"], ["circle", "rays"]] {
                UserDefaults.standard.set(stored, forKey: SharedKeys.allowedCanvasShapes)
                XCTAssertFalse(
                    CanvasShapeType.allowedByUser.isEmpty,
                    "empty for isPro=\(isPro) stored=\(stored)"
                )
            }
        }
    }
}
