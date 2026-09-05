import AVFoundation
import CryptoKit
import XCTest
@testable import Steps4

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
        let rendererVersion: String?
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
        let rendererVersion: String?
    }

    private struct Asset: Decodable {
        let conversion: RenderFormat?
        let path: String
        let rootMIDINote: Int?
        let sha256: String
        let sourceKey: String
        let licenseFilename: String
        let sourceFiles: [SourceFile]
        let offlinePitchTransformSemitones: Int?
        let renderIdentitySha256: String?
    }

    private struct SourceFile: Decodable {
        let path: String
        let sha256: String
    }

    private struct HappeningSourceMap: Decodable {
        let schemaVersion: Int
        let rendererVersion: String
        let rendererImplementationSha256: String
        let renderFormat: RenderFormat
        let vcslRevision: String
        let vcslSourceURL: String
        let vcslLicenseFilename: String
        let recipes: [HappeningSourceRecipe]
    }

    private struct HappeningSourceRecipe: Decodable {
        let id: Int
        let workingName: String
        let paletteKind: String
        let topology: String
        let attackTopology: String
        let tailTopology: String
        let masteringFamily: String
        let sourceKey: String
        let seed: Int
        let rootMIDIs: [Int]
        let renderIdentitySha256: String
        let definitionSha256: String?
        let input: HappeningInput?
        let outputs: [HappeningOutput]
    }

    private struct RenderFormat: Decodable, Equatable {
        let sampleRateHz: Int?
        let channels: Int?
        let bitDepth: Int?
        let peakDBFS: Double?
        let fadeMilliseconds: Int?
        let maximumDurationSeconds: Double?
        let tailTaperMilliseconds: Int?
        let tailBoundaryRMSDBFS: Double?
        let onsetRMSDBFS: Double?
        let dcCeilingDBFS: Double?
        let maximumGainDB: Double?
        let masteringTargets: [String: MasteringFormat]?
        let resampler: ResamplerFormat?
        let tool: String?
    }

    private struct MasteringFormat: Decodable, Equatable {
        let rmsMinDBFS: Double
        let rmsMaxDBFS: Double
    }

    private struct ResamplerFormat: Decodable, Equatable {
        let algorithm: String
        let taps: Int
        let phases: Int
        let window: String
        let coefficientDecimalPlaces: Int
    }

    private struct HappeningInput: Decodable {
        let path: String
        let rootMIDI: Int
        let sha256: String
    }

    private struct HappeningOutput: Decodable {
        let path: String
        let rootMIDI: Int
        let pitchSemitones: Int?
        let sha256: String
    }

    private let selectedUIDs: Set<String> = [
        "39529417-FBC1-41D5-B1D1-0DED9E38F164",
        "96F9F71C-1D6C-41FC-8192-E4B550562357",
        "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
        "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
        "88335303-C675-4D14-907E-2D80823C2BCA",
        "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
        "C2958050-CDCA-4C64-AF92-3217539CE60A",
        "E2D8B458-C727-4388-A0EA-28802B605796",
        "A11082F1-308C-48EE-8C0A-F0F9DC361212",
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

    private func pcm16Samples(from url: URL) throws -> [Int] {
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThanOrEqual(data.count, 44, url.lastPathComponent)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: data[36..<40], as: UTF8.self), "data")
        return stride(from: 44, to: data.count - 1, by: 2).map { offset in
            let bits = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            return Int(Int16(bitPattern: bits))
        }
    }

    private func hasFiveMillisecondFade(_ samples: [Int], quantizedPeak: Int) -> Bool {
        let fadeFrames = Int(44_100 * 0.005)
        guard samples.count >= fadeFrames * 2, samples.first == 0, samples.last == 0 else { return false }
        let maximumAdjacentStep = quantizedPeak * 2 / 3
        let hasBoundedSlope: (ArraySlice<Int>) -> Bool = { window in
            zip(window, window.dropFirst()).allSatisfy { abs($1 - $0) <= maximumAdjacentStep }
        }
        return (samples.prefix(10).map(abs).max() ?? quantizedPeak) <= Int(Double(quantizedPeak) * 0.04)
            && (samples.suffix(10).map(abs).max() ?? quantizedPeak) <= Int(Double(quantizedPeak) * 0.02)
            && hasBoundedSlope(samples.prefix(fadeFrames))
            && hasBoundedSlope(samples.suffix(fadeFrames))
    }

    func testBundledAudioLicensesAndSourceManifestHavePinnedProvenance() throws {
        let bundle = Bundle(for: type(of: self))
        let licenseFilenames = [
            "AudioKitSynthOne-MIT.txt",
            "AudioKitCookbook-MIT.txt",
            "OsirisPiano-CC0-1.0.txt",
            "VCSL-CC0-1.0.txt",
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
                "VCSL": "c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e",
            ]
        )
    }

    func testBundledHappeningInventoryHasExactlyTheCatalogsDeclaredWAVFiles() throws {
        let bundle = Bundle(for: type(of: self))
        let resourceRoot = try XCTUnwrap(bundle.resourceURL)
        let happeningRoot = resourceRoot.appendingPathComponent("Happenings", isDirectory: true)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: happeningRoot.path, isDirectory: &isDirectory),
            "Missing bundled Happenings inventory"
        )
        XCTAssertTrue(isDirectory.boolValue, "Bundled Happenings must be a directory")

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: happeningRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let bundledPaths = try enumerator.compactMap { item -> String? in
            let url = try XCTUnwrap(item as? URL)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
            return "Happenings/" + url.path.replacingOccurrences(of: happeningRoot.path + "/", with: "")
        }
        let catalogPaths = HappeningSoundCatalog.recipes.flatMap(\.sources).map(\.resourceName)

        XCTAssertEqual(bundledPaths.count, 102)
        XCTAssertEqual(Set(bundledPaths), Set(catalogPaths))
        XCTAssertEqual(Set(catalogPaths).count, 102)
    }

    func testHappeningSourceMapPinsInputsAndMatchesCatalogManifestAndBundledBytes() throws {
        let bundle = Bundle(for: type(of: self))
        let sourceMapURL = try XCTUnwrap(
            bundle.url(forResource: "happening-source-map", withExtension: "json")
        )
        let sourceMap = try JSONDecoder().decode(
            HappeningSourceMap.self,
            from: Data(contentsOf: sourceMapURL)
        )
        let manifestURL = try XCTUnwrap(bundle.url(forResource: "audio-assets-manifest", withExtension: "json"))
        let manifest = try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: manifestURL))
        let sourcesURL = try XCTUnwrap(bundle.url(forResource: "SOURCES", withExtension: "json"))
        let sources = try JSONDecoder().decode([Source].self, from: Data(contentsOf: sourcesURL))
        let manifestAssets = Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.path, $0) })
        let catalogSources = HappeningSoundCatalog.recipes.flatMap(\.sources)
        let catalogHashes = Dictionary(uniqueKeysWithValues: catalogSources.map { ($0.resourceName, $0.sha256) })
        let catalogRoots = Dictionary(uniqueKeysWithValues: catalogSources.map { ($0.resourceName, Int($0.rootMIDI)) })
        let mappedOutputs = sourceMap.recipes.flatMap(\.outputs)
        let mappedHashes = Dictionary(uniqueKeysWithValues: mappedOutputs.map { ($0.path, $0.sha256) })
        let expectedVCSLPaths = [
            "09 Idiophones/Struck Idiophones/Marimba/Marimba_hit_Outrigger_C4_soft_01.wav",
            "10 Idiophones/Struck Idiophones/Balafon/Soft Mallet/EthnicXylo_softM_C4_vl2_rr1_Mid.wav",
            "11 Idiophones/Struck Idiophones/Vibraphone/Soft Mallets/Vibes_soft_C5_v1_rr1_Main.wav",
            "17 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_C4_p_rr1.wav",
            "18 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_D4_p_rr1.wav",
        ]

        XCTAssertEqual(sourceMap.schemaVersion, 1)
        XCTAssertEqual(sourceMap.rendererVersion, "happening-bank-v3")
        XCTAssertNotNil(sourceMap.rendererImplementationSha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression))
        XCTAssertEqual(sourceMap.renderFormat.sampleRateHz, 44_100)
        XCTAssertEqual(sourceMap.renderFormat.resampler?.algorithm, "windowed-sinc-bandlimited")
        XCTAssertEqual(sourceMap.renderFormat.resampler?.taps, 32)
        XCTAssertEqual(sourceMap.renderFormat.tailTaperMilliseconds, 1_000)
        XCTAssertEqual(sourceMap.renderFormat.tailBoundaryRMSDBFS, -45)
        XCTAssertEqual(sourceMap.renderFormat.peakDBFS, -6)
        XCTAssertEqual(sourceMap.renderFormat.onsetRMSDBFS, -15)
        XCTAssertEqual(sourceMap.renderFormat.dcCeilingDBFS, -50)
        XCTAssertEqual(sourceMap.renderFormat.maximumGainDB, 12)
        XCTAssertEqual(sourceMap.renderFormat.maximumDurationSeconds, 4.5)
        XCTAssertEqual(sourceMap.renderFormat.masteringTargets?["tonal-organic"],
                       MasteringFormat(rmsMinDBFS: -22, rmsMaxDBFS: -18))
        XCTAssertEqual(sourceMap.renderFormat.masteringTargets?["texture"],
                       MasteringFormat(rmsMinDBFS: -26, rmsMaxDBFS: -21))
        XCTAssertEqual(sourceMap.vcslRevision, "c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e")
        XCTAssertEqual(sourceMap.vcslSourceURL, "https://github.com/sgossner/VCSL")
        XCTAssertEqual(sourceMap.vcslLicenseFilename, "VCSL-CC0-1.0.txt")
        XCTAssertEqual(sourceMap.recipes.map(\.id), Array(1...30))
        XCTAssertEqual(sourceMap.recipes.filter { $0.sourceKey == "project-authored" }.map(\.seed),
                       Array(1...8) + Array(12...16) + Array(19...30))
        XCTAssertEqual(sourceMap.recipes.compactMap(\.input).map(\.path), expectedVCSLPaths)
        let vcslSource = try XCTUnwrap(sources.first { $0.project == "VCSL" })
        XCTAssertEqual(vcslSource.sourceURL, sourceMap.vcslSourceURL)
        XCTAssertEqual(vcslSource.revision, sourceMap.vcslRevision)
        XCTAssertEqual(vcslSource.licenseFilename, sourceMap.vcslLicenseFilename)
        XCTAssertEqual(vcslSource.selectedPaths, expectedVCSLPaths)
        XCTAssertTrue(sourceMap.recipes.compactMap(\.input).allSatisfy {
            $0.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        })
        XCTAssertTrue(sourceMap.recipes.allSatisfy {
            $0.renderIdentitySha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        })
        XCTAssertEqual(mappedOutputs.count, 102)
        XCTAssertEqual(mappedHashes, catalogHashes)

        let happeningManifestAssets = manifest.assets.filter { $0.path.hasPrefix("Happenings/") }
        XCTAssertEqual(happeningManifestAssets.count, 102)
        XCTAssertEqual(Set(happeningManifestAssets.map(\.path)), Set(mappedHashes.keys))
        XCTAssertEqual(manifest.sources["vcsl"]?.revision, sourceMap.vcslRevision)
        XCTAssertEqual(manifest.sources["vcsl"]?.licenseFilename, sourceMap.vcslLicenseFilename)
        XCTAssertEqual(manifest.sources["project-authored"]?.rendererVersion, sourceMap.rendererVersion)

        for output in mappedOutputs {
            let manifestAsset = try XCTUnwrap(manifestAssets[output.path])
            let conversion = try XCTUnwrap(manifestAsset.conversion, output.path)
            XCTAssertEqual(manifestAsset.sha256, output.sha256, output.path)
            let recipe = try XCTUnwrap(sourceMap.recipes.first { $0.outputs.contains { $0.path == output.path } })
            XCTAssertEqual(manifestAsset.rootMIDINote, output.rootMIDI, output.path)
            XCTAssertEqual(catalogRoots[output.path], output.rootMIDI, output.path)
            XCTAssertEqual(manifestAsset.sourceKey, recipe.sourceKey, output.path)
            XCTAssertEqual(manifestAsset.licenseFilename,
                           recipe.input == nil ? "" : sourceMap.vcslLicenseFilename,
                           output.path)
            XCTAssertEqual(manifestAsset.offlinePitchTransformSemitones, output.pitchSemitones, output.path)
            XCTAssertEqual(manifestAsset.renderIdentitySha256, recipe.renderIdentitySha256, output.path)
            XCTAssertEqual(conversion.sampleRateHz, sourceMap.renderFormat.sampleRateHz, output.path)
            XCTAssertEqual(conversion.channels, sourceMap.renderFormat.channels, output.path)
            XCTAssertEqual(conversion.bitDepth, sourceMap.renderFormat.bitDepth, output.path)
            XCTAssertEqual(conversion.peakDBFS, sourceMap.renderFormat.peakDBFS, output.path)
            XCTAssertEqual(conversion.fadeMilliseconds, sourceMap.renderFormat.fadeMilliseconds, output.path)
            XCTAssertEqual(conversion.maximumDurationSeconds,
                           sourceMap.renderFormat.maximumDurationSeconds, output.path)
            XCTAssertEqual(conversion.tailTaperMilliseconds,
                           sourceMap.renderFormat.tailTaperMilliseconds, output.path)
            XCTAssertEqual(conversion.tailBoundaryRMSDBFS,
                           sourceMap.renderFormat.tailBoundaryRMSDBFS, output.path)
            XCTAssertEqual(conversion.resampler, sourceMap.renderFormat.resampler, output.path)
            XCTAssertEqual(conversion.tool, sourceMap.rendererVersion, output.path)
            XCTAssertEqual(manifestAsset.sourceFiles.first?.sha256,
                           recipe.input?.sha256 ?? recipe.definitionSha256,
                           output.path)
            XCTAssertEqual(manifestAsset.sourceFiles.first?.path,
                           recipe.input?.path ?? "Scripts/day_objects_audio/happening-source-map.json#recipe-\(String(format: "%02d", recipe.id))",
                           output.path)
            let bundledURL = try XCTUnwrap(bundledAssetURL(for: output.path, in: bundle))
            let bundledHash = SHA256.hash(data: try Data(contentsOf: bundledURL))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(bundledHash, output.sha256, output.path)
        }
    }

    func testBundledHappeningWAVsUseProductionFormatDurationAndSizeBounds() throws {
        let bundle = Bundle(for: type(of: self))
        var aggregateBytes = 0

        for source in HappeningSoundCatalog.recipes.flatMap(\.sources) {
            let url = try XCTUnwrap(bundledAssetURL(for: source.resourceName, in: bundle))
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            aggregateBytes += try XCTUnwrap(values.fileSize)

            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.channelCount, 1, source.resourceName)
            XCTAssertEqual(file.fileFormat.sampleRate, 44_100, accuracy: 0.001, source.resourceName)
            XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16, source.resourceName)
            let duration = Double(file.length) / file.fileFormat.sampleRate
            XCTAssertTrue((0.12...6.0).contains(duration), "\(source.resourceName): \(duration)s")
        }

        XCTAssertLessThanOrEqual(aggregateBytes, 30 * 1_024 * 1_024)
    }

    func testFiveMillisecondFadeRejectsHardDiscontinuitiesBeyondSafeTenSampleEdges() {
        let quantizedPeak = 23_197
        var hardStart = [Int](repeating: 0, count: 1_000)
        hardStart.replaceSubrange(110..<780, with: repeatElement(quantizedPeak, count: 670))
        for offset in 0..<110 {
            hardStart[780 + offset] = quantizedPeak * (109 - offset) / 109
        }
        let hardEnd = Array(hardStart.reversed())

        XCTAssertFalse(hasFiveMillisecondFade(hardStart, quantizedPeak: quantizedPeak), "start fade")
        XCTAssertFalse(hasFiveMillisecondFade(hardEnd, quantizedPeak: quantizedPeak), "end fade")
    }

    func testBundledHappeningPCMMeetsMasteringFadesAndSafeTailGates() throws {
        let bundle = Bundle(for: type(of: self))
        let maximumPeak = Int(round(32_767 * pow(10, -6.0 / 20.0)))
        let tailFrames = Int(44_100 * 0.05)
        let maximumTailRMS = pow(10, -45.0 / 20.0)

        for recipe in HappeningSoundCatalog.recipes {
            let rmsBounds = recipe.id.rawValue <= 24 ? -22.0 ... -18.0 : -26.0 ... -21.0
            for source in recipe.sources {
                let url = try XCTUnwrap(bundledAssetURL(for: source.resourceName, in: bundle))
                let samples = try pcm16Samples(from: url)
                let absolutePeak = try XCTUnwrap(samples.map(abs).max())
                let audibleThreshold = Int(round(32_767 * pow(10, -60.0 / 20.0)))
                let audible = samples.filter { abs($0) >= audibleThreshold }
                let firstAudible = try XCTUnwrap(samples.firstIndex { abs($0) >= audibleThreshold })
                let onset = samples[firstAudible..<min(samples.count, firstAudible + Int(44_100 * 0.05))]
                let rmsDBFS: ([Int]) -> Double = { values in
                    let meanSquare = values.reduce(0.0) {
                        $0 + pow(Double($1) / 32_767.0, 2)
                    } / Double(values.count)
                    return 20 * log10(max(sqrt(meanSquare), 1e-6))
                }
                let dc = samples.reduce(0.0) { $0 + Double($1) / 32_767.0 } / Double(samples.count)
                let dcDBFS = 20 * log10(max(abs(dc), 1e-6))

                XCTAssertLessThanOrEqual(absolutePeak, maximumPeak + 1, source.resourceName)
                XCTAssertTrue(rmsBounds.contains(rmsDBFS(audible)), source.resourceName)
                XCTAssertLessThanOrEqual(rmsDBFS(Array(onset)), -14.95, source.resourceName)
                XCTAssertLessThanOrEqual(dcDBFS, -49.95, source.resourceName)
                XCTAssertTrue(hasFiveMillisecondFade(samples, quantizedPeak: maximumPeak), source.resourceName)

                if samples.count == 6 * 44_100 {
                    let tail = samples.suffix(tailFrames)
                    let meanSquare = tail.reduce(0.0) { $0 + pow(Double($1) / 32_767.0, 2) } / Double(tail.count)
                    XCTAssertLessThanOrEqual(sqrt(meanSquare), maximumTailRMS, source.resourceName)
                }
            }
        }
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

        let happeningPaths = Set(HappeningSoundCatalog.recipes.flatMap(\.sources).map(\.resourceName))
        XCTAssertEqual(Set(manifest.assets.map(\.path)), expectedAssetPaths.union(happeningPaths))
        XCTAssertEqual(manifest.assets.count, expectedAssetPaths.count + 102)

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
        XCTAssertEqual(
            Set(manifest.assets.map(\.path)),
            expectedAssetPaths.union(HappeningSoundCatalog.recipes.flatMap(\.sources).map(\.resourceName))
        )

        for asset in manifest.assets {
            let source = try XCTUnwrap(manifest.sources[asset.sourceKey], "Unknown source key for \(asset.path)")
            XCTAssertFalse(source.sourceURL.isEmpty, "Missing source URL for \(asset.path)")
            XCTAssertFalse(source.revision.isEmpty, "Missing source revision for \(asset.path)")
            XCTAssertEqual(asset.licenseFilename, source.licenseFilename)
            if !source.licenseFilename.isEmpty {
                XCTAssertNotNil(
                    bundle.url(forResource: source.licenseFilename, withExtension: nil),
                    "Missing license for \(asset.path)"
                )
            }
            XCTAssertTrue(asset.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)

            let assetURL = try XCTUnwrap(bundledAssetURL(for: asset.path, in: bundle))
            let digest = SHA256.hash(data: try Data(contentsOf: assetURL))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, asset.sha256, "Stale hash for \(asset.path)")
        }
    }
}
