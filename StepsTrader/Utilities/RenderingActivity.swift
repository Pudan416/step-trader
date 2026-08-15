import SwiftUI

extension EnvironmentValues {
    @Entry var renderingIsActive: Bool = true
}

enum RenderingActivity {
    static func shouldAnimate(
        isViewActive: Bool,
        sceneIsActive: Bool,
        reduceMotion: Bool
    ) -> Bool {
        isViewActive && sceneIsActive && !reduceMotion
    }
}

enum MetalOverlayRenderingPolicy {
    static func shouldRender(
        isRenderingAllowed: Bool,
        hasActiveEffect: Bool
    ) -> Bool {
        isRenderingAllowed && hasActiveEffect
    }
}
