#!/usr/bin/env swift

#if !DAY_OBJECTS_ANALYZER_COMPILED
import Darwin
import Foundation

private func repositoryRoot() -> URL? {
    let fileManager = FileManager.default
    var candidates = [
        URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
        URL(fileURLWithPath: #filePath).deletingLastPathComponent(),
    ]
    while let candidate = candidates.first {
        candidates.removeFirst()
        let analyzer = candidate.appendingPathComponent(
            "StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift"
        )
        if fileManager.fileExists(atPath: analyzer.path) { return candidate }
        let parent = candidate.deletingLastPathComponent()
        if parent.path != candidate.path, !candidates.contains(parent) {
            candidates.append(parent)
        }
    }
    return nil
}

guard let root = repositoryRoot() else {
    FileHandle.standardError.write(Data("Could not locate the Day Objects analyzer source.\n".utf8))
    exit(64)
}

let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("day-objects-analyzer-\(UUID().uuidString)", isDirectory: true)
do {
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporaryDirectory) }
    let mainSource = temporaryDirectory.appendingPathComponent("main.swift")
    try fileManager.copyItem(at: URL(fileURLWithPath: #filePath), to: mainSource)
    let executable = temporaryDirectory.appendingPathComponent("analyze-day-objects-mix")
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = [
        "swiftc", "-D", "DEBUG", "-D", "DAY_OBJECTS_ANALYZER_COMPILED",
        root.appendingPathComponent(
            "StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift"
        ).path,
        mainSource.path,
        "-o", executable.path,
    ]
    compiler.standardOutput = FileHandle.standardError
    compiler.standardError = FileHandle.standardError
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else { exit(compiler.terminationStatus) }

    let analyzer = Process()
    analyzer.executableURL = executable
    analyzer.arguments = Array(CommandLine.arguments.dropFirst())
    analyzer.standardOutput = FileHandle.standardOutput
    analyzer.standardError = FileHandle.standardError
    try analyzer.run()
    analyzer.waitUntilExit()
    exit(analyzer.terminationStatus)
} catch {
    FileHandle.standardError.write(Data("Analyzer bootstrap failed: \(error)\n".utf8))
    exit(70)
}

#else
import AVFAudio
import Darwin
import Foundation

private struct Limits: Codable {
    var minimumIntegratedLUFS = -18.0
    var maximumIntegratedLUFS = -16.0
    var maximumTruePeakDBTP = -1.0
}

private struct FileReport: Codable {
    let path: String
    let integratedLUFS: Double
    let truePeakDBTP: Double
    let durationSeconds: Double
    let containsOnlyFiniteSamples: Bool
    let passesIntegratedLoudness: Bool
    let passesTruePeak: Bool

    var passes: Bool {
        containsOnlyFiniteSamples && passesIntegratedLoudness && passesTruePeak
    }
}

private struct CommandReport: Codable {
    let schemaVersion: Int
    let analyzer: String
    let limits: Limits
    let files: [FileReport]
    let passes: Bool
}

private enum CommandError: Error, CustomStringConvertible {
    case usage(String)
    case noPCMFiles(String)
    case fileTooLarge(String)

    var description: String {
        switch self {
        case let .usage(message), let .noPCMFiles(message), let .fileTooLarge(message): message
        }
    }
}

private func parseArguments() throws -> (URL, URL?, Limits) {
    var limits = Limits()
    var outputURL: URL?
    var inputURL: URL?
    var index = 1
    let arguments = CommandLine.arguments
    func value(after option: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw CommandError.usage("Missing value after \(option)")
        }
        index += 1
        return arguments[index]
    }
    while index < arguments.count {
        switch arguments[index] {
        case "--min-lufs":
            guard let value = Double(try value(after: arguments[index])), value.isFinite else {
                throw CommandError.usage("--min-lufs requires a finite number")
            }
            limits.minimumIntegratedLUFS = value
        case "--max-lufs":
            guard let value = Double(try value(after: arguments[index])), value.isFinite else {
                throw CommandError.usage("--max-lufs requires a finite number")
            }
            limits.maximumIntegratedLUFS = value
        case "--max-dbtp":
            guard let value = Double(try value(after: arguments[index])), value.isFinite else {
                throw CommandError.usage("--max-dbtp requires a finite number")
            }
            limits.maximumTruePeakDBTP = value
        case "--output":
            outputURL = URL(fileURLWithPath: try value(after: arguments[index]))
        case "--help", "-h":
            throw CommandError.usage(
                "Usage: analyze_day_objects_mix.swift [--min-lufs -18] [--max-lufs -16] "
                    + "[--max-dbtp -1] [--output report.json] <PCM file or directory>"
            )
        default:
            guard !arguments[index].hasPrefix("-"), inputURL == nil else {
                throw CommandError.usage("Unexpected argument: \(arguments[index])")
            }
            inputURL = URL(fileURLWithPath: arguments[index])
        }
        index += 1
    }
    guard limits.minimumIntegratedLUFS <= limits.maximumIntegratedLUFS else {
        throw CommandError.usage("Minimum LUFS must not exceed maximum LUFS")
    }
    guard let inputURL else {
        throw CommandError.usage("A PCM file or directory is required; use --help for usage")
    }
    return (inputURL, outputURL, limits)
}

