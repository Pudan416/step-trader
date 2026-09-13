import Darwin
import Foundation
import EditorialFieldCore
import EditorialFieldEvidence
import EditorialFieldRender

enum RenderCLIError: Error, LocalizedError {
    case usage(String)
    case missingOption(String)
    case invalidOverlay(String)
    case invalidOption(name: String, value: String)
    case missingFixture(Int)

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        case .missingOption(let option): "Missing required option \(option)"
        case .invalidOverlay(let value): "Unknown overlay '\(value)'"
        case .invalidOption(let name, let value): "Invalid \(name) value '\(value)'"
        case .missingFixture(let index): "Composition fixture \(index) was not found"
        }
    }
}

private let usage = """
Usage:
  editorial-field-render composition --manifest <path> --output <round-dir> [--source-commit <hash>] [--overlays all|none|crop,overlap,centerOfMass,occupiedBounds]
  editorial-field-render material --manifest <path> --composition-approval <path> --composition-recipes <path> --output <round-dir> [--source-commit <hash>] [--scale <positive-integer>]
  editorial-field-render preview-frame --composition-recipes <path> --fixture-index <index> --output <dir> [--background light|dark|warm|cool|saturated|lowContrast] [--elapsed-time <seconds>] [--steps normal|low] [--reduce-motion] [--scale <positive-integer>]
  editorial-field-render verify --package <round-dir> --expected-source-commit <full-git-object-id>
  editorial-field-render verify-material --package <round-dir> --composition-approval <path> --composition-recipes <path> --expected-source-commit <full-git-object-id>
"""

private func option(_ name: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        throw RenderCLIError.missingOption(name)
    }
    return arguments[index + 1]
}

private func overlays(in arguments: [String]) throws -> Set<NeutralOverlay> {
    guard let index = arguments.firstIndex(of: "--overlays") else {
        return Set(NeutralOverlay.allCases)
    }
    guard arguments.indices.contains(index + 1) else {
        throw RenderCLIError.missingOption("--overlays")
    }
    let value = arguments[index + 1]
    if value == "all" { return Set(NeutralOverlay.allCases) }
    if value == "none" { return [] }
    var result = Set<NeutralOverlay>()
    for token in value.split(separator: ",").map(String.init) {
        guard let overlay = NeutralOverlay(rawValue: token) else {
            throw RenderCLIError.invalidOverlay(token)
        }
        result.insert(overlay)
    }
    return result
}

private func currentSourceCommit() -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "HEAD"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "unknown" }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return "unknown"
    }
}

private func positiveIntegerOption(
    _ name: String,
    in arguments: [String],
    default defaultValue: Int
) throws -> Int {
    guard arguments.contains(name) else { return defaultValue }
    let value = try option(name, in: arguments)
    guard let integer = Int(value), integer > 0 else {
        throw RenderCLIError.usage("\(name) must be a positive integer")
    }
    return integer
}

private func integerOption(_ name: String, in arguments: [String]) throws -> Int {
    let value = try option(name, in: arguments)
    guard let integer = Int(value) else {
        throw RenderCLIError.invalidOption(name: name, value: value)
    }
    return integer
}

private func doubleOption(
    _ name: String,
    in arguments: [String],
    default defaultValue: Double
) throws -> Double {
    guard arguments.contains(name) else { return defaultValue }
    let value = try option(name, in: arguments)
    guard let number = Double(value), number.isFinite else {
        throw RenderCLIError.invalidOption(name: name, value: value)
    }
    return number
}

