import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AuditFailure: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw AuditFailure(description: message) }
}

func object(_ value: Any?, _ context: String) throws -> [String: Any] {
    guard let result = value as? [String: Any] else {
        throw AuditFailure(description: "expected object: \(context)")
    }
    return result
}

func array(_ value: Any?, _ context: String) throws -> [Any] {
    guard let result = value as? [Any] else {
        throw AuditFailure(description: "expected array: \(context)")
    }
    return result
}

func string(_ value: Any?, _ context: String) throws -> String {
    guard let result = value as? String else {
        throw AuditFailure(description: "expected string: \(context)")
    }
    return result
}

func integer(_ value: Any?, _ context: String) throws -> Int {
    guard let result = value as? NSNumber else {
        throw AuditFailure(description: "expected integer: \(context)")
    }
    return result.intValue
}

func boolean(_ value: Any?, _ context: String) throws -> Bool {
    guard let result = value as? Bool else {
        throw AuditFailure(description: "expected boolean: \(context)")
    }
    return result
}

func jsonObject(_ url: URL) throws -> [String: Any] {
    try object(
        JSONSerialization.jsonObject(with: Data(contentsOf: url)),
        url.path
    )
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
    }
}

func png(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetType(source) as String? == UTType.png.identifier,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw AuditFailure(description: "cannot decode PNG: \(url.path)") }
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
    try require(rendered, "cannot normalize image RGBA")
    return data
}

func relativeFiles(_ root: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ) else { throw AuditFailure(description: "cannot enumerate: \(root.path)") }
    var result: [String] = []
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.hasPrefix(".") }) {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
            }
            continue
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        result.append(relative)
    }
    return result.sorted()
}

func recursiveDigest(_ root: URL) throws -> String {
    let files = try relativeFiles(root)
    var ledger = Data()
    for relative in files {
        let data = try Data(contentsOf: root.appendingPathComponent(relative))
        ledger.append(Data("\(sha256(data))  \(relative)\n".utf8))
    }
    return sha256(ledger)
}

func comparePackages(_ lhs: URL, _ rhs: URL, label: String) throws -> String {
    let lhsFiles = try relativeFiles(lhs)
    let rhsFiles = try relativeFiles(rhs)
    try require(lhsFiles == rhsFiles, "\(label) relative inventories differ")
    try require(lhsFiles.count == 261, "\(label) expected 261 files")
    var ledger = Data()
    for relative in lhsFiles {
        let lhsData = try Data(contentsOf: lhs.appendingPathComponent(relative))
        let rhsData = try Data(contentsOf: rhs.appendingPathComponent(relative))
        try require(lhsData == rhsData, "\(label) byte mismatch: \(relative)")
        ledger.append(Data("\(sha256(lhsData))  \(relative)\n".utf8))
    }
    return sha256(ledger)
}

let families = [
    "gradient", "solid", "sphere", "glass", "mist",
    "halo", "luminous", "outline", "counterform",
]
let backgrounds = ["light", "dark", "lowContrast"]
let contactSheets: Set<String> = [
    "contact-sheets/material-atlas.png",
    "contact-sheets/family-optics.png",
    "contact-sheets/outline-counterform.png",
    "contact-sheets/scene-scale-full.png",
    "contact-sheets/scene-scale-tile.png",
]
let expectedCommit = "3e5f3095167889b3a9ae5a8145ef0103489e6e3c"

struct PackageAudit {
    let root: URL
    let scale: Int
    let sceneScalePaths: [String]
    let outlineScenePaths: [String]
    let sceneScaleCanonicalJSON: Data
    let authorityRecordCount: Int
    let authorityInvocationCount: Int
    let authorityCanonicalSHA256: String
}

