#if DEBUG || INTERNAL_BUILD
func smoothActivation(_ value: Double, start: Double, end: Double) -> Double {
    guard value.isFinite, start.isFinite, end.isFinite, end > start else {
        return 0
    }
    guard value > start else { return 0 }
    guard value < end else { return 1 }

    let progress = (value - start) / (end - start)
    return progress * progress * (3 - (2 * progress))
}
#endif
