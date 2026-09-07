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
        coordinator.cancelPreparation()
        coordinator.renderer?.setAnimating(false)
        uiView.isPaused = true
        uiView.delegate = nil
        coordinator.mtkView = nil
    }

    @MainActor final class Coordinator {
        private(set) var renderer: DayObjectsRenderer?
        weak var mtkView: MTKView?
        private var preparation: Task<Void, Never>?
        private var scene: DayObjectScene
        private var environment: DayObjectEnvironment
        private var digitalImpact: DayObjectDigitalImpact
        private var soundPulseBus: DayObjectsSoundPulseBus?
        private var presentationMode: DayObjectsPresentationMode
        private var isAnimating = false

        init(
            scene: DayObjectScene,
            environment: DayObjectEnvironment,
            digitalImpact: DayObjectDigitalImpact,
            soundPulseBus: DayObjectsSoundPulseBus?,
            presentationMode: DayObjectsPresentationMode = .canvas
        ) {
            self.scene = scene
            self.environment = environment
            self.digitalImpact = digitalImpact
            self.soundPulseBus = soundPulseBus
            self.presentationMode = presentationMode
        }

        func prepareRenderer() async {
            guard renderer == nil else { return }
            await Task.detached(priority: .userInitiated) {
                DayObjectsRenderer.prepareResources()
            }.value
            guard !Task.isCancelled, renderer == nil else { return }
            renderer = DayObjectsRenderer.create(
                scene: scene, environment: environment, digitalImpact: digitalImpact,
                soundPulseBus: soundPulseBus, presentationMode: presentationMode
            )
        }

        func cancelPreparation() {
            preparation?.cancel()
            preparation = nil
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
            self.scene = scene
            self.environment = environment
            self.digitalImpact = digitalImpact
            self.soundPulseBus = soundPulseBus
            self.presentationMode = presentationMode
            self.isAnimating = isAnimating
            mtkView = view
            guard renderer != nil else {
                view.isPaused = true
                if preparation == nil {
                    preparation = Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.prepareRenderer()
                        guard !Task.isCancelled else { return }
                        self.preparation = nil
                        self.applyCurrentState()
                    }
                }
                return
            }
            applyCurrentState()
        }

        private func applyCurrentState() {
            guard let renderer, let view = mtkView else { return }
            if view.device == nil { view.device = renderer.device }
            view.delegate = renderer
            renderer.update(scene: scene, environment: environment, digitalImpact: digitalImpact,
                            soundPulseBus: soundPulseBus, presentationMode: presentationMode)
            renderer.setAnimating(isAnimating)
            renderer.configureAnimation(view)
        }
    }
}
