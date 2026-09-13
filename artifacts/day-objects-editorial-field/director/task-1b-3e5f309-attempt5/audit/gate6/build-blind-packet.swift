import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct BuildFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw BuildFailure(description: message) }
}

func object(_ value: Any?, _ context: String) throws -> [String: Any] {
    guard let result = value as? [String: Any] else {
        throw BuildFailure(description: "expected object: \(context)")
    }
    return result
}

func array(_ value: Any?, _ context: String) throws -> [Any] {
    guard let result = value as? [Any] else {
        throw BuildFailure(description: "expected array: \(context)")
    }
    return result
}

func string(_ value: Any?, _ context: String) throws -> String {
    guard let result = value as? String else {
        throw BuildFailure(description: "expected string: \(context)")
    }
    return result
}

func integer(_ value: Any?, _ context: String) throws -> Int {
    guard let result = value as? NSNumber else {
        throw BuildFailure(description: "expected integer: \(context)")
    }
    return result.intValue
}

func jsonObject(_ url: URL) throws -> [String: Any] {
    try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)), url.path)
}

func canonicalJSON(_ value: Any) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) + Data("\n".utf8)
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func readPackageHash(_ root: URL) throws -> String {
    try String(contentsOf: root.appendingPathComponent("package-hash.txt"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func image(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw BuildFailure(description: "cannot decode image: \(url.path)") }
    return image
}

func normalizedRGBA(_ image: CGImage) throws -> Data {
    let bytesPerRow = image.width * 4
    var data = Data(count: bytesPerRow * image.height)
    let rendered = data.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    try require(rendered, "cannot normalize RGBA")
    return data
}

func writeNew(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: [.withoutOverwriting])
}

func descriptor(
    metrics: [String: Any],
    colors: Int,
    background: String,
    expectedFull: String,
    expectedTile: String
) throws -> [String: Any] {
    let records = try array(metrics["sceneScale"], "metrics.sceneScale")
    let matches = try records.compactMap { raw -> [String: Any]? in
        let record = try object(raw, "scene-scale record")
        guard try string(record["family"], "scene family") == "outline",
              try integer(record["requestedColorCount"], "scene colors") == colors,
              try string(record["background"], "scene background") == background
        else { return nil }
        return record
    }
    try require(matches.count == 1, "condition must resolve exactly once")
    let record = matches[0]
    try require(try integer(record["layoutFixtureIndex"], "layout") == 11, "layout is not 11")
    try require(try integer(record["sourceScale"], "source scale") == 2, "source scale is not 2")
    try require(try integer(record["pixelWidth"], "width") == 393, "native width is not 393")
    try require(try integer(record["pixelHeight"], "height") == 852, "native height is not 852")
    try require(try string(record["fullPath"], "full path") == expectedFull, "full path differs")
    try require(try string(record["tilePath"], "tile path") == expectedTile, "tile path differs")
    return [
        "background": background,
        "fullPath": expectedFull,
        "layoutFixtureIndex": 11,
        "pixelHeight": 852,
        "pixelWidth": 393,
        "requestedColorCount": colors,
        "sourceScale": 2,
        "tilePath": expectedTile,
    ]
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw BuildFailure(description: "usage: build-blind-packet.swift <candidate-root> <baseline-root> <output-root>")
    }
    let candidateRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let baselineRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let outputRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let fm = FileManager.default
    try require(!fm.fileExists(atPath: outputRoot.path), "blind output root already exists")

    let expectedCandidateHash = "09c092ed48a969c81145b789da7f123106c21b124020c3122de7fbd2bf508852"
    let expectedBaselineHash = "c5fcd68d43b57443c56a7b9934566baf178ed46c5c2ef53d18b90b76b6ba1c51"
    let expectedCandidateCommit = "3e5f3095167889b3a9ae5a8145ef0103489e6e3c"
    let expectedBaselineCommit = "622b7b50e0a4594ab47889a2265748e51e94e523"
    let candidateHash = try readPackageHash(candidateRoot)
    let baselineHash = try readPackageHash(baselineRoot)
    try require(candidateHash == expectedCandidateHash, "candidate package hash differs")
    try require(baselineHash == expectedBaselineHash, "baseline package hash differs")

    let candidateManifest = try jsonObject(candidateRoot.appendingPathComponent("manifest.json"))
    let baselineManifest = try jsonObject(baselineRoot.appendingPathComponent("manifest.json"))
    try require(try string(candidateManifest["sourceCommit"], "candidate commit") == expectedCandidateCommit, "candidate commit differs")
    try require(try string(baselineManifest["sourceCommit"], "baseline commit") == expectedBaselineCommit, "baseline commit differs")
    let candidateViewport = try object(candidateManifest["viewport"], "candidate viewport")
    let baselineViewport = try object(baselineManifest["viewport"], "baseline viewport")
    try require(try canonicalJSON(candidateViewport) == canonicalJSON(baselineViewport), "viewport facts differ")
    try require(try integer(candidateViewport["scale"], "candidate scale") == 1, "candidate is not scale 1")
    try require(try integer(baselineViewport["scale"], "baseline scale") == 1, "baseline is not scale 1")

    for relative in ["corpus-manifest.json", "composition-approved.json", "composition-recipes.json"] {
        let candidateData = try Data(contentsOf: candidateRoot.appendingPathComponent(relative))
        let baselineData = try Data(contentsOf: baselineRoot.appendingPathComponent(relative))
        try require(candidateData == baselineData, "frozen input differs: \(relative)")
    }

    let candidateMetrics = try jsonObject(candidateRoot.appendingPathComponent("metrics.json"))
    let baselineMetrics = try jsonObject(baselineRoot.appendingPathComponent("metrics.json"))
    let backgrounds = ["light", "dark", "lowContrast"]
    var conditionSpecs: [(key: String, colors: Int, background: String)] = []
    for colors in 1...3 {
        for background in backgrounds {
            conditionSpecs.append(("c\(colors)-\(background)", colors, background))
        }
    }

    try fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
    var assignmentConditions: [[String: Any]] = []
    var packetConditions: [[String: Any]] = []
    var copyRecords: [[String: Any]] = []
    var criticFiles: [String] = []

    for spec in conditionSpecs {
        let stem = "scene-scale/outline/outline-colors-\(spec.colors)-\(spec.background)-layout-11"
        let fullRelative = "\(stem)-full@1x.png"
        let tileRelative = "\(stem)-tile@1x.png"
        let candidateDescriptor = try descriptor(
            metrics: candidateMetrics,
            colors: spec.colors,
            background: spec.background,
            expectedFull: fullRelative,
            expectedTile: tileRelative
        )
        let baselineDescriptor = try descriptor(
            metrics: baselineMetrics,
            colors: spec.colors,
            background: spec.background,
            expectedFull: fullRelative,
            expectedTile: tileRelative
        )
        try require(
            try canonicalJSON(candidateDescriptor) == canonicalJSON(baselineDescriptor),
            "condition facts differ: \(spec.key)"
        )

        var assignmentInput = Data("day-objects-outline-task1b-ab-v1".utf8)
        assignmentInput.append(0)
        assignmentInput.append(Data(candidateHash.utf8))
        assignmentInput.append(0)
        assignmentInput.append(Data(baselineHash.utf8))
        assignmentInput.append(0)
        assignmentInput.append(Data(spec.key.utf8))
        let assignmentDigest = SHA256.hash(data: assignmentInput)
        let bit = Int(Array(assignmentDigest)[0] & 1)
        let aIdentity = bit == 0 ? "candidate" : "baseline"
        let bIdentity = bit == 0 ? "baseline" : "candidate"
        let identityRoots = ["candidate": candidateRoot, "baseline": baselineRoot]

        let pairRelativeRoot = "pairs/\(spec.key)"
        let pairRoot = outputRoot.appendingPathComponent(pairRelativeRoot, isDirectory: true)
        try fm.createDirectory(at: pairRoot, withIntermediateDirectories: true)
        var neutralSides: [String: [String: Any]] = [:]
        for (label, identity) in [("A", aIdentity), ("B", bIdentity)] {
            guard let sourceRoot = identityRoots[identity] else {
                throw BuildFailure(description: "missing identity root")
            }
            var neutralViews: [String: Any] = [:]
            for (view, sourceRelative) in [("full", fullRelative), ("tile", tileRelative)] {
                let sourceURL = sourceRoot.appendingPathComponent(sourceRelative)
                let copiedRelative = "\(pairRelativeRoot)/\(label)-\(view).png"
                let copiedURL = outputRoot.appendingPathComponent(copiedRelative)
                let sourceData = try Data(contentsOf: sourceURL)
                let decoded = try image(sourceURL)
                if view == "full" {
                    try require(decoded.width == 393 && decoded.height == 852, "full dimensions differ")
                } else {
                    try require(decoded.width == 393 && decoded.height == 393, "tile dimensions differ")
                }
                try writeNew(sourceData, to: copiedURL)
                let copiedData = try Data(contentsOf: copiedURL)
                try require(copiedData == sourceData, "copied bytes differ")
                let digest = sha256(sourceData)
                neutralViews["\(view)Path"] = copiedRelative
                neutralViews["\(view)SHA256"] = digest
                copyRecords.append([
                    "conditionKey": spec.key,
                    "copiedPath": copiedRelative,
                    "copiedSHA256": sha256(copiedData),
                    "identity": identity,
                    "label": label,
                    "sourcePath": sourceURL.path,
                    "sourceSHA256": digest,
                    "view": view,
                ])
                criticFiles.append(copiedRelative)
            }
            neutralSides[label] = neutralViews
        }

        for identityRoot in [candidateRoot, baselineRoot] {
            let fullImage = try image(identityRoot.appendingPathComponent(fullRelative))
            let tileImage = try image(identityRoot.appendingPathComponent(tileRelative))
            guard let crop = fullImage.cropping(to: CGRect(x: 0, y: 229, width: 393, height: 393)) else {
                throw BuildFailure(description: "cannot crop \(spec.key)")
            }
            try require(try normalizedRGBA(crop) == normalizedRGBA(tileImage), "full/tile crop differs: \(spec.key)")
        }

        assignmentConditions.append([
            "AIdentity": aIdentity,
            "BIdentity": bIdentity,
            "assignmentBit": bit,
            "assignmentInputSHA256": sha256(assignmentInput),
            "conditionKey": spec.key,
            "fullSourceRelativePath": fullRelative,
            "tileSourceRelativePath": tileRelative,
        ])
        packetConditions.append([
            "A": neutralSides["A"]!,
            "B": neutralSides["B"]!,
            "conditionKey": spec.key,
            "displayFacts": [
                "background": spec.background,
                "requestedColorCount": spec.colors,
            ],
        ])
    }

    let assignment: [String: Any] = [
        "assignmentFormula": "SHA256(domain\\0candidatePackageHash\\0baselinePackageHash\\0conditionKey).firstByte & 1",
        "baselinePackageHash": baselineHash,
        "baselineSourceCommit": expectedBaselineCommit,
        "candidatePackageHash": candidateHash,
        "candidateSourceCommit": expectedCandidateCommit,
        "conditions": assignmentConditions,
        "domain": "day-objects-outline-task1b-ab-v1",
        "version": "day-objects-outline-task1b-ab-assignment-v1",
    ]
    let assignmentData = try canonicalJSON(assignment)
    try writeNew(assignmentData, to: outputRoot.appendingPathComponent("assignment.json"))
    try writeNew(
        Data("\(sha256(assignmentData))  assignment.json\n".utf8),
        to: outputRoot.appendingPathComponent("assignment.sha256")
    )

    let copyLedger: [String: Any] = [
        "baselinePackageHash": baselineHash,
        "candidatePackageHash": candidateHash,
        "recordCount": copyRecords.count,
        "records": copyRecords,
        "version": "day-objects-outline-task1b-copy-ledger-v1",
    ]
    let copyLedgerData = try canonicalJSON(copyLedger)
    try writeNew(copyLedgerData, to: outputRoot.appendingPathComponent("source-copy-ledger.json"))

    let packet: [String: Any] = [
        "comparisonFacts": [
            "bytesCopiedWithoutReencoding": true,
            "conditionCount": 9,
            "fullTilePairSharesOneLabel": true,
        ],
        "conditions": packetConditions,
        "inspectionInstruction": "Inspect all nine neutral A/B full-screen and calendar-tile pairs; lock observations before identity reveal.",
        "version": "day-objects-outline-task1b-critic-packet-v1",
        "viewport": [
            "fullHeightPixels": 852,
            "fullWidthPixels": 393,
            "tileCrop": ["height": 393, "width": 393, "x": 0, "y": 229],
            "tileHeightPixels": 393,
            "tileWidthPixels": 393,
        ],
    ]
    let packetData = try canonicalJSON(packet)
    let lowerPacket = String(decoding: packetData, as: UTF8.self).lowercased()
    for forbidden in [
        "candidate", "baseline", "sourcecommit", "packagehash",
        expectedCandidateCommit, expectedBaselineCommit, candidateHash, baselineHash,
    ] {
        try require(!lowerPacket.contains(forbidden.lowercased()), "critic packet identity leak: \(forbidden)")
    }
    try writeNew(packetData, to: outputRoot.appendingPathComponent("packet-manifest.json"))
    criticFiles.append("packet-manifest.json")
    criticFiles.sort()

    var criticChecksums = Data()
    for relative in criticFiles {
        let data = try Data(contentsOf: outputRoot.appendingPathComponent(relative))
        criticChecksums.append(Data("\(sha256(data))  \(relative)\n".utf8))
    }
    try writeNew(
        Data(criticFiles.joined(separator: "\n").appending("\n").utf8),
        to: outputRoot.appendingPathComponent("critic-packet-files.txt")
    )
    try writeNew(criticChecksums, to: outputRoot.appendingPathComponent("critic-packet-SHA256SUMS"))

    try require(copyRecords.count == 36, "copy record count is not 36")
    try require(criticFiles.count == 37, "critic packet allowlist count is not 37")
    print("BLIND_PACKET_BUILD: PASS")
    print("condition_count=9")
    print("copied_image_count=36")
    print("critic_packet_allowlist_count=37")
    print("candidate_package_hash=\(candidateHash)")
    print("baseline_package_hash=\(baselineHash)")
    print("assignment_sha256=\(sha256(assignmentData))")
    print("packet_manifest_sha256=\(sha256(packetData))")
    print("critic_packet_checksums_sha256=\(sha256(criticChecksums))")
    print("identity_leak_scan=PASS")
    print("source_copy_byte_identity=36/36")
    print("full_tile_crop_equality=18/18")
} catch {
    fputs("BLIND_PACKET_BUILD: FAIL\n\(error)\n", stderr)
    exit(1)
}
