import MetalKit
import SwiftUI

struct DayObjectsMetalView: UIViewRepresentable {
    let scene: DayObjectScene
    let environment: DayObjectEnvironment
    let digitalImpact: DayObjectDigitalImpact
    let isAnimating: Bool
    let soundPulseBus: DayObjectsSoundPulseBus?
    var presentationMode: DayObjectsPresentationMode = .canvas

    func makeCoordinator() -> Coordinator {
        Coordinator(
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact,
            soundPulseBus: soundPulseBus,
            presentationMode: presentationMode
        )
    }

    func makeUIView(context: Context) -> MTKView {
        let renderer = context.coordinator.renderer
        let view = MTKView(frame: .zero, device: renderer?.device)
        view.delegate = renderer
        DayObjectsRenderer.configureDisplay(view)
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isOpaque = false
        view.layer.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        context.coordinator.mtkView = view
        updateUIView(view, context: context)
        return view
    }

    static func configureAnimationFrameRate(_ view: MTKView, prefersSixtyFPS: Bool = false) {
        // MTKView owns the display link and exposes its rate through this API.
        let preferred = prefersSixtyFPS ? 60 : 30
        if view.preferredFramesPerSecond != preferred {
            view.preferredFramesPerSecond = preferred
        }
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.update(
            uiView,
            scene: scene,
            environment: environment,
            digitalImpact: digitalImpact,
            soundPulseBus: soundPulseBus,
            presentationMode: presentationMode,
            isAnimating: isAnimating
        )
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
            digitalImpact: DayObjectDigitalImpact,
            soundPulseBus: DayObjectsSoundPulseBus?,
            presentationMode: DayObjectsPresentationMode = .canvas
        ) {
            renderer = DayObjectsRenderer.create(
                scene: scene,
                environment: environment,
                digitalImpact: digitalImpact,
                soundPulseBus: soundPulseBus,
                presentationMode: presentationMode
            )
        }

        func update(
            _ view: MTKView,
            scene: DayObjectScene,
            environment: DayObjectEnvironment,
            digitalImpact: DayObjectDigitalImpact,
            soundPulseBus: DayObjectsSoundPulseBus?,
            presentationMode: DayObjectsPresentationMode,
            isAnimating: Bool
        ) {
            guard let renderer else {
                view.isPaused = true
                return
            }
            renderer.update(scene: scene, environment: environment, digitalImpact: digitalImpact,
                            soundPulseBus: soundPulseBus, presentationMode: presentationMode)
            renderer.setAnimating(isAnimating)
            renderer.configureAnimation(view)
        }
    }
}