private func enumOption<Value: RawRepresentable>(
    _ name: String,
    in arguments: [String],
    default defaultValue: Value
) throws -> Value where Value.RawValue == String {
    guard arguments.contains(name) else { return defaultValue }
    let value = try option(name, in: arguments)
    guard let result = Value(rawValue: value) else {
        throw RenderCLIError.invalidOption(name: name, value: value)
    }
    return result
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw RenderCLIError.usage(usage) }
    switch command {
    case "composition":
        let manifestURL = URL(fileURLWithPath: try option("--manifest", in: arguments))
        let outputURL = URL(fileURLWithPath: try option("--output", in: arguments), isDirectory: true)
        let manifest = try JSONDecoder().decode(
            CorpusManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let sourceCommit: String
        if arguments.contains("--source-commit") {
            sourceCommit = try option("--source-commit", in: arguments)
        } else {
            sourceCommit = currentSourceCommit()
        }
        let generated = try EvidencePackage.generateComposition(
            manifest: manifest,
            sourceCommit: sourceCommit,
            outputDirectory: outputURL,
            renderConfiguration: .init(scale: 3, overlays: try overlays(in: arguments))
        )
        print("composition evidence: \(generated.outputDirectory.path)")
        print("core PNG views: \(generated.manifest.coreImageCount)")
        print("artifact records: \(generated.manifest.artifacts.count)")
        print("package SHA-256: \(generated.packageHash)")
    case "material":
        let manifestURL = URL(fileURLWithPath: try option("--manifest", in: arguments))
        let approvalURL = URL(fileURLWithPath: try option("--composition-approval", in: arguments))
        let recipesURL = URL(fileURLWithPath: try option("--composition-recipes", in: arguments))
        let outputURL = URL(fileURLWithPath: try option("--output", in: arguments), isDirectory: true)
        let manifest = try JSONDecoder().decode(
            CorpusManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let sourceCommit: String
        if arguments.contains("--source-commit") {
            sourceCommit = try option("--source-commit", in: arguments)
        } else {
            sourceCommit = currentSourceCommit()
        }
        let generated = try MaterialEvidencePackage.generate(
            manifest: manifest,
            compositionApprovalData: Data(contentsOf: approvalURL),
            compositionRecipeArchiveData: Data(contentsOf: recipesURL),
            sourceCommit: sourceCommit,
            outputDirectory: outputURL,
            scale: try positiveIntegerOption("--scale", in: arguments, default: 3)
        )
        print("material evidence: \(generated.outputDirectory.path)")
        print("material fixtures: \(generated.manifest.fixtureCount)")
        print("core PNG views: \(generated.manifest.coreImageCount)")
        print("artifact records: \(generated.manifest.artifacts.count)")
        print("composition approval SHA-256: \(generated.manifest.compositionApprovalSHA256)")
        print("composition recipes SHA-256: \(generated.manifest.compositionRecipeArchiveSHA256)")
        print("package SHA-256: \(generated.packageHash)")
    case "preview-frame":
        let recipesURL = URL(fileURLWithPath: try option("--composition-recipes", in: arguments))
        let fixtureIndex = try integerOption("--fixture-index", in: arguments)
        let outputURL = URL(fileURLWithPath: try option("--output", in: arguments), isDirectory: true)
        let archive = try JSONDecoder().decode(
            FrozenCompositionRecipeArchive.self,
            from: Data(contentsOf: recipesURL)
        )
        guard let recipe = archive.fixtures.first(where: { $0.fixtureIndex == fixtureIndex })?.recipe else {
            throw RenderCLIError.missingFixture(fixtureIndex)
        }
        let background: BackgroundCondition = try enumOption(
            "--background",
            in: arguments,
            default: .lowContrast
        )
        let steps: StepCondition = try enumOption(
            "--steps",
            in: arguments,
            default: .normal
        )
        let elapsedTime = try doubleOption("--elapsed-time", in: arguments, default: 0)
        let motion = MotionField.make(
            daySeed: recipe.daySeed,
            eventIDs: recipe.actors.map(\.eventID)
        )
        let rendered = try MotionRenderer().render(
            recipe: recipe,
            material: MaterialDNA.make(
                daySeed: recipe.daySeed,
                eventIDs: recipe.actors.map(\.eventID)
            ),
            motionRecipes: motion,
            background: background,
            elapsedTime: elapsedTime,
            steps: steps,
            reduceMotion: arguments.contains("--reduce-motion"),
            configuration: .init(
                scale: try positiveIntegerOption("--scale", in: arguments, default: 1)
            )
        )
        try FileManager.default.createDirectory(
            at: outputURL,
            withIntermediateDirectories: true
        )
        try rendered.fullScreen.pngData.write(
            to: outputURL.appendingPathComponent("full.png"),
            options: .atomic
        )
        try rendered.calendarTile.pngData.write(
            to: outputURL.appendingPathComponent("tile.png"),
            options: .atomic
        )
        print("preview frame: \(outputURL.path)")
        print("fixture index: \(fixtureIndex)")
        print("actors: \(recipe.actors.count)")
        print("background: \(background.rawValue)")
        print("elapsed time: \(elapsedTime)")
        print("steps: \(steps.rawValue)")
        print("reduce motion: \(arguments.contains("--reduce-motion"))")
    case "verify":
        let packageURL = URL(fileURLWithPath: try option("--package", in: arguments), isDirectory: true)
        let expectedSourceCommit = try option("--expected-source-commit", in: arguments)
        let packageHash = try EvidencePackage.verify(
            directory: packageURL,
            expectedSourceCommit: expectedSourceCommit
        )
        print("verified package SHA-256: \(packageHash)")
    case "verify-material":
        let packageURL = URL(fileURLWithPath: try option("--package", in: arguments), isDirectory: true)
        let approvalURL = URL(fileURLWithPath: try option("--composition-approval", in: arguments))
        let recipesURL = URL(fileURLWithPath: try option("--composition-recipes", in: arguments))
        let expectedSourceCommit = try option("--expected-source-commit", in: arguments)
        let packageHash = try MaterialEvidencePackage.verify(
            directory: packageURL,
            expectedSourceCommit: expectedSourceCommit,
            expectedCompositionApprovalData: Data(contentsOf: approvalURL),
            expectedCompositionRecipeArchiveData: Data(contentsOf: recipesURL)
        )
        print("verified material package SHA-256: \(packageHash)")
    default:
        throw RenderCLIError.usage(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n\(usage)\n".utf8))
    exit(1)
}
