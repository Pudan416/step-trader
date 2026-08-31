#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsTransportEventKind: Equatable, Sendable {
    case subdivision
    case beat
    case barBoundary
    case harmonicCycleBoundary
}

struct DayObjectsTransportEvent: Equatable, Sendable {
    let kind: DayObjectsTransportEventKind
    let position: MusicalPosition
    let hostTimeSeconds: TimeInterval
    let tempoBPM: Double
}
#endif
