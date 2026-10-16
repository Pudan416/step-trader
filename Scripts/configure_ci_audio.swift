#!/usr/bin/env swift
// Route hosted macOS simulator tests through the installed software audio device.
// This changes only the ephemeral runner; app and test rendering stay live.
import CoreAudio
import Foundation

struct AudioSetupError: Error, CustomStringConvertible {
    let description: String
}

func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    .init(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
          mElement: kAudioObjectPropertyElementMain)
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw AudioSetupError(description: "\(operation): OSStatus \(status)") }
}

func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
    var result = initial
    var property = address(selector)
    var size = UInt32(MemoryLayout<T>.size)
    let status = withUnsafeMutablePointer(to: &result) { pointer in
        AudioObjectGetPropertyData(object, &property, 0, nil, &size, UnsafeMutableRawPointer(pointer))
    }
    try check(status, "Read property \(selector)")
    return result
}

struct Device: Codable {
    let id: AudioDeviceID
    let name: String
    let sampleRate: Double
}

let system = AudioObjectID(kAudioObjectSystemObject)
let selectors: [(String, AudioObjectPropertySelector)] = [
    ("input", kAudioHardwarePropertyDefaultInputDevice),
    ("output", kAudioHardwarePropertyDefaultOutputDevice),
    ("systemOutput", kAudioHardwarePropertyDefaultSystemOutputDevice),
]

func defaults() throws -> [String: AudioDeviceID] {
    try Dictionary(uniqueKeysWithValues: selectors.map {
        ($0.0, try value(system, $0.1, initial: AudioDeviceID(0)))
    })
}

struct Report: Codable {
    let devices: [Device]
    let before: [String: AudioDeviceID]
    let after: [String: AudioDeviceID]
}

do {
    guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" else {
        throw AudioSetupError(description: "Audio routing is restricted to GitHub Actions runners")
    }
    var property = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size), "List device size")
    guard size > 0 else { throw AudioSetupError(description: "No host audio devices") }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    try ids.withUnsafeMutableBytes { bytes in
        try check(AudioObjectGetPropertyData(system, &property, 0, nil, &size, bytes.baseAddress!), "List devices")
    }
    let devices = try ids.map { id -> Device in
        let name: CFString? = try value(id, kAudioObjectPropertyName, initial: Optional<CFString>.none)
        return Device(id: id, name: name.map { $0 as String } ?? "", sampleRate:
            try value(id, kAudioDevicePropertyNominalSampleRate, initial: Float64(0)))
    }
    let candidates = devices.filter { $0.name == "Null Audio Device" }
    guard candidates.count == 1, let target = candidates.first else {
        throw AudioSetupError(description: "Expected one installed Null Audio Device, found \(candidates.count)")
    }
    let before = try defaults()
    for (label, selector) in selectors {
        var property = address(selector)
        var id = target.id
        try check(AudioObjectSetPropertyData(system, &property, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id), "Set default \(label)")
    }
    let after = try defaults()
    guard after.values.allSatisfy({ $0 == target.id }), after.count == selectors.count else {
        throw AudioSetupError(description: "Default audio device readback does not match requested route")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Report(devices: devices, before: before, after: after))
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("CI audio setup failed: \(error)\n".utf8))
    exit(1)
}
