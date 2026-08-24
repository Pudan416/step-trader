enum ExperimentalFeatures {
    #if DEBUG || INTERNAL_BUILD
    static let richCanvasLab = true
    static let generativeSceneLab = true
    static let canvasAtmosphereLab = true
    static let dayRaysLab = true
    static let dayObjectsLab = true
    #else
    static let richCanvasLab = false
    static let generativeSceneLab = false
    static let canvasAtmosphereLab = false
    static let dayRaysLab = false
    static let dayObjectsLab = false
    #endif
}
