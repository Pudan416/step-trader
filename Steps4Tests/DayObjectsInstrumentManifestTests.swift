import XCTest
@testable import Steps4

final class DayObjectsInstrumentManifestTests: XCTestCase {
    private let heyJakobID = "bass.hey-jakob"
    private let heyJakobUID = "E2D8B458-C727-4388-A0EA-28802B605796"
    private let basslinerID = "bass.bassliner"
    private let basslinerUID = "A11082F1-308C-48EE-8C0A-F0F9DC361212"

    private let expectedIDs = [
        "pad.interstellar",
        "pad.whispering-sands",
        "pad.forgotten-stories",
        "pluck.play-something-sad",
        "pluck.jec-ambient-pizz-2",
        "pluck.spider-filter-pluck",
        "bass.analog-boom",
        "bass.hey-jakob",
        "bass.bassliner",
        "bass.jec-hollores-2",
        "lead.verbacious",
        "lead.jec-softwah-2",
        "lead.bb-silver-screen",
        "keys.maschinenmensch",
        "keys.bb-slow-poly",
        "keys.jec-polaroids-2",
    ]

    private let expectedUIDByID = [
        "pad.interstellar": "39529417-FBC1-41D5-B1D1-0DED9E38F164",
        "pad.whispering-sands": "96F9F71C-1D6C-41FC-8192-E4B550562357",
        "pad.forgotten-stories": "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
        "pluck.play-something-sad": "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
        "pluck.jec-ambient-pizz-2": "88335303-C675-4D14-907E-2D80823C2BCA",
        "pluck.spider-filter-pluck": "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
        "bass.analog-boom": "C2958050-CDCA-4C64-AF92-3217539CE60A",
        "bass.hey-jakob": "E2D8B458-C727-4388-A0EA-28802B605796",
        "bass.bassliner": "A11082F1-308C-48EE-8C0A-F0F9DC361212",
        "bass.jec-hollores-2": "FA16AF16-3033-485F-A183-4DAAB7025B52",
        "lead.verbacious": "9BDE3DCB-219D-4D70-A067-C1057B557F19",
        "lead.jec-softwah-2": "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F",
        "lead.bb-silver-screen": "BB74B6AD-9076-464C-B373-F2E968BBD2BE",
        "keys.maschinenmensch": "AA903CDB-938B-4FC7-8E01-050DB95EFDE7",
        "keys.bb-slow-poly": "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1",
        "keys.jec-polaroids-2": "9F2D32B0-ED71-4127-A4C5-F51209656AF7",
    ]

    func testDefaultDescriptorsPreserveExactStableCatalogContract() {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors

        XCTAssertEqual(descriptors.map(\.id.rawValue), expectedIDs)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: descriptors.compactMap { descriptor in
                descriptor.sourceUID.map { (descriptor.id.rawValue, $0) }
            }),
            expectedUIDByID
        )
    }

    func testApprovedBassPaletteUsesMeasuredOutputTrims() throws {
        let bass = DayObjectsInstrumentManifest.descriptors(in: .bass)
        XCTAssertEqual(bass.map(\.id.rawValue), [
            "bass.analog-boom", "bass.hey-jakob",
            "bass.bassliner", "bass.jec-hollores-2",
        ])
        let descriptor = try XCTUnwrap(bass.first { $0.id.rawValue == heyJakobID })
        XCTAssertEqual(descriptor.sourceUID, heyJakobUID)
        XCTAssertEqual(descriptor.referenceMIDI, 38)
        XCTAssertEqual(descriptor.outputTrimDB, -9.18)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: bass.map { ($0.id.rawValue, $0.outputTrimDB) }),
            [
                "bass.analog-boom": -15.65,
                "bass.hey-jakob": -9.18,
                "bass.bassliner": -15.00,
                "bass.jec-hollores-2": -23.45,
            ]
        )

        let bassliner = try XCTUnwrap(bass.first { $0.id.rawValue == basslinerID })
        XCTAssertEqual(bassliner.sourceUID, basslinerUID)
        XCTAssertEqual(bassliner.displayName, "Bassliner")
        XCTAssertEqual(bassliner.bankName, "Red Sky Lullaby")
    }

    func testEachSynthOneTonalCategoryHasExpectedUniqueDescriptorCount() {
        let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
        let expectedCounts: [DayObjectsInstrumentCategory: Int] = [
            .pad: 3,
            .pluck: 3,
            .bass: 4,
            .lead: 3,
            .keys: 3,
        ]

        for (category, expectedCount) in expectedCounts {
            let matching = DayObjectsInstrumentManifest.descriptors(in: category)
            XCTAssertEqual(matching.count, expectedCount, "Unexpected count for \(category)")
            XCTAssertEqual(Set(matching.map(\.id)).count, expectedCount, "Duplicate ID in \(category)")
            XCTAssertTrue(matching.allSatisfy { $0.category == category })
            XCTAssertEqual(matching, descriptors.filter { $0.category == category })
        }

        XCTAssertEqual(DayObjectsInstrumentManifest.descriptors(in: .drums), [])
        XCTAssertEqual(DayObjectsInstrumentManifest.descriptors(in: .piano), [])
        XCTAssertEqual(Set(descriptors.map(\.id)).count, 16)
        XCTAssertEqual(Set(descriptors.compactMap(\.sourceUID)).count, 16)
    }

    func testEverySynthOneDescriptorHasAttributionAndBoundedAuditionMetadata() {
        for descriptor in DayObjectsInstrumentManifest.defaultDescriptors {
            XCTAssertFalse(descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(descriptor.bankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotNil(descriptor.sourceUID)
            XCTAssertTrue(descriptor.outputTrimDB.isFinite)
            XCTAssertLessThanOrEqual(descriptor.outputTrimDB, 0)
            XCTAssertTrue((24...96).contains(descriptor.referenceMIDI))
            XCTAssertFalse(descriptor.auditionChord.isEmpty)
            XCTAssertTrue(descriptor.auditionChord.allSatisfy { (24...108).contains($0) })
        }
    }

    func testInstrumentIDAndDescriptorRoundTripThroughCodable() throws {
        let descriptor = try XCTUnwrap(DayObjectsInstrumentManifest.defaultDescriptors.first)
        let data = try JSONEncoder().encode(descriptor)

        XCTAssertEqual(try JSONDecoder().decode(DayObjectsInstrumentDescriptor.self, from: data), descriptor)
        XCTAssertEqual(try JSONDecoder().decode(DayObjectsInstrumentID.self, from: JSONEncoder().encode(descriptor.id)), descriptor.id)
        XCTAssertEqual(Set(DayObjectsInstrumentCategory.allCases), [.pad, .pluck, .bass, .lead, .keys, .drums, .piano])
    }
}
