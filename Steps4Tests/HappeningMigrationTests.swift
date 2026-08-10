import XCTest
@testable import Steps4

/// Guards the one failure mode that is invisible in review: elements saved
/// before `frozenShapeType` existed resolve their shape *through* the category.
/// Dropping the category outright would silently redraw historical canvases
/// with different shapes, and nothing fails loudly when it happens.
///
/// The fixture is a real canvas captured from the simulator — five elements
/// across all three categories — with `frozenShapeType` stripped to recreate
/// the pre-`frozenShapeType` on-disk format. It is deliberately not synthesized.
final class HappeningMigrationTests: XCTestCase {

    private func loadFixture() throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: "canvas_legacy_categorised", withExtension: "json"),
            "Fixture missing from the Steps4Tests bundle — check Copy Bundle Resources"
        )
        return try Data(contentsOf: url)
    }

    /// The mapping the legacy decode path must reproduce, taken from
    /// `CanvasShapeType.defaultShape(for:)` as it stood before the refactor.
    private let expectedByCategory: [String: CanvasShapeType] = [
        "body": .circle,
        "mind": .snowflake,
        "heart": .rays
    ]

    func testLegacyCanvasDecodesToUnchangedFrozenShapeTypes() throws {
        let data = try loadFixture()

        // Read the raw categories straight out of the JSON so the expectation
        // does not depend on any type we are about to change.
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rawElements = try XCTUnwrap(raw["elements"] as? [[String: Any]])
        XCTAssertFalse(rawElements.isEmpty, "Fixture must contain elements")

        let canvas = try JSONDecoder().decode(DayCanvas.self, from: data)
        XCTAssertEqual(canvas.elements.count, rawElements.count)

        for (rawElement, decoded) in zip(rawElements, canvas.elements) {
            let rawCategory = try XCTUnwrap(rawElement["category"] as? String)
            XCTAssertNil(
                rawElement["frozenShapeType"],
                "Fixture element must predate frozenShapeType"
            )
            let expected = try XCTUnwrap(
                expectedByCategory[rawCategory],
                "Unmapped legacy category in fixture: \(rawCategory)"
            )
            XCTAssertEqual(
                decoded.frozenShapeType, expected,
                "Element \(decoded.optionId) drifted: category \(rawCategory) "
                + "must still resolve to \(expected)"
            )
        }
    }

    /// The fixture must actually exercise every mapping, or the test above
    /// passes vacuously for whichever category is missing.
    func testFixtureCoversAllThreeCategories() throws {
        let raw = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try loadFixture()) as? [String: Any]
        )
        let rawElements = try XCTUnwrap(raw["elements"] as? [[String: Any]])
        let categories = Set(rawElements.compactMap { $0["category"] as? String })
        XCTAssertEqual(categories, ["body", "mind", "heart"])
    }

    /// `EnergyCategory`'s decoder maps five legacy raw values. Saved canvases on
    /// beta devices contain them, so the migration path must accept all five or
    /// the whole canvas fails to decode — a louder failure than shape drift,
    /// but guarded by the same fixture.
    func testLegacyCategoryAliasesStillDecode() throws {
        let aliases: [String: CanvasShapeType] = [
            "activity": .circle,
            "creativity": .snowflake,
            "recovery": .snowflake,
            "rest": .snowflake,
            "joys": .rays
        ]
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try loadFixture()) as? [String: Any]
        )
        let elements = try XCTUnwrap(json["elements"] as? [[String: Any]])
        let template = try XCTUnwrap(elements.first)

        for (alias, expected) in aliases {
            var element = template
            element["category"] = alias
            element.removeValue(forKey: "frozenShapeType")
            json["elements"] = [element]

            let patched = try JSONSerialization.data(withJSONObject: json)
            let canvas = try JSONDecoder().decode(DayCanvas.self, from: patched)
            XCTAssertEqual(
                canvas.elements.first?.frozenShapeType, expected,
                "Legacy alias \(alias) must resolve to \(expected)"
            )
        }
    }

    func testNewSpawnHasNoCategoryAndFreezesAnAllowedShape() throws {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: "2026-08-08",
            composition: DayComposition.forDay(dayKey: "2026-08-08", happeningCount: 0)
        )

        XCTAssertEqual(element.frozenShapeType, .circle)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(element)) as? [String: Any]
        )
        XCTAssertNil(object["category"], "New elements must not persist a category")
    }
}
