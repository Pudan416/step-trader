public enum EditorialGrammar: String, CaseIterable, Codable, Sendable {
    case layeredOverlap
    case openField
    case croppedForeground
    case depthScatter
    case transparentPrint
    case equalScaleStudy

    public static func select(daySeed: UInt64) -> EditorialGrammar {
        switch daySeed % 100 {
        case 0..<24: .layeredOverlap
        case 24..<44: .openField
        case 44..<59: .croppedForeground
        case 59..<81: .depthScatter
        case 81..<93: .transparentPrint
        default: .equalScaleStudy
        }
    }

    var overlapTarget: Double {
        switch self {
        case .layeredOverlap: 0.42
        case .openField: 0.04
        case .croppedForeground: 0.16
        case .depthScatter: 0.20
        case .transparentPrint: 0.36
        case .equalScaleStudy: 0.08
        }
    }

    var isDistributed: Bool {
        self == .openField || self == .depthScatter
    }
}
