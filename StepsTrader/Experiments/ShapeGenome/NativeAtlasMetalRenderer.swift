import MetalKit

/// Shared live/export path. Geometry is evaluated by Metal, never by PNG assets.
final class NativeAtlasMetalRenderer {
    private let device: MTLDevice
    private let composite: MTLRenderPipelineState
    private let display: MTLRenderPipelineState
    private let gradient: MTLRenderPipelineState
    private let finish: MTLRenderPipelineState
    private var targets: [MTLTexture] = []
    private var descriptors: [String: NativeAtlasRecipe.Actor] = [:]
    private var paletteBackgroundElapsed: Double?

    init?(device: MTLDevice) {
        self.device = device
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "metalShapeGenomeVertex") else { return nil }
        func pipeline(_ name: String, _ format: MTLPixelFormat, fullscreen: Bool = false, mask: MTLColorWriteMask = .all) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = fullscreen ? library.makeFunction(name: "dayObjectsFullscreenVertex") : vertex
            d.fragmentFunction = library.makeFunction(name: name)
            d.colorAttachments[0].pixelFormat = format
            d.colorAttachments[0].writeMask = mask
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        guard let composite = pipeline("nativeAtlasComposite", .rgba16Float),
              let display = pipeline("nativeAtlasDisplay", .rgba16Float),
              let gradient = pipeline("dayObjectsMeshGradientFragment", .rgba16Float, fullscreen: true, mask: [.red, .green, .blue]),
              let finish = pipeline("nativeAtlasFinishFragment", .bgra8Unorm_srgb, fullscreen: true) else { return nil }
        self.composite = composite; self.display = display
        self.gradient = gradient; self.finish = finish
    }

    func adapt(_ frame: DayObjectRenderFrame, recipe: NativeAtlasRecipe, aspect: Float, elapsed: Double = 0, soundPulses: [String: Double] = [:], isPalette: Bool = false) -> DayObjectRenderFrame {
        for actor in recipe.actors { descriptors[actor.eventID] = actor }
        let activeIDs = Set(frame.actors.map(\.eventID))
        descriptors = descriptors.filter { activeIDs.contains($0.key) }
        // The picker owns its slot positions and feedback envelopes; only its
        // actual contour/material come from the same event-bound atlas recipe.
        if isPalette { return frame }
        let actors = frame.actors.map { old -> DayObjectRenderActor in
            guard let spec = descriptors[old.eventID] else { return old }
            let pose = old.gpuActor
            let resonance = Float(DayObjectSoundResonance.scale(elapsedSinceAttack: elapsed - (soundPulses[old.eventID] ?? -100), depth: Double(pose.depth)))
            let size = spec.size / 2.72 * (0.7 + 0.3 * pose.opacity) * resonance
            let gpu = DayObjectGPUActor(
                position: SIMD2((spec.position.x - 0.5) * max(aspect, 1), (0.5 - spec.position.y) * max(1 / aspect, 1)),
                direction: SIMD2(cos(spec.rotation), -sin(spec.rotation)),
                halfSize: SIMD2(repeating: size), opacity: pose.opacity, trailLength: 0,
                shape: pose.shape, appearanceIndex: pose.appearanceIndex, depth: pose.depth,
                materialPhase: pose.materialPhase, localDepthSoftness: 0
            )
            return DayObjectRenderActor(actorID: old.actorID, eventID: old.eventID, gpuActor: gpu, gpuAppearance: old.gpuAppearance)
        }
        return DayObjectRenderFrame(choreographyTime: frame.choreographyTime, actors: actors, postProcess: frame.postProcess)
    }

    func encode(commandBuffer: MTLCommandBuffer, output: MTLTexture, recipe: NativeAtlasRecipe, frame: DayObjectRenderFrame, damage: Float, scene: DayObjectScene, elapsed: Double, pointToPixelScale: Float, isPalette: Bool, colorVariants: [String: Int] = [:]) -> Bool {
        let renderScale = min(1.0, 1536.0 / Double(max(output.width, output.height)))
        let w = max(1, Int(Double(output.width) * renderScale)), h = max(1, Int(Double(output.height) * renderScale))
        if targets.first?.width != w || targets.first?.height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            guard let first = device.makeTexture(descriptor: d), let second = device.makeTexture(descriptor: d) else { return false }
            targets = [first, second]
        }
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = targets[0]
        clear.colorAttachments[0].loadAction = .clear; clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let clearEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: clear) else { return false }
        if isPalette {
            if paletteBackgroundElapsed == nil { paletteBackgroundElapsed = elapsed }
        } else { paletteBackgroundElapsed = nil }
        var background = DayObjectsMeshGradientUniforms(scene: scene, resolution: SIMD2(Float(w), Float(h)), elapsedTime: paletteBackgroundElapsed ?? elapsed)
        clearEncoder.setRenderPipelineState(gradient)
        clearEncoder.setFragmentBytes(&background, length: DayObjectsMeshGradientUniforms.metalStride, index: 0)
        clearEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        clearEncoder.endEncoding()
        var source = 0
        for actor in frame.actors {
            guard let spec = descriptors[actor.eventID] else { continue }
            let target = 1 - source
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = targets[target]
            pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.setRenderPipelineState(composite)
            encoder.setFragmentTexture(targets[source], index: 0)
            var geometry = spec.geometry, material = spec.material.primaryCanvasMaterial
            if let variant = colorVariants[actor.eventID], spec.materialID != .sunset {
                material = material.withColorVariant(variant)
            }
            let eligible: Set<MetalShapeMaterial> = [.solid, .sideLight, .radialTwo, .radialThree, .proceduralLight, .proceduralFlow]
            let aspect = Float(w) / Float(h), pose = actor.gpuActor
            let center = SIMD2(0.5 + pose.position.x / max(aspect, 1), 0.5 - pose.position.y / max(1 / aspect, 1))
            let saturation = pose.presentationSaturation
            let placement: [SIMD4<Float>] = [
                SIMD4(center.x, center.y, pose.halfSize.x * 2.72, spec.rotation),
                SIMD4(Float(w), Float(h), pose.opacity, eligible.contains(spec.materialID) ? 1 : 0),
                SIMD4(Float(recipe.intersectionType), recipe.intersectionStrength, saturation, pose.removalEmphasis),
                SIMD4(pose.paletteMorph, isPalette ? 1 : 0, 0, 0)
            ]
            encoder.setFragmentBytes(&geometry, length: MetalShapeGenomeUniforms.metalStride, index: 0)
            encoder.setFragmentBytes(&material, length: MetalShapeMaterialUniforms.metalStride, index: 1)
            placement.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
            source = target
        }
        let pass = MTLRenderPassDescriptor()
        let traceTarget = 1 - source
        pass.colorAttachments[0].texture = targets[traceTarget]
        pass.colorAttachments[0].loadAction = .dontCare; pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(display); encoder.setFragmentTexture(targets[source], index: 0)
        let seed = UInt64(recipe.seedHex, radix: 16) ?? 0
        var effect = SIMD4<Float>(damage, Float(recipe.glitchType), Float(seed & 65535) / 65535, Float((seed >> 16) & 65535) / 65535)
        encoder.setFragmentBytes(&effect, length: 16, index: 0)
        var post = DayObjectsPostUniforms(frame: frame, scene: scene, resolution: SIMD2(Float(output.width), Float(output.height)), pointToPixelScale: pointToPixelScale)
        var focus = SIMD4<Float>(post.blurRadiusPixels / Float(max(output.width, output.height)), 0, 0, 0)
        encoder.setFragmentBytes(&focus, length: 16, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
        let finalPass = MTLRenderPassDescriptor()
        finalPass.colorAttachments[0].texture = output
        finalPass.colorAttachments[0].loadAction = .dontCare
        finalPass.colorAttachments[0].storeAction = .store
        guard let finalEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalPass) else { return false }
        finalEncoder.setRenderPipelineState(finish)
        finalEncoder.setFragmentTexture(targets[traceTarget], index: 0)
        finalEncoder.setFragmentBytes(&post, length: DayObjectsPostUniforms.metalStride, index: 0)
        finalEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finalEncoder.endEncoding()
        return true
    }
}
