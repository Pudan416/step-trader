import CoreGraphics
import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#endif

/// Snapshots exported with the same catalog, contours and materials as happenings.
/// Bundled in both targets so an empty day and a cold Screen Time extension work offline.
enum GateArtworkRenderer {
    static func render(_ artwork: GateArtwork, pixels: Int, bundle: Bundle = .main) -> CGImage? {
        let size = min(max(pixels, 1), 1024)
        guard let url = bundle.url(forResource: artwork.resourceName, withExtension: "png",
                                   subdirectory: "GateArtworkImages"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()
    }

    #if canImport(UIKit)
    static func image(_ artwork: GateArtwork, pointSize: CGFloat, scale: CGFloat = 3) -> UIImage? {
        guard let cgImage = render(artwork, pixels: Int(pointSize * scale)) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    #endif
}
