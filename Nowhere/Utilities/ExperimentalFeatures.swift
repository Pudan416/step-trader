enum ExperimentalFeatures {
    // The legacy experiment host is a developer tool, even in internal Release builds.
    #if DEBUG
    static let dayObjectsLab = true
    #else
    static let dayObjectsLab = false
    #endif
}
