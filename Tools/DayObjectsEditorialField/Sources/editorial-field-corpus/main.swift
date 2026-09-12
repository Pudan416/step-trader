import CryptoKit
import EditorialFieldCore
import Foundation

enum CorpusCommandError: LocalizedError {
    case usage
    case missingValue(String)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: editorial-field-corpus visible --output <path> | verify --manifest <path>"
        case let .missingValue(option):
            return "Missing value for \(option)."
        case let .verificationFailed(message):
            return message
        }
    }
}

@main
struct EditorialFieldCorpusCommand {
    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            throw CorpusCommandError.usage
        }

        switch command {
        case "visible":
            let output = try optionValue("--output", in: Array(arguments.dropFirst()))
            let data = try CorpusManifest.visibleV1().canonicalJSON()
            let url = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            print("Wrote visible corpus: \(output)")
        case "verify":
            let path = try optionValue("--manifest", in: Array(arguments.dropFirst()))
            let actual = try Data(contentsOf: URL(fileURLWithPath: path))
            let expected = try CorpusManifest.visibleV1().canonicalJSON()
            guard actual == expected else {
                throw CorpusCommandError.verificationFailed(
                    "Manifest does not match the canonical visible-v1 corpus. Regenerate it with `visible --output \(path)`.")
            }

            let manifest = CorpusManifest.visibleV1()
            let seeds = manifest.breadth.map(\.seed) + [manifest.continuity.seed] + manifest.stress.map(\.seed)
            let duplicateSeedCount = seeds.count - Set(seeds).count
            let hash = SHA256.hash(data: actual).map { String(format: "%02x", $0) }.joined()
            print("Manifest SHA-256: \(hash)")
            print("Breadth fixtures: \(manifest.breadth.count)")
            print("Continuity stages: \(manifest.continuity.stages.count)")
            print("Stress fixtures: \(manifest.stress.count)")
            print("Duplicate seeds: \(duplicateSeedCount)")
        default:
            throw CorpusCommandError.usage
        }
    }

    static func optionValue(_ option: String, in arguments: [String]) throws -> String {
        guard let optionIndex = arguments.firstIndex(of: option) else {
            throw CorpusCommandError.usage
        }
        let valueIndex = arguments.index(after: optionIndex)
        guard arguments.indices.contains(valueIndex) else {
            throw CorpusCommandError.missingValue(option)
        }
        return arguments[valueIndex]
    }
}
