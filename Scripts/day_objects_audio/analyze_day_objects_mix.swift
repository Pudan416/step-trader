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
        let diagnostics = candidate.appendingPathComponent(
            "StepsTrader/Experiments/DayObjects/Sound/Diagnostics",
            isDirectory: true
        )
        let requiredSources = [
            "DayObjectsLoudnessAnalyzer.swift",
            "DayObjectsMixQualityReport.swift",
            "DayObjectsMixQualityAnalyzer.swift",
        ]
        if requiredSources.allSatisfy({
            fileManager.fileExists(atPath: diagnostics.appendingPathComponent($0).path)
        }) { return candidate }
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
    let diagnostics = root.appendingPathComponent(
        "StepsTrader/Experiments/DayObjects/Sound/Diagnostics",
        isDirectory: true
    )
    compiler.arguments = [
        "swiftc", "-D", "DEBUG", "-D", "DAY_OBJECTS_ANALYZER_COMPILED",
        diagnostics.appendingPathComponent("DayObjectsLoudnessAnalyzer.swift").path,
        diagnostics.appendingPathComponent("DayObjectsMixQualityReport.swift").path,
        diagnostics.appendingPathComponent("DayObjectsMixQualityAnalyzer.swift").path,
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
    let quality: DayObjectsMixQualityReport

    var passes: Bool {
        containsOnlyFiniteSamples
            && passesIntegratedLoudness
            && passesTruePeak
            // These two measurements use the command's explicit limits above;
            // the embedded quality report retains the default diagnostic gates.
            && quality.issues.allSatisfy { $0 == .integratedLoudness || $0 == .truePeak }
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
    case missingStem(String)
    case stemsRequireSingleMix(String)
    case inputIsStem(String)

    var description: String {
        switch self {
        case let .usage(message),
             let .noPCMFiles(message),
             let .fileTooLarge(message),
             let .missingStem(message),
             let .stemsRequireSingleMix(message),
             let .inputIsStem(message): message
        }
    }
}

private func parseActiveStemRoles(_ value: String) throws -> Set<DayObjectsMixRole> {
    let names = value.split(separator: ",", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty }) else {
        throw CommandError.usage("--active-stems requires at least one role")
    }
    var roles = Set<DayObjectsMixRole>()
    for name in names {
        guard let role = DayObjectsMixRole(rawValue: name) else {
            throw CommandError.usage(
                "Unknown active stem role: \(name); expected rhythm,bass,harmony,happenings,lead"
            )
        }
        guard roles.insert(role).inserted else {
            throw CommandError.usage("--active-stems roles must be unique")
        }
    }
    return roles
}

private func parseArguments(_ arguments: [String] = CommandLine.arguments) throws -> (
    URL,
    URL?,
    URL?,
    Set<DayObjectsMixRole>?,
    Limits
) {
    var limits = Limits()
    var outputURL: URL?
    var stemsDirectoryURL: URL?
    var activeStemRoles: Set<DayObjectsMixRole>?
    var inputURLs: [URL] = []
    var index = 1
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
        case "--stems-directory":
            stemsDirectoryURL = URL(fileURLWithPath: try value(after: arguments[index]))
        case "--active-stems":
            guard activeStemRoles == nil else {
                throw CommandError.usage("--active-stems may be specified only once")
            }
            activeStemRoles = try parseActiveStemRoles(try value(after: arguments[index]))
        case "--help", "-h":
            throw CommandError.usage(
                "Usage: analyze_day_objects_mix.swift [--min-lufs -18] [--max-lufs -16] "
                    + "[--max-dbtp -1] [--stems-directory directory "
                    + "--active-stems role,...] "
                    + "[--output report.json] <PCM file (or directory without stems)>"
                    + "\nLUFS/peak options replace the default acceptance limits; all other quality gates still apply."
            )
        default:
            guard !arguments[index].hasPrefix("-") else {
                throw CommandError.usage("Unexpected argument: \(arguments[index])")
            }
            inputURLs.append(URL(fileURLWithPath: arguments[index]))
        }
        index += 1
    }
    guard limits.minimumIntegratedLUFS <= limits.maximumIntegratedLUFS else {
        throw CommandError.usage("Minimum LUFS must not exceed maximum LUFS")
    }
    if stemsDirectoryURL != nil, activeStemRoles == nil {
        throw CommandError.usage(
            "--active-stems is required whenever --stems-directory is used"
        )
    }
    if stemsDirectoryURL == nil, activeStemRoles != nil {
        throw CommandError.usage("--active-stems requires --stems-directory")
    }
    if stemsDirectoryURL != nil, inputURLs.count != 1 {
        throw CommandError.stemsRequireSingleMix(
            "--stems-directory requires exactly one full-mix file"
        )
    }
    guard let inputURL = inputURLs.first else {
        throw CommandError.usage("A PCM file or directory is required; use --help for usage")
    }
    guard inputURLs.count == 1 else {
        throw CommandError.usage("Unexpected argument: \(inputURLs[1].path)")
    }
    return (inputURL, outputURL, stemsDirectoryURL, activeStemRoles, limits)
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

