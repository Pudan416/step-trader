#!/usr/bin/env swift
import Foundation

// Runs the app-hosted exporter, never a substitute desktop synthesis graph.
let usage = """
Usage: export_sound_world_auditions.swift --directory PATH [--seed UINT64]
       [--destination 'platform=iOS Simulator,name=iPhone 16e'] [--xctestrun PATH]

Exports 12 numbered 24s WAV mixes, 60 private stems, a manifest and quality
reports through the iOS app graph. PATH must be absent or empty. The default
seed is 15321439165460004865. Quality issues are recorded for calibration;
infrastructure errors stop once. Existing WAVs are never overwritten.
Without --xctestrun, builds the app/tests into a new temporary directory.
"""

enum ExportCommandError: Error { case usage(String), command(Int32), missingTestRun, missingTestTarget }

func run(_ arguments: [String], at directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ExportCommandError.command(process.terminationStatus) }
}

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") || arguments.contains("-h") { print(usage); return }
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard ["--directory", "--seed", "--destination", "--xctestrun"].contains(key),
              index + 1 < arguments.count, options[key] == nil else {
            throw ExportCommandError.usage("Unknown, duplicate, or incomplete option: \(key)")
        }
        options[key] = arguments[index + 1]
        index += 2
    }
    guard let directory = options["--directory"], !directory.isEmpty else {
        throw ExportCommandError.usage("--directory is required")
    }
    let seed = options["--seed"] ?? "15321439165460004865"
    guard UInt64(seed) != nil else { throw ExportCommandError.usage("--seed must be a UInt64 decimal integer") }
    let destination = options["--destination"] ?? "platform=iOS Simulator,name=iPhone 16e"
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let output = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
    if FileManager.default.fileExists(atPath: output.path),
       !(try FileManager.default.contentsOfDirectory(atPath: output.path)).isEmpty {
        throw ExportCommandError.usage("Output directory must be absent or empty")
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("day-objects-export-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let source: URL
    if let path = options["--xctestrun"] {
        source = URL(fileURLWithPath: path)
    } else {
        let derived = temporary.appendingPathComponent("DerivedData")
        try run(["build-for-testing", "-quiet", "-project", "Steps4.xcodeproj", "-scheme", "Steps4",
                 "-destination", destination, "-derivedDataPath", derived.path], at: root)
        let products = derived.appendingPathComponent("Build/Products")
        guard let found = try FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "xctestrun" }).sorted(by: { $0.path < $1.path }).first else {
            throw ExportCommandError.missingTestRun
        }
        source = found
    }
    var injected = false
    func patch(_ value: Any) -> Any {
        if let array = value as? [Any] { return array.map(patch) }
        guard var dictionary = value as? [String: Any] else {
            // Keep __TESTROOT__ relative references valid after copying metadata.
            if let string = value as? String {
                return string.replacingOccurrences(of: "__TESTROOT__", with: source.deletingLastPathComponent().path)
            }
            return value
        }
        dictionary = dictionary.mapValues(patch)
        if dictionary["BlueprintName"] as? String == "Steps4Tests" {
            var environment = dictionary["EnvironmentVariables"] as? [String: String] ?? [:]
            environment["DAY_OBJECTS_AUDITION_PACK"] = "1"
            environment["DAY_OBJECTS_AUDITION_PACK_DIR"] = output.path
            environment["DAY_OBJECTS_AUDITION_PACK_SEED"] = seed
            dictionary["EnvironmentVariables"] = environment
            injected = true
        }
        return dictionary
    }
    let original = try PropertyListSerialization.propertyList(from: Data(contentsOf: source), format: nil)
    let modified = patch(original)
    guard injected else { throw ExportCommandError.missingTestTarget }
    let testRun = temporary.appendingPathComponent("Auditions.xctestrun")
    try PropertyListSerialization.data(fromPropertyList: modified, format: .xml, options: 0).write(to: testRun)
    try run(["test-without-building", "-quiet", "-xctestrun", testRun.path,
             "-destination", destination, "-parallel-testing-enabled", "NO",
             "-only-testing:Steps4Tests/DayObjectsMixScenarioTests/testExportsTwelveAuditionsWhenExplicitlyRequested",
             "-resultBundlePath", temporary.appendingPathComponent("Export.xcresult").path], at: root)
    print("Audition pack: \(output.path)")
    print("Run evidence: \(temporary.path)")
}

do { try main() } catch {
    FileHandle.standardError.write(Data("Export stopped: \(error)\n\(usage)\n".utf8))
    exit(1)
}
