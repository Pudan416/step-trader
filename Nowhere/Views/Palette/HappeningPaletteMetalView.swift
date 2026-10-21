import MetalKit
import QuartzCore
import SwiftUI

/// One serial GPU worker shares a queue and Native Atlas scratch targets.
/// All dirty tiles in a batch use the same immutable world sample.
final class HappeningPaletteTileRenderer {
    struct Output {
        let tile: HappeningPaletteTilePlan.Tile
        let texture: MTLTexture
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let native: NativeAtlasMetalRenderer
    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let native = NativeAtlasMetalRenderer(device: device) else { return nil }
        self.device = device; self.queue = queue; self.native = native
    }

    func encode(outputs: [Output], scene: DayObjectScene,
                presentation: HappeningPaletteRenderPresentation, sample worldSample: HappeningPaletteRenderSample,
                at elapsed: TimeInterval, pointScale: Float) -> MTLCommandBuffer? {
        guard !outputs.isEmpty, let original = scene.input.nativeAtlasRecipe, original.isSupported,
              let buffer = queue.makeCommandBuffer() else { return nil }
        let states = Dictionary(uniqueKeysWithValues: presentation.slots.map { ($0.happeningID, $0.visualState) })
        for output in outputs {
            let sample = HappeningPaletteTilePlan.projectedSample(worldSample, to: output.tile)
            let slots = sample.slots.map {
                HappeningPaletteRenderSlot(happeningID: $0.happeningID, assignment: $0.assignment,
                    visualState: states[$0.happeningID] ?? .available, source: $0.source)
            }
            let local = HappeningPaletteRenderPresentation(slots: slots, viewportSize: output.tile.frame.size,
                reduceMotion: presentation.reduceMotion, isTransitionActive: presentation.isTransitionActive,
                backgroundRevision: presentation.backgroundRevision, usesSharedGeometry: true)
            let frame = HappeningPaletteRenderFrame.make(presentation: local, scene: scene,
                elapsed: elapsed, sampledSlots: sample)
            var recipe = original
            recipe.intersectionStrength = 0
            var variants = scene.input.actorColorVariants
            recipe.actors = slots.compactMap { slot in
                let id = slot.assignment.elementID.uuidString.lowercased()
                guard let spec = slot.assignment.nativeActor ?? original.prospectiveActor(eventID: id) else { return nil }
                variants[slot.happeningID] = slot.assignment.colorVariant
                return NativeAtlasRecipe.Actor(eventID: slot.happeningID, presetID: spec.presetID,
                    materialID: spec.materialID, seedHex: spec.seedHex, geometry: spec.geometry,
                    material: spec.material, position: spec.position, size: spec.size,
                    rotation: spec.rotation, slot: spec.slot)
            }
            let adapted = native.adapt(frame, recipe: recipe, aspect: 1, elapsed: elapsed, isPalette: true)
            guard native.encode(commandBuffer: buffer, output: output.texture, recipe: recipe,
                frame: adapted, damage: 0, scene: scene, elapsed: elapsed, pointToPixelScale: pointScale,
                isPalette: true, colorVariants: variants,
                paletteWorldOrigin: output.tile.frame.origin) else { return nil }
        }
        return buffer
    }
}

struct HappeningPaletteMetalView: UIViewRepresentable {
    let scene: DayObjectScene
    let presentation: HappeningPaletteRenderPresentation
    let isActive: Bool

    func makeUIView(context: Context) -> HappeningPaletteTileSurfaceView {
        HappeningPaletteTileSurfaceView(frame: .zero)
    }

    func updateUIView(_ view: HappeningPaletteTileSurfaceView, context: Context) {
        view.update(scene: scene, presentation: presentation, isActive: isActive)
    }

    static func dismantleUIView(_ view: HappeningPaletteTileSurfaceView, coordinator: ()) {
        view.dismantle()
    }
}

