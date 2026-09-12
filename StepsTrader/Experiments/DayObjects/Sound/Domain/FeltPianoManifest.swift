import Foundation

struct FeltPianoSample: Equatable, Hashable, Sendable {
    let filename: String
    let rootMIDINote: UInt8
    let rootNote: String
    let velocityLayer: Int
    let originalSHA256: String
    let editedSHA256: String
    let sourceKey: String
    let licenseFilename: String
}

struct FeltPianoKeyZone: Equatable, Sendable {
    let sample: FeltPianoSample
    let keyRange: ClosedRange<UInt8>
}

enum FeltPianoManifestError: Error, Equatable {
    case resourceMissing
    case invalidSampleInventory
}

enum FeltPianoManifest {
    static let playableRange: ClosedRange<UInt8> = 36...83

    static func load(from bundle: Bundle) throws -> [FeltPianoSample] {
        guard let url = bundle.url(forResource: "audio-assets-manifest", withExtension: "json") else {
            throw FeltPianoManifestError.resourceMissing
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [FeltPianoSample] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        let samples = document.assets.compactMap { asset -> FeltPianoSample? in
            guard asset.path.hasPrefix("FeltPiano/"),
                  let rootMIDINote = asset.rootMIDINote,
                  let rootNote = asset.rootNote,
                  let velocityLayer = asset.velocityLayer,
                  let originalSHA256 = asset.sourceFiles?.first?.sha256 else { return nil }
            return FeltPianoSample(
                filename: (asset.path as NSString).lastPathComponent,
                rootMIDINote: rootMIDINote,
                rootNote: rootNote,
                velocityLayer: velocityLayer,
                originalSHA256: originalSHA256,
                editedSHA256: asset.sha256,
                sourceKey: asset.sourceKey,
                licenseFilename: asset.licenseFilename
            )
        }.sorted { $0.rootMIDINote < $1.rootMIDINote }

        guard samples.count == 12,
              samples.map(\.rootMIDINote) == [36, 40, 43, 48, 52, 55, 60, 64, 67, 72, 76, 79],
              samples.allSatisfy({ $0.velocityLayer == 1 && $0.sourceKey == "sfzinstruments/Osiris_Piano" && $0.licenseFilename == "OsirisPiano-CC0-1.0.txt" }),
              Set(samples.map(\.filename)).count == samples.count else {
            throw FeltPianoManifestError.invalidSampleInventory
        }
        return samples
    }

    static func nearestRootZones(for samples: [FeltPianoSample]) -> [FeltPianoKeyZone] {
        let ordered = samples.sorted { $0.rootMIDINote < $1.rootMIDINote }
        return ordered.indices.map { index in
            let lower = index == ordered.startIndex
                ? playableRange.lowerBound
                : UInt8((Int(ordered[index - 1].rootMIDINote) + Int(ordered[index].rootMIDINote)) / 2 + 1)
            let upper = index == ordered.index(before: ordered.endIndex)
                ? playableRange.upperBound
                : UInt8((Int(ordered[index].rootMIDINote) + Int(ordered[index + 1].rootMIDINote)) / 2)
            return FeltPianoKeyZone(sample: ordered[index], keyRange: lower...upper)
        }
    }

    static func sample(for midiNote: UInt8, in samples: [FeltPianoSample]) -> FeltPianoSample? {
        nearestRootZones(for: samples).first { $0.keyRange.contains(midiNote) }?.sample
    }

    private struct Document: Decodable { let assets: [Asset] }
    private struct Asset: Decodable {
        let path: String
        let rootMIDINote: UInt8?
        let rootNote: String?
        let velocityLayer: Int?
        let sha256: String
        let sourceKey: String
        let licenseFilename: String
        let sourceFiles: [SourceFile]?
    }
    private struct SourceFile: Decodable { let sha256: String }
}
