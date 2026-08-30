import CryptoKit
import XCTest

final class DayObjectsAudioResourceTests: XCTestCase {
    private struct Preset: Decodable {
        let uid: String
    }

    private struct Source: Decodable, Equatable {
        let project: String
        let sourceURL: String
        let revision: String
        let licenseFilename: String
        let selectedPaths: [String]
    }

    private struct AssetManifest: Decodable {
        let schemaVersion: Int
        let sources: [String: ManifestSource]
        let assets: [Asset]
    }

    private struct ManifestSource: Decodable {
        let sourceURL: String
        let revision: String
        let licenseFilename: String
    }

    private struct Asset: Decodable {
        let path: String
        let sha256: String
        let sourceKey: String
        let licenseFilename: String
    }

    private let selectedUIDs: Set<String> = [
        "39529417-FBC1-41D5-B1D1-0DED9E38F164",
        "96F9F71C-1D6C-41FC-8192-E4B550562357",
        "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
        "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
        "88335303-C675-4D14-907E-2D80823C2BCA",
        "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
        "C2958050-CDCA-4C64-AF92-3217539CE60A",
        "4131C811-FBB8-4E15-B238-8986645A62D3",
        "FA16AF16-3033-485F-A183-4DAAB7025B52",
        "9BDE3DCB-219D-4D70-A067-C1057B557F19",
        "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F",
        "BB74B6AD-9076-464C-B373-F2E968BBD2BE",
        "AA903CDB-938B-4FC7-8E01-050DB95EFDE7",
        "6A4C11CA-2CF9-4153-B5D3-A67F28E465A1",
        "9F2D32B0-ED71-4127-A4C5-F51209656AF7",
    ]

    private let expectedAssetPaths: Set<String> = [
        "SynthOnePresets/selected-presets.json",
        "Drums/bass_drum_C1.wav",
        "Drums/closed_hi_hat_F#1.wav",
        "Drums/open_hi_hat_A#1.wav",
        "Drums/clap_D#1.wav",
        "Drums/snare_D1.wav",
        "Drums/cheeb-stick.wav",
        "Drums/cheeb-hat.wav",
        "Drums/cheeb-ch.wav",
        "FeltPiano/felt_C2.caf",
        "FeltPiano/felt_E2.caf",
        "FeltPiano/felt_G2.caf",
        "FeltPiano/felt_C3.caf",
        "FeltPiano/felt_E3.caf",
        "FeltPiano/felt_G3.caf",
        "FeltPiano/felt_C4.caf",
        "FeltPiano/felt_E4.caf",
        "FeltPiano/felt_G4.caf",
        "FeltPiano/felt_C5.caf",
        "FeltPiano/felt_E5.caf",
        "FeltPiano/felt_G5.caf",
    ]

    private func bundledAssetURL(for path: String, in bundle: Bundle) -> URL? {
        let nsPath = path as NSString
        let filename = nsPath.lastPathComponent as NSString
        let subdirectory = nsPath.deletingLastPathComponent
        return bundle.url(
            forResource: filename.deletingPathExtension,
            withExtension: filename.pathExtension,
            subdirectory: subdirectory == "." ? nil : subdirectory
        )
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

    func testBundledSynthOneSelectionContainsEachApprovedUIDExactlyOnce() throws {
        let bundle = Bundle(for: type(of: self))
        let presetsURL = try XCTUnwrap(
            bundle.url(forResource: "selected-presets", withExtension: "json", subdirectory: "SynthOnePresets")
        )
        let presets = try JSONDecoder().decode([Preset].self, from: Data(contentsOf: presetsURL))

        XCTAssertEqual(presets.count, selectedUIDs.count)
        XCTAssertEqual(Set(presets.map(\.uid)), selectedUIDs)
    }

    func testBundledAudioAssetInventoryIsExact() throws {
        let bundle = Bundle(for: type(of: self))
        let manifestURL = try XCTUnwrap(bundle.url(forResource: "audio-assets-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))

        XCTAssertEqual(Set(manifest.assets.map(\.path)), expectedAssetPaths)
        XCTAssertEqual(manifest.assets.count, expectedAssetPaths.count)

        let resourceRoot = try XCTUnwrap(bundle.resourceURL)
        let bundledAssetPaths = try ["SynthOnePresets", "Drums", "FeltPiano"].reduce(into: Set<String>()) {
            result, directory in
            let directoryURL = resourceRoot.appendingPathComponent(directory, isDirectory: true)
            let entries = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                let values = try entry.resourceValues(forKeys: [.isRegularFileKey])
                XCTAssertEqual(values.isRegularFile, true, "Unexpected non-file bundle entry \(entry.path)")
                result.insert("\(directory)/\(entry.lastPathComponent)")
            }
        }
        XCTAssertEqual(bundledAssetPaths, expectedAssetPaths)

        for path in expectedAssetPaths {
            XCTAssertNotNil(
                bundledAssetURL(for: path, in: bundle),
                "Missing bundled asset \(path)"
            )
        }
    }

    func testBundledAudioAssetManifestHashesAndAttributesEveryAsset() throws {
        let bundle = Bundle(for: type(of: self))
        let manifestURL = try XCTUnwrap(bundle.url(forResource: "audio-assets-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(Set(manifest.assets.map(\.path)), expectedAssetPaths)

        for asset in manifest.assets {
            let source = try XCTUnwrap(manifest.sources[asset.sourceKey], "Unknown source key for \(asset.path)")
            XCTAssertFalse(source.sourceURL.isEmpty, "Missing source URL for \(asset.path)")
            XCTAssertFalse(source.revision.isEmpty, "Missing source revision for \(asset.path)")
            XCTAssertEqual(asset.licenseFilename, source.licenseFilename)
            XCTAssertNotNil(
                bundle.url(forResource: source.licenseFilename, withExtension: nil),
                "Missing license for \(asset.path)"
            )
            XCTAssertTrue(asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)

            let assetURL = try XCTUnwrap(bundledAssetURL(for: asset.path, in: bundle))
            let digest = SHA256.hash(data: try Data(contentsOf: assetURL))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, asset.sha256, "Stale hash for \(asset.path)")
        }
    }
}
