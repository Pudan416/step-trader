enum ExperimentalFeatures {
    #if DEBUG || INTERNAL_BUILD
    static let richCanvasLab = true
    #else
    static let richCanvasLab = false
    #endif
}