/// The host and each tile retain fixed world frames. Native scrolling can move
/// their already-rendered pixels without requesting a new camera or GPU frame.
final class HappeningPaletteTileSurfaceView: UIView {
    private(set) var residentTiles: [HappeningPaletteTilePlan.Tile: MTKView] = [:]
    private(set) var submittedFrameCount = 0
    var isAnimatingFrames: Bool { displayLink != nil || batchIsInFlight }
    private var dirtyTiles = Set<HappeningPaletteTilePlan.Tile>()
    private var renderer: HappeningPaletteTileRenderer?
    private var preparation: Task<Void, Never>?
    private var scene: DayObjectScene?
    private var presentation: HappeningPaletteRenderPresentation?
    private var isActive = false
    private let clock = DayObjectsClock()
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: PaletteDisplayLinkTarget?
    private var isScheduled = false
    private weak var observedScroll: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var boundsObservation: NSKeyValueObservation?
    private var pixelSide = 0
    private var wasAnimating = false
    private var worldPresentation: HappeningPaletteRenderPresentation?
    private var timeline = HappeningPaletteTransitionTimeline()
    private let worker = DispatchQueue(label: "nowhere.happenings.tiles", qos: .userInteractive)
    private var batchIsInFlight = false
    private var currentBatch: PaletteTileBatch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false; backgroundColor = .clear; isUserInteractionEnabled = false
        clipsToBounds = true
        clock.setPaused(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(scene: DayObjectScene, presentation: HappeningPaletteRenderPresentation, isActive: Bool) {
        clock.setPaused(!isActive || window == nil)
        var world = presentation; world.visibleRect = nil
        if self.scene != scene || worldPresentation != world {
            currentBatch?.cancel()
            timeline.update(to: world, elapsed: clock.elapsedTime)
            worldPresentation = world
            dirtyTiles.formUnion(residentTiles.keys)
        }
        self.scene = scene; self.presentation = presentation; self.isActive = isActive
        if renderer == nil, preparation == nil {
            preparation = Task { @MainActor [weak self] in
                await Task.detached(priority: .userInitiated) { DayObjectsRenderer.prepareResources() }.value
                guard let self, !Task.isCancelled, self.scene != nil,
                      self.presentation != nil, let device = MTLCreateSystemDefaultDevice() else { return }
                self.renderer = HappeningPaletteTileRenderer(device: device)
                self.preparation = nil
                self.scheduleFrame()
            }
        }
        if !isActive { currentBatch?.cancel(); stopDisplayLink() }
        scheduleFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clock.setPaused(!isActive || window == nil)
        if window == nil {
            currentBatch?.cancel()
            stopDisplayLink()
            offsetObservation = nil; boundsObservation = nil; observedScroll = nil
            releaseTiles()
        } else {
            observeScroll()
            scheduleFrame()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        observeScroll()
        scheduleFrame()
    }

    func dismantle() {
        isActive = false; clock.setPaused(true)
        preparation?.cancel(); preparation = nil
        currentBatch?.cancel()
        stopDisplayLink()
        offsetObservation = nil; boundsObservation = nil; observedScroll = nil
        releaseTiles(); renderer = nil; scene = nil; presentation = nil
    }

    private func observeScroll() {
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
        guard let scroll = ancestor as? UIScrollView, scroll !== observedScroll else { return }
        observedScroll = scroll
        offsetObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.scheduleFrame() }
        boundsObservation = scroll.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.scheduleFrame() }
    }

