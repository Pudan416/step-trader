import MetalKit
import SwiftUI

struct DayObjectsMetalView: UIViewRepresentable {
    let scene: DayObjectScene
    let environment: DayObjectEnvironment
    let digitalImpact: DayObjectDigitalImpact
    let isAnimating: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let renderer = context.coordinator.renderer
        let view = MTKView(frame: .zero, device: renderer?.device)
        view.delegate = renderer
        view.preferredFramesPerSecond = 30
        DayObjectsRenderer.configureDisplay(view)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = !isAnimating
        view.isPaused = !isAnimating || renderer == nil
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        renderer?.setAnimating(isAnimating)
        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else {
            uiView.isPaused = true
            return
        }

        renderer.update(
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact
        )
        renderer.setAnimating(isAnimating)
        uiView.enableSetNeedsDisplay = !isAnimating
        uiView.isPaused = !isAnimating
        if !isAnimating {
            uiView.setNeedsDisplay()
        }
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.renderer?.setAnimating(false)
        uiView.isPaused = true
        uiView.delegate = nil
        coordinator.mtkView = nil
    }

    @MainActor final class Coordinator {
        let renderer: DayObjectsRenderer?
        weak var mtkView: MTKView?

        init(
            scene: DayObjectScene,
            environment: DayObjectEnvironment,
            digitalImpact: DayObjectDigitalImpact
        ) {
            renderer = DayObjectsRenderer.create(
                scene: scene,
                environment: environment,
                digitalImpact: digitalImpact
            )
        }
    }
}
