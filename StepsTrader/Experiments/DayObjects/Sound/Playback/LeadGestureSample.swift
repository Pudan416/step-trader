#if DEBUG || INTERNAL_BUILD
struct LeadGestureSample: Equatable, Sendable {
    let normalizedX: Double
    let normalizedY: Double
    let speed: Double
}
#endif
