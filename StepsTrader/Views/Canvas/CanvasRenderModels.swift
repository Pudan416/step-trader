import SwiftUI

struct ElementInteraction {
    var noiseBoost: Double = 0
    var attractionOffset: CGVector = .zero
    var stretchFactor: Double = 1.0
}

struct MindFrequencyProfile {
    let fx1, fx2, fx3: Double
    let fy1, fy2, fy3: Double

    init(phase p: Double) {
        let s = p * 1000.0
        fx1 = 1.0  + sin(s * 0.11) * 0.15
        fx2 = 2.2  + sin(s * 0.23) * 0.3
        fx3 = 3.8  + sin(s * 0.37) * 0.5
        fy1 = 0.85 + cos(s * 0.17) * 0.15
        fy2 = 2.0  + cos(s * 0.31) * 0.3
        fy3 = 3.5  + cos(s * 0.43) * 0.5
    }
}

struct BodyBlobInfo {
    let element: CanvasElement
    let center: CGPoint
    let radius: CGFloat
    let color: Color
    let color2: Color?
    let seed: UInt64
}