func validatePackage(
    root: URL,
    scale: Int,
    externalApproval: Data,
    externalRecipes: Data
) throws -> PackageAudit {
    let files = try relativeFiles(root)
    try require(files.count == 261, "scale\(scale) package file count != 261")

    let manifest = try jsonObject(root.appendingPathComponent("manifest.json"))
    let metrics = try jsonObject(root.appendingPathComponent("metrics.json"))
    try require(try string(manifest["sourceCommit"], "manifest.sourceCommit") == expectedCommit, "source commit mismatch")
    try require(try integer(manifest["fixtureCount"], "manifest.fixtureCount") == 27, "manifest fixture count")
    try require(try integer(manifest["coreImageCount"], "manifest.coreImageCount") == 54, "manifest core image count")
    try require(try array(manifest["artifacts"], "manifest.artifacts").count == 258, "manifest artifact count")
    try require(try string(metrics["version"], "metrics.version") == "material-metrics-v9", "metrics version")
    try require(
        try string(metrics["outlinePresentationAuthorityVersion"], "metrics.authorityVersion")
            == "outline-presentation-authority-v1",
        "outline authority version"
    )
    try require(try integer(metrics["fixtureCount"], "metrics.fixtureCount") == 27, "metrics fixture count")
    try require(try integer(metrics["coreImageCount"], "metrics.coreImageCount") == 54, "metrics core image count")
    try require(
        try Data(contentsOf: root.appendingPathComponent("composition-approved.json")) == externalApproval,
        "composition approval bytes differ"
    )
    try require(
        try Data(contentsOf: root.appendingPathComponent("composition-recipes.json")) == externalRecipes,
        "composition recipe bytes differ"
    )
    try require(
        try string(manifest["compositionApprovalSHA256"], "manifest.approvalSHA") == sha256(externalApproval),
        "approval digest mismatch"
    )
    try require(
        try string(manifest["compositionRecipeArchiveSHA256"], "manifest.recipesSHA") == sha256(externalRecipes),
        "recipe digest mismatch"
    )

    let packageHash = try String(contentsOf: root.appendingPathComponent("package-hash.txt"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    try require(isSHA256(packageHash), "invalid package hash")

    let sceneRecords = try array(metrics["sceneScale"], "metrics.sceneScale")
    try require(sceneRecords.count == 81, "expected 81 scene-scale records")
    var sceneKeys = Set<String>()
    var scenePaths: [String] = []
    var outlinePaths: [String] = []
    var authorityRecords: [[String: Any]] = []
    var authorityInvocations = Set<String>()
    var topologyCount = 0

    for rawRecord in sceneRecords {
        let record = try object(rawRecord, "sceneScale record")
        let family = try string(record["family"], "sceneScale.family")
        let background = try string(record["background"], "sceneScale.background")
        let colors = try integer(record["requestedColorCount"], "sceneScale.requestedColorCount")
        try require(families.contains(family), "unknown family \(family)")
        try require(backgrounds.contains(background), "unknown background \(background)")
        try require((1...3).contains(colors), "invalid color count")
        try require(try integer(record["layoutFixtureIndex"], "sceneScale.layoutFixtureIndex") == 11, "scene layout != 11")
        try require(try integer(record["sourceScale"], "sceneScale.sourceScale") == 2, "scene source scale != 2")
        try require(try integer(record["pixelWidth"], "sceneScale.pixelWidth") == 393, "scene width != 393")
        try require(try integer(record["pixelHeight"], "sceneScale.pixelHeight") == 852, "scene height != 852")
        let key = "\(family)|\(colors)|\(background)"
        try require(sceneKeys.insert(key).inserted, "duplicate scene key \(key)")

        let fullPath = try string(record["fullPath"], "sceneScale.fullPath")
        let tilePath = try string(record["tilePath"], "sceneScale.tilePath")
        try require(fullPath.hasSuffix("full@1x.png"), "scene full is not native 1x")
        try require(tilePath.hasSuffix("tile@1x.png"), "scene tile is not native 1x")
        scenePaths.append(contentsOf: [fullPath, tilePath])
        if family == "outline" { outlinePaths.append(contentsOf: [fullPath, tilePath]) }

        let full = try png(root.appendingPathComponent(fullPath))
        let tile = try png(root.appendingPathComponent(tilePath))
        try require(full.width == 393 && full.height == 852, "native full dimensions: \(fullPath)")
        try require(tile.width == 393 && tile.height == 393, "native tile dimensions: \(tilePath)")
        guard let expectedTile = full.cropping(to: CGRect(x: 0, y: 229, width: 393, height: 393)) else {
            throw AuditFailure(description: "cannot crop native full: \(fullPath)")
        }
        try require(try normalizedRGBA(expectedTile) == normalizedRGBA(tile), "tile crop pixel mismatch: \(tilePath)")

        if family == "outline" {
            let actors = try array(record["actors"], "outline actors")
            try require(actors.count == 10, "outline condition does not have 10 actors")
            var eventIDs = Set<String>()
            var drawOrder = Set<Int>()
            var conditionInvocation: String?
            for rawActor in actors {
                let actor = try object(rawActor, "outline actor")
                let eventID = try string(actor["eventID"], "outline actor eventID")
                try require(eventIDs.insert(eventID).inserted, "duplicate outline actor eventID")
                _ = try boolean(actor["eligible"], "outline actor eligible")
                try require(try boolean(actor["passes"], "outline actor passes"), "outline actor fails")
                for presentationName in ["fullPresentation", "tilePresentation"] {
                    let presentation = try object(actor[presentationName], presentationName)
                    for key in [
                        "angularCoverage", "croppedRayCount", "inFrameRayCount",
                        "observableOwnedRayCount", "occludedRayCount", "supportedRayCount",
                    ] {
                        try require(presentation[key] != nil, "missing \(presentationName).\(key)")
                    }
                }
                let authority = try object(actor["outlinePresentationAuthority"], "outline authority")
                try require(try string(authority["eventID"], "authority.eventID") == eventID, "authority actor identity mismatch")
                let index = try integer(authority["drawOrderIndex"], "authority.drawOrderIndex")
                try require(drawOrder.insert(index).inserted, "duplicate draw-order index")
                try require(try string(authority["fullVisiblePath"], "authority.fullPath") == fullPath, "authority full path mismatch")
                try require(try string(authority["tileVisiblePath"], "authority.tilePath") == tilePath, "authority tile path mismatch")
                try require(try integer(authority["sourceScale"], "authority.sourceScale") == 2, "authority source scale")
                try require(try integer(authority["presentationScale"], "authority.presentationScale") == 1, "authority presentation scale")
                let crop = try object(authority["tileCrop"], "authority.tileCrop")
                try require(
                    try integer(crop["x"], "crop.x") == 0
                        && integer(crop["y"], "crop.y") == 229
                        && integer(crop["width"], "crop.width") == 393
                        && integer(crop["height"], "crop.height") == 393,
                    "authority crop mismatch"
                )
                let fullTrace = try object(authority["fullTrace"], "authority.fullTrace")
                let tileTrace = try object(authority["tileTrace"], "authority.tileTrace")
                try require(
                    try integer(fullTrace["width"], "fullTrace.width") == 393
                        && integer(fullTrace["height"], "fullTrace.height") == 852,
                    "full trace dimensions"
                )
                try require(
                    try integer(tileTrace["width"], "tileTrace.width") == 393
                        && integer(tileTrace["height"], "tileTrace.height") == 393,
                    "tile trace dimensions"
                )
                try require(try isSHA256(string(fullTrace["alphaSHA256"], "fullTrace.sha")), "full trace SHA")
                try require(try isSHA256(string(tileTrace["alphaSHA256"], "tileTrace.sha")), "tile trace SHA")
                let invocation = try string(authority["sourceRenderInvocationSHA256"], "authority.invocation")
                try require(isSHA256(invocation), "invalid render invocation SHA")
                if let conditionInvocation {
                    try require(conditionInvocation == invocation, "actors do not share condition render invocation")
                } else {
                    conditionInvocation = invocation
                }
                authorityRecords.append(authority)
            }
            try require(drawOrder == Set(0..<10), "draw order is not 0...9")
            if let conditionInvocation { authorityInvocations.insert(conditionInvocation) }
            let topology = try array(record["topology"], "outline topology")
            try require(!topology.isEmpty, "outline topology is empty")
            topologyCount += topology.count
            for rawTopology in topology {
                let measurement = try object(rawTopology, "outline topology measurement")
                try require(try boolean(measurement["eligible"], "topology eligible"), "topology record is not eligible")
                try require(try boolean(measurement["passes"], "topology passes"), "topology record fails")
                for key in [
                    "fullAlphaBands", "tileAlphaBands", "fullOpenCenterMargin", "tileOpenCenterMargin",
                    "fullThicknessRange", "tileThicknessRange", "fullCenterToRimRatio", "tileCenterToRimRatio",
                ] {
                    try require(measurement[key] != nil, "missing topology field \(key)")
                }
            }
        }
    }
    try require(sceneKeys.count == 81, "scene condition matrix is incomplete")
    try require(scenePaths.count == 162 && Set(scenePaths).count == 162, "scene path inventory != 162")
    try require(outlinePaths.count == 18 && Set(outlinePaths).count == 18, "outline native path inventory != 18")
    try require(authorityRecords.count == 90, "authority actor-condition records != 90")
    try require(authorityInvocations.count == 9, "authority render invocation count != 9")
    try require(topologyCount == 9, "eligible outline topology records != 9")

    var expectedOutlinePaths = Set<String>()
    for colors in 1...3 {
        for background in backgrounds {
            let stem = "scene-scale/outline/outline-colors-\(colors)-\(background)-layout-11"
            expectedOutlinePaths.insert("\(stem)-full@1x.png")
            expectedOutlinePaths.insert("\(stem)-tile@1x.png")
        }
    }
    try require(Set(outlinePaths) == expectedOutlinePaths, "exact 18 outline paths differ")

    let familyCrops = try array(metrics["familyCrops"], "metrics.familyCrops")
    try require(familyCrops.count == 27, "family crop count != 27")
    var familyCropKeys = Set<String>()
    for rawCrop in familyCrops {
        let crop = try object(rawCrop, "family crop")
        let family = try string(crop["family"], "familyCrop.family")
        let colors = try integer(crop["requestedColorCount"], "familyCrop.colors")
        try require(familyCropKeys.insert("\(family)|\(colors)").inserted, "duplicate family crop")
        let path = try string(crop["path"], "familyCrop.path")
        try require(path.hasSuffix("@\(scale)x.png"), "family crop scale suffix")
        let size = try integer(crop["pixelSize"], "familyCrop.pixelSize")
        let image = try png(root.appendingPathComponent(path))
        try require(image.width == size && image.height == size, "family crop dimensions")
    }
    try require(familyCropKeys.count == 27, "family crop matrix incomplete")

    let topologyCrops = try array(metrics["exactTopologyCrops"], "metrics.exactTopologyCrops")
    try require(topologyCrops.count == 6, "exact topology crop count != 6")
    var topologyFamilies: [String: Int] = [:]
    for rawCrop in topologyCrops {
        let crop = try object(rawCrop, "topology crop")
        let family = try string(crop["family"], "topologyCrop.family")
        topologyFamilies[family, default: 0] += 1
        try require(["outline", "halo"].contains(family), "unexpected topology crop family")
        try require(try integer(crop["scale"], "topologyCrop.scale") == scale, "topology crop scale")
        let path = try string(crop["path"], "topologyCrop.path")
        try require(path.hasSuffix("@\(scale)x.png"), "topology crop suffix")
        let image = try png(root.appendingPathComponent(path))
        try require(
            image.width == (try integer(crop["pixelWidth"], "topologyCrop.width"))
                && image.height == (try integer(crop["pixelHeight"], "topologyCrop.height")),
            "topology crop dimensions"
        )
    }
    try require(topologyFamilies == ["outline": 3, "halo": 3], "topology crop family counts")

    let fixtures = try array(metrics["fixtures"], "metrics.fixtures")
    try require(fixtures.count == 27, "fixture metrics count != 27")
    var fixtureKeys = Set<String>()
    for rawFixture in fixtures {
        let fixture = try object(rawFixture, "fixture metrics")
        let descriptor = try object(fixture["fixture"], "fixture descriptor")
        let family = try string(descriptor["family"], "fixture.family")
        let colors = try integer(descriptor["requestedColorCount"], "fixture.colors")
        try require(fixtureKeys.insert("\(family)|\(colors)").inserted, "duplicate fixture")
    }
    try require(fixtureKeys.count == 27, "fixture family/color matrix incomplete")

    let packageContacts = Set(files.filter { $0.hasPrefix("contact-sheets/") && $0.hasSuffix(".png") })
    try require(packageContacts == contactSheets, "contact-sheet inventory differs")
    for path in contactSheets {
        let image = try png(root.appendingPathComponent(path))
        try require(image.width > 0 && image.height > 0, "empty contact sheet")
    }

    let renderedPNGs = files.filter { $0.hasPrefix("renders/") && $0.hasSuffix(".png") }
    try require(renderedPNGs.count == 54, "canonical rendered PNG count != 54")
    let actorPNGs = files.filter { $0.hasPrefix("actor-crops/") && $0.hasSuffix(".png") }
    try require(actorPNGs.count == 27, "actor crop PNG count != 27")
    let topologyPNGs = files.filter { $0.hasPrefix("exact-topology-crops/") && $0.hasSuffix(".png") }
    try require(topologyPNGs.count == 6, "topology crop PNG count != 6")
    let scenePNGs = files.filter { $0.hasPrefix("scene-scale/") && $0.hasSuffix(".png") }
    try require(scenePNGs.count == 162, "scene-scale PNG count != 162")

    for colors in 1...3 {
        let path = "actor-crops/outline/outline-colors-\(colors)@\(scale)x.png"
        try require(files.contains(path), "missing required outline actor crop: \(path)")
    }
    for path in [
        "exact-topology-crops/21-outline-0A9B16D9@\(scale)x.png",
        "exact-topology-crops/22-outline-2C9F4B58@\(scale)x.png",
        "exact-topology-crops/23-outline-4E6B83FD@\(scale)x.png",
    ] {
        try require(files.contains(path), "missing required outline topology crop: \(path)")
    }

    let canonical = [
        "21-outline-colors-01-dark-layout-09",
        "22-outline-colors-02-lowContrast-layout-10",
        "23-outline-colors-03-light-layout-11",
    ]
    for stem in canonical {
        let fullPath = "renders/outline/\(stem)-full@\(scale)x.png"
        let tilePath = "renders/outline/\(stem)-tile@\(scale)x.png"
        try require(files.contains(fullPath) && files.contains(tilePath), "missing canonical fixture \(stem)")
        let full = try png(root.appendingPathComponent(fullPath))
        let tile = try png(root.appendingPathComponent(tilePath))
        try require(full.width == 393 * scale && full.height == 852 * scale, "canonical full dimensions")
        try require(tile.width == 393 * scale && tile.height == 393 * scale, "canonical tile dimensions")
    }

    let canonicalScene = try JSONSerialization.data(withJSONObject: sceneRecords, options: [.sortedKeys])
    let canonicalAuthority = try JSONSerialization.data(withJSONObject: authorityRecords, options: [.sortedKeys])
    return PackageAudit(
        root: root,
        scale: scale,
        sceneScalePaths: scenePaths.sorted(),
        outlineScenePaths: outlinePaths.sorted(),
        sceneScaleCanonicalJSON: canonicalScene,
        authorityRecordCount: authorityRecords.count,
        authorityInvocationCount: authorityInvocations.count,
        authorityCanonicalSHA256: sha256(canonicalAuthority)
    )
}

do {
    guard CommandLine.arguments.count == 7 else {
        throw AuditFailure(description: "usage: audit.swift <s1-candidate> <s1-rerender> <s3-candidate> <s3-rerender> <approval> <recipes>")
    }
    let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    let scale1Candidate = urls[0]
    let scale1Rerender = urls[1]
    let scale3Candidate = urls[2]
    let scale3Rerender = urls[3]
    let externalApproval = try Data(contentsOf: urls[4])
    let externalRecipes = try Data(contentsOf: urls[5])

    let packageRoots = [scale1Candidate, scale1Rerender, scale3Candidate, scale3Rerender]
    let expectedRecursiveDigests = [
        "35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0",
        "35d5f7e2b640e010b9e0726237801bc26135b39aff1479a2dd06cd8bf29656c0",
        "fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b",
        "fc20e175697d53e0ccdb113db3ebb778c5d3d8e25f047ccdffe34f453228fd4b",
    ]
    let preAuditRecursiveDigests = try packageRoots.map(recursiveDigest)
    try require(
        preAuditRecursiveDigests == expectedRecursiveDigests,
        "pre-audit recursive package seals differ"
    )

    let scale1PairDigest = try comparePackages(scale1Candidate, scale1Rerender, label: "scale1")
    let scale3PairDigest = try comparePackages(scale3Candidate, scale3Rerender, label: "scale3")
    let s1 = try validatePackage(
        root: scale1Candidate,
        scale: 1,
        externalApproval: externalApproval,
        externalRecipes: externalRecipes
    )
    let s3 = try validatePackage(
        root: scale3Candidate,
        scale: 3,
        externalApproval: externalApproval,
        externalRecipes: externalRecipes
    )

    try require(s1.sceneScalePaths == s3.sceneScalePaths, "cross-scale native scene path inventories differ")
    var nativeLedger = Data()
    for relative in s1.sceneScalePaths {
        let scale1Data = try Data(contentsOf: scale1Candidate.appendingPathComponent(relative))
        let scale3Data = try Data(contentsOf: scale3Candidate.appendingPathComponent(relative))
        try require(scale1Data == scale3Data, "cross-scale native scene byte mismatch: \(relative)")
        nativeLedger.append(Data("\(sha256(scale1Data))  \(relative)\n".utf8))
    }
    try require(s1.outlineScenePaths == s3.outlineScenePaths, "cross-scale outline path inventories differ")
    try require(s1.sceneScaleCanonicalJSON == s3.sceneScaleCanonicalJSON, "cross-scale scene-scale metrics differ")
    try require(s1.authorityCanonicalSHA256 == s3.authorityCanonicalSHA256, "cross-scale authority records differ")
    let postAuditRecursiveDigests = try packageRoots.map(recursiveDigest)
    try require(
        postAuditRecursiveDigests == preAuditRecursiveDigests,
        "post-audit recursive package seals differ"
    )

    print("AUDIT: PASS")
    print("scale1_file_count=261")
    print("scale3_file_count=261")
    print("scale1_pair_recursive_digest=\(scale1PairDigest)")
    print("scale3_pair_recursive_digest=\(scale3PairDigest)")
    print("scene_scale_records=81")
    print("scene_scale_pngs=162")
    print("native_scene_cross_scale_byte_identity=PASS")
    print("native_scene_cross_scale_aggregate_sha256=\(sha256(nativeLedger))")
    print("outline_native_pngs=18")
    print("outline_authority_schema=material-metrics-v9/outline-presentation-authority-v1")
    print("outline_authority_actor_condition_records=\(s1.authorityRecordCount)")
    print("outline_authority_render_invocations=\(s1.authorityInvocationCount)")
    print("outline_authority_cross_scale_sha256=\(s1.authorityCanonicalSHA256)")
    print("family_actor_crops=27")
    print("exact_topology_crops=6")
    print("canonical_outline_fixtures=6")
    print("contact_sheets=5")
    print("full_to_tile_normalized_rgba_crops=81/81_per_candidate")
    print("pre_audit_recursive_seals=\(preAuditRecursiveDigests.joined(separator: ","))")
    print("post_audit_recursive_seals=\(postAuditRecursiveDigests.joined(separator: ","))")
    print("pre_post_recursive_seal_identity=PASS")
    print("aesthetic_verdict=NOT_PERFORMED")
} catch {
    fputs("AUDIT: FAIL\n\(error)\n", stderr)
    exit(1)
}
