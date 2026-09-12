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
        blurMode: UInt32 = 0,
        colorVariant: Int? = nil
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
        var materialUniforms = colorVariant.map { frame.material.withColorVariant($0) } ?? frame.material
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
