#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsDrumVoice: String, CaseIterable, Sendable {
    case kickSoft, kickFull, hatClosed, hatOpen, shaker
    case clapSoft, stick, organicHigh, organicLow
}
#endif