    private func scheduleFrame() {
        guard isActive, window != nil, renderer != nil, !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScheduled = false
            self.drawFrame()
        }
    }

    fileprivate func drawFrame() {
        guard isActive, window != nil, let renderer, let presentation, let scene,
              let worldPresentation else { stopDisplayLink(); return }
        let visible = observedScroll.map { convert($0.bounds, from: $0) }
            ?? presentation.visibleRect ?? CGRect(origin: .zero, size: bounds.size)
        let scale = HappeningPaletteTilePlan.displayScale(viewportSize: visible.size, nativeScale: traitCollection.displayScale)
        let side = max(1, Int(floor(HappeningPaletteTilePlan.tileSide * scale)))
        if side != pixelSide { releaseTiles(); pixelSide = side }
        let plan = HappeningPaletteTilePlan.tiles(worldSize: presentation.viewportSize, visibleRect: visible)
        let required = Set(plan)
        for tile in Array(residentTiles.keys) where !required.contains(tile) {
            if let view = residentTiles.removeValue(forKey: tile) { view.releaseDrawables(); view.removeFromSuperview() }
            dirtyTiles.remove(tile)
        }
        for tile in plan where residentTiles[tile] == nil {
            let view = MTKView(frame: tile.frame, device: renderer.device)
            view.autoResizeDrawable = false; view.isPaused = true; view.enableSetNeedsDisplay = false
            view.isOpaque = false; view.layer.isOpaque = false; view.backgroundColor = .clear
            view.isUserInteractionEnabled = false; view.framebufferOnly = true
            view.contentScaleFactor = CGFloat(side) / HappeningPaletteTilePlan.tileSide
            view.drawableSize = CGSize(width: side, height: side)
            (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
            DayObjectsRenderer.configureDisplay(view)
            addSubview(view); residentTiles[tile] = view; dirtyTiles.insert(tile)
        }
        let elapsed = clock.elapsedTime
        let animates = needsAnimation(at: elapsed)
        // Include the first settled tick so a fade/morph reaches its endpoint.
        if animates || wasAnimating { dirtyTiles.formUnion(required) }
        wasAnimating = animates
        if !batchIsInFlight {
            let requests = plan.compactMap { tile -> (HappeningPaletteTilePlan.Tile, CAMetalLayer)? in
                guard dirtyTiles.contains(tile), let layer = residentTiles[tile]?.layer as? CAMetalLayer else { return nil }
                return (tile, layer)
            }
            if !requests.isEmpty {
                let sample = timeline.sample(at: elapsed)
                let batch = PaletteTileBatch()
                currentBatch = batch; batchIsInFlight = true
                // New updates/ticks can dirty these IDs again while the batch
                // runs; completion must not erase that newer work.
                dirtyTiles.subtract(requests.map { $0.0 })
                let pointScale = Float(CGFloat(side) / HappeningPaletteTilePlan.tileSide)
                worker.async { [weak self] in
                    autoreleasepool {
                        var drawables: [CAMetalDrawable] = []
                        for (_, layer) in requests {
                            guard !batch.isCancelled, let drawable = layer.nextDrawable() else {
                                DispatchQueue.main.async { self?.finishBatch(requests: requests, succeeded: false) }
                                return
                            }
                            drawables.append(drawable)
                        }
                        // Acquire the complete batch before encoding/presenting:
                        // a missing tile must not split one animated figure.
                        guard !batch.isCancelled,
                              let buffer = renderer.encode(outputs: zip(requests, drawables).map {
                                  .init(tile: $0.0.0, texture: $0.1.texture)
                              }, scene: scene, presentation: worldPresentation, sample: sample,
                                 at: elapsed, pointScale: pointScale) else {
                            DispatchQueue.main.async { self?.finishBatch(requests: requests, succeeded: false) }
                            return
                        }
                        let submitted = batch.commitIfActive {
                            for drawable in drawables { buffer.present(drawable) }
                            buffer.addCompletedHandler { completed in
                                let succeeded = completed.status == .completed
                                DispatchQueue.main.async { self?.finishBatch(requests: requests, succeeded: succeeded) }
                            }
                            buffer.commit()
                        }
                        if !submitted {
                            DispatchQueue.main.async { self?.finishBatch(requests: requests, succeeded: false) }
                        }
                    }
                }
            }
        }
        if animates || !dirtyTiles.isEmpty || batchIsInFlight { startDisplayLink() } else { stopDisplayLink() }
    }

    private func needsAnimation(at elapsed: TimeInterval) -> Bool {
        timeline.hasActiveTransitions(at: elapsed)
            || worldPresentation.map { DayObjectsPresentationMode.happeningPalette($0).prefersSixtyFPS } == true
    }

    private func finishBatch(requests: [(HappeningPaletteTilePlan.Tile, CAMetalLayer)], succeeded: Bool) {
        batchIsInFlight = false; currentBatch = nil
        if succeeded { submittedFrameCount += 1 }
        else {
            for (tile, layer) in requests where residentTiles[tile]?.layer === layer { dirtyTiles.insert(tile) }
        }
        guard isActive, window != nil else { stopDisplayLink(); return }
        if needsAnimation(at: clock.elapsedTime) || wasAnimating || !dirtyTiles.isEmpty {
            startDisplayLink()
        } else { stopDisplayLink() }
    }

    private func releaseTiles() {
        currentBatch?.cancel()
        for view in residentTiles.values { view.releaseDrawables(); view.removeFromSuperview() }
        residentTiles.removeAll(); dirtyTiles.removeAll()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let target = PaletteDisplayLinkTarget(); target.view = self
        let link = CADisplayLink(target: target, selector: #selector(PaletteDisplayLinkTarget.tick))
        link.preferredFramesPerSecond = 60
        displayLinkTarget = target; displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil; displayLinkTarget = nil
    }
}

private final class PaletteDisplayLinkTarget: NSObject {
    weak var view: HappeningPaletteTileSurfaceView?
    @objc func tick() { view?.drawFrame() }
}

/// Cancellation is the only state shared with the serial GPU worker. A scene
/// change/detach must not enqueue an obsolete snapshot after drawable waiting.
private final class PaletteTileBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    /// Linearize cancellation against submission. Drawable acquisition and
    /// encoding never hold this lock; only the short, non-waiting commit does.
    func commitIfActive(_ submit: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        submit()
        return true
    }
}
