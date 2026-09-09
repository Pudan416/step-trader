#if DEBUG || INTERNAL_BUILD
import CoreGraphics
import Metal
import UIKit

enum MetalShapeGenomeRendererError: Error {
    case unavailableDevice
    case unavailableCommandQueue
    case unavailableLibrary
    case unavailableFunction(String)
    case unavailablePipeline
    case unavailableTexture
    case unavailableCommandBuffer
    case unavailableEncoder
    case renderingFailed
    case imageConversionFailed
}

enum MetalShapeGenomeRenderer {
    private static let device = MTLCreateSystemDefaultDevice()
    private static let queue = device?.makeCommandQueue()
    private static let pipeline: MTLRenderPipelineState? = {
        guard let device,
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "metalShapeGenomeVertex"),
              let fragment = library.makeFunction(name: "metalShapeGenomeFragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()

    static func image(
        preset: MetalShapePreset,
        material: MetalShapeMaterial,
        seed: UInt64,
        size: CGSize,
        scale: CGFloat,
        blurMode: UInt32 = 0
    ) async throws -> UIImage {
        let width = max(Int((size.width * scale).rounded()), 1)
        let height = max(Int((size.height * scale).rounded()), 1)
        guard let device else {
            throw MetalShapeGenomeRendererError.unavailableDevice
        }
        guard let queue else {
            throw MetalShapeGenomeRendererError.unavailableCommandQueue
        }
        guard let pipeline else {
            throw MetalShapeGenomeRendererError.unavailablePipeline
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget]
        textureDescriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw MetalShapeGenomeRendererError.unavailableTexture
        }
        guard let commandBuffer = queue.makeCommandBuffer() else {
            throw MetalShapeGenomeRendererError.unavailableCommandBuffer
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw MetalShapeGenomeRendererError.unavailableEncoder
        }

        let frame = MetalShapeGenomeFrame.make(
            preset: preset,
            material: material,
            seed: seed,
            blurMode: blurMode
        )
        var geometry = frame.geometry
        var materialUniforms = frame.material
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &geometry,
            length: MetalShapeGenomeUniforms.metalStride,
            index: 0
        )
        encoder.setFragmentBytes(
            &materialUniforms,
            length: MetalShapeMaterialUniforms.metalStride,
            index: 1
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        await commandBuffer.completed()
        guard commandBuffer.status == .completed else {
            throw MetalShapeGenomeRendererError.renderingFailed
        }
        guard let image = makeImage(texture: texture, scale: scale, correctSRGBAlpha: material == .directionalBlur || material == .sunset) else {
            throw MetalShapeGenomeRendererError.imageConversionFailed
        }
        return image
    }

    private static func makeImage(texture: MTLTexture, scale: CGFloat, correctSRGBAlpha: Bool) -> UIImage? {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        if correctSRGBAlpha {
            // Metal encodes linear premultiplied RGB into sRGB. CoreGraphics expects
            // sRGB RGB multiplied by alpha; convert before exporting soft transparent edges.
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let alpha = Double(bytes[offset + 3]) / 255
                for channel in 0..<3 {
                    guard alpha > 0 else { bytes[offset + channel] = 0; continue }
                    let encoded = Double(bytes[offset + channel]) / 255
                    let linear = encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
                    let straight = min(linear / alpha, 1)
                    let srgb = straight <= 0.0031308 ? straight * 12.92 : 1.055 * pow(straight, 1 / 2.4) - 0.055
                    bytes[offset + channel] = UInt8(min(max((srgb * alpha * 255).rounded(), 0), 255))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(
                width: texture.width,
                height: texture.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
#endif

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
            // The legacy picker ends its added-state transition at 0.08.
            // Map that endpoint to neutral gray while preserving the transition.
            let saturation = isPalette
                ? max(0, min(1, (pose.presentationSaturation - 0.08) / 0.92))
                : pose.presentationSaturation
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