private func validateStemAnalysisInput(
    _ inputURL: URL,
    stemsDirectory: URL?
) throws {
    guard let stemsDirectory else { return }
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
       isDirectory.boolValue {
        throw CommandError.stemsRequireSingleMix(
            "--stems-directory requires exactly one full-mix file; directories are not supported"
        )
    }
    let resolvedInput = inputURL.standardizedFileURL.resolvingSymlinksInPath()
    for role in DayObjectsMixRole.allCases {
        let stem = stemsDirectory
            .appendingPathComponent("\(role.rawValue).wav")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        if resolvedInput == stem {
            throw CommandError.inputIsStem(
                "Full-mix input must not be a stem path: \(inputURL.path)"
            )
        }
    }
}

private func readPCMBuffer(_ url: URL) throws -> AVAudioPCMBuffer {
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
    return buffer
}

private func readStems(at directory: URL?) throws -> [DayObjectsMixRole: AVAudioPCMBuffer] {
    guard let directory else { return [:] }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw CommandError.missingStem("Stems directory does not exist: \(directory.path)")
    }
    var stems: [DayObjectsMixRole: AVAudioPCMBuffer] = [:]
    for role in DayObjectsMixRole.allCases {
        let url = directory.appendingPathComponent("\(role.rawValue).wav")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CommandError.missingStem("Missing required stem: \(url.path)")
        }
        stems[role] = try readPCMBuffer(url)
    }
    return stems
}

private func analyze(
    _ url: URL,
    stems: [DayObjectsMixRole: AVAudioPCMBuffer],
    activeRoles: Set<DayObjectsMixRole>?,
    limits: Limits
) throws -> FileReport {
    let buffer = try readPCMBuffer(url)
    let quality = try DayObjectsMixQualityAnalyzer.analyze(
        fullMix: buffer,
        stems: stems,
        activeRoles: activeRoles
    )
    return FileReport(
        path: url.path,
        integratedLUFS: quality.integratedLUFS,
        truePeakDBTP: quality.truePeakDBTP,
        durationSeconds: Double(buffer.frameLength) / buffer.format.sampleRate,
        containsOnlyFiniteSamples: true,
        passesIntegratedLoudness: (limits.minimumIntegratedLUFS ... limits.maximumIntegratedLUFS)
            .contains(quality.integratedLUFS),
        passesTruePeak: quality.truePeakDBTP <= limits.maximumTruePeakDBTP,
        quality: quality
    )
}

#if !DAY_OBJECTS_ANALYZER_TESTING
do {
    let (inputURL, outputURL, stemsDirectoryURL, activeStemRoles, limits) = try parseArguments()
    try validateStemAnalysisInput(inputURL, stemsDirectory: stemsDirectoryURL)
    let stems = try readStems(at: stemsDirectoryURL)
    let reports = try pcmFiles(at: inputURL).map {
        try analyze($0, stems: stems, activeRoles: activeStemRoles, limits: limits)
    }
    let report = CommandReport(
        schemaVersion: 4,
        analyzer: "ITU-R BS.1770 loudness/4x true peak; deterministic 4096-point FFT mix quality",
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
#endif
