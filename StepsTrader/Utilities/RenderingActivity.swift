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

/// Scoped to the visible full-screen music canvas.
struct CanvasIdleTimerModifier: ViewModifier {
    let isFullScreen: Bool
    let isCanvasSelected: Bool
    let isMusicPlaying: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var previousIdleTimerSetting: Bool?

    private var requestsWake: Bool {
        isFullScreen && isCanvasSelected && isMusicPlaying && scenePhase == .active
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                updateIdleTimer(requestsWake)
            }
            .onChange(of: isVisible && requestsWake) { _, enabled in
                updateIdleTimer(enabled)
            }
            .onDisappear {
                isVisible = false
                updateIdleTimer(false)
            }
    }

    private func updateIdleTimer(_ enabled: Bool) {
        if enabled {
            guard previousIdleTimerSetting == nil else { return }
            previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        } else if let previousIdleTimerSetting {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting
            self.previousIdleTimerSetting = nil
        }
    }
}
