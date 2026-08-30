import Darwin
import Foundation
import EditorialFieldCore
import EditorialFieldEvidence
import EditorialFieldRender

enum RenderCLIError: Error, LocalizedError {
    case usage(String)
    case missingOption(String)
    case invalidOverlay(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): message
        case .missingOption(let option): "Missing required option \(option)"
        case .invalidOverlay(let value): "Unknown overlay '\(value)'"
        }
    }
}

private let usage = """
Usage:
  editorial-field-render composition --manifest <path> --output <round-dir> [--source-commit <hash>] [--overlays all|none|crop,overlap,centerOfMass,occupiedBounds]
  editorial-field-render verify --package <round-dir>
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
    case "verify":
        let packageURL = URL(fileURLWithPath: try option("--package", in: arguments), isDirectory: true)
        let packageHash = try EvidencePackage.verify(directory: packageURL)
        print("verified package SHA-256: \(packageHash)")
    default:
        throw RenderCLIError.usage(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n\(usage)\n".utf8))
    exit(1)
}
