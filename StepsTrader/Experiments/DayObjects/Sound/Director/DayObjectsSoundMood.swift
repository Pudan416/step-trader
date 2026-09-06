#if DEBUG || INTERNAL_BUILD
enum DayObjectsSoundMood: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case sparse
    case moving
    case strange
}
#endif
