#if DEBUG || INTERNAL_BUILD
import Foundation

struct DayObjectsInstrumentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

enum DayObjectsInstrumentCategory: String, Codable, CaseIterable, Sendable {
    case pad
    case pluck
    case bass
    case lead
    case keys
    case drums
    case piano
}

struct DayObjectsInstrumentDescriptor: Equatable, Codable, Sendable {
    let id: DayObjectsInstrumentID
    let category: DayObjectsInstrumentCategory
    let displayName: String
    let bankName: String
    let sourceUID: String?
    let referenceMIDI: UInt8
    let auditionChord: [UInt8]
    let outputTrimDB: Double
}
#endif