private func pcmFiles(at inputURL: URL) throws -> [URL] {
    let supportedExtensions: Set<String> = ["wav", "wave", "caf", "aif", "aiff"]
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
        throw CommandError.noPCMFiles("Input does not exist: \(inputURL.path)")
    }
    if !isDirectory.boolValue {
        guard supportedExtensions.contains(inputURL.pathExtension.lowercased()) else {
            throw CommandError.noPCMFiles("Unsupported PCM extension: \(inputURL.pathExtension)")
        }
        return [inputURL]
    }
    guard let enumerator = FileManager.default.enumerator(
        at: inputURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw CommandError.noPCMFiles("Could not enumerate: \(inputURL.path)")
    }
    let files = enumerator.compactMap { $0 as? URL }.filter {
        supportedExtensions.contains($0.pathExtension.lowercased())
    }.sorted { $0.path < $1.path }
    guard !files.isEmpty else {
        throw CommandError.noPCMFiles("No PCM files found under: \(inputURL.path)")
    }
    return files
}

private func analyze(_ url: URL, limits: Limits) throws -> FileReport {
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.length <= Int64(AVAudioFrameCount.max) else {
        throw CommandError.fileTooLarge("Unsupported frame count in: \(url.path)")
    }
    let format = file.processingFormat
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(file.length)
    ) else {
        throw CommandError.fileTooLarge("Could not allocate PCM buffer for: \(url.path)")
    }
    try file.read(into: buffer)
    let loudness = try DayObjectsStereoCaptureAdapter.analyze(buffer)
    return FileReport(
        path: url.path,
        integratedLUFS: loudness.integratedLUFS,
        truePeakDBTP: loudness.truePeakDBTP,
        durationSeconds: loudness.durationSeconds,
        containsOnlyFiniteSamples: loudness.containsOnlyFiniteSamples,
        passesIntegratedLoudness: (limits.minimumIntegratedLUFS ... limits.maximumIntegratedLUFS)
            .contains(loudness.integratedLUFS),
        passesTruePeak: loudness.truePeakDBTP <= limits.maximumTruePeakDBTP
    )
}

do {
    let (inputURL, outputURL, limits) = try parseArguments()
    let reports = try pcmFiles(at: inputURL).map { try analyze($0, limits: limits) }
    let report = CommandReport(
        schemaVersion: 1,
        analyzer: "ITU-R BS.1770 K-weighting; 400 ms blocks; 75% overlap; -70 LUFS absolute / -10 LU relative gates; 4x true peak",
        limits: limits,
        files: reports,
        passes: reports.allSatisfy(\.passes)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    if let outputURL {
        try data.write(to: outputURL, options: .atomic)
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(report.passes ? 0 : 2)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(64)
}
#endif
