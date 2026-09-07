import CoreGraphics
import Metal
import UIKit

enum DayObjectsImageRenderer {
    static func image(
        input: EditorialCanvasRenderInput,
        size: CGSize,
        scale: CGFloat,
        elapsedTime: TimeInterval
    ) async -> UIImage? {
        await Task.detached(priority: .utility) {
            DayObjectsRenderer.prepareResources()
        }.value
        guard !Task.isCancelled else { return nil }
        let scene = DayObjectScene.make(input: input.sceneInput)
        let environment = DayObjectEnvironment(
            motionEnergy: input.sceneInput.motionEnergy,
            visualClarity: input.sceneInput.visualClarity
        )
        guard let renderer = DayObjectsRenderer.create(
            scene: scene,
            environment: environment,
            digitalImpact: input.digitalImpact
        ) else { return nil }

        let texture: MTLTexture? = await withCheckedContinuation { continuation in
            renderer.renderOffscreen(
                size: size,
                pointScale: scale,
                elapsedTime: elapsedTime
            ) { texture, _ in
                continuation.resume(returning: texture)
            }
        }
        guard let texture else { return nil }
        return makeImage(texture: texture, scale: scale)
    }

    private static func makeImage(texture: MTLTexture, scale: CGFloat) -> UIImage? {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let cgImage = CGImage(
            width: texture.width,
            height: texture.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
