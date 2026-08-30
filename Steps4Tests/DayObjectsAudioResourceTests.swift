import XCTest

final class DayObjectsAudioResourceTests: XCTestCase {
    private struct Source: Decodable, Equatable {
        let project: String
        let sourceURL: String
        let revision: String
        let licenseFilename: String
        let selectedPaths: [String]
    }

    func testBundledAudioLicensesAndSourceManifestHavePinnedProvenance() throws {
        let bundle = Bundle(for: type(of: self))
        let licenseFilenames = [
            "AudioKitSynthOne-MIT.txt",
            "AudioKitCookbook-MIT.txt",
            "OsirisPiano-CC0-1.0.txt",
        ]

        for filename in licenseFilenames {
            XCTAssertNotNil(bundle.url(forResource: filename, withExtension: nil), "Missing \(filename)")
        }

        let sourcesURL = try XCTUnwrap(bundle.url(forResource: "SOURCES", withExtension: "json"))
        let sources = try JSONDecoder().decode([Source].self, from: Data(contentsOf: sourcesURL))

        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: sources.map { ($0.project, $0.revision) }),
            [
                "AudioKitSynthOne": "6466a3715c96b7ecf1dd255a218cbd571408a314",
                "AudioKit/Cookbook": "c37d41daedf161b47315b7ae24b07f41213b73be",
                "sfzinstruments/Osiris_Piano": "18c6afccb60cff458edbf7c394571783e074e1e9",
            ]
        )
    }
}
