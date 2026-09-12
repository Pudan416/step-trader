import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A lightweight static object for extension-safe rendering. Uses the canvas's
/// palette collection, with bounded organic silhouettes and radial materials.
/// No Metal, network, personal data or animated render loop is needed.
enum GateArtworkRenderer {
    static func render(_ artwork: GateArtwork, pixels: Int) -> CGImage? {
        let size = min(max(pixels, 1), 1024)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.scaleBy(x: CGFloat(size), y: CGFloat(size))
        let palette = GradientPalette.allCases[Int(artwork.seed / 5) % GradientPalette.allCases.count]
        let colors = palette.colorHexes.map(color)
        let family = Int(artwork.seed % 5)
        let rotation = CGFloat(artwork.seed / 35 % 360) * .pi / 180
        let phase = CGFloat(artwork.seed / 12600 % 1000) / 1000 * .pi * 2
        let path = silhouette(family: family, rotation: rotation, phase: phase)

        context.addPath(path)
        context.clip()
        context.setFillColor(colors[2])
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))

        let focus = CGPoint(x: 0.5 + cos(rotation) * 0.24, y: 0.5 + sin(rotation) * 0.24)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [colors[0], colors[1], colors[2], colors[3]] as CFArray,
            locations: [0, 0.27, 0.68, 1]
        ) {
            context.drawRadialGradient(gradient, startCenter: focus, startRadius: 0,
                                       endCenter: CGPoint(x: 0.51, y: 0.48), endRadius: 0.64,
                                       options: [.drawsAfterEndLocation])
        }

        // Broad reflected light across the opposite lobe gives the body depth.
        let reflection = CGPoint(x: 1 - focus.x, y: 1 - focus.y)
        if let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [colors[0].copy(alpha: 0.74)!, colors[1].copy(alpha: 0.3)!, colors[1].copy(alpha: 0)!] as CFArray,
            locations: [0, 0.4, 1]
        ) {
            context.drawRadialGradient(glow, startCenter: reflection, startRadius: 0,
                                       endCenter: reflection, endRadius: 0.34, options: [])
        }

        // Very fine nested contours follow the same geometry, like a soft print.
        // They are restrained at shield size and become visible in the PayGate.
        context.setLineWidth(0.0009)
        for index in 0..<48 {
            let scale = 0.38 + CGFloat(index) * 0.0125
            var transform = CGAffineTransform(translationX: 0.5, y: 0.5)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -0.5, y: -0.5)
            if let contour = path.copy(using: &transform) {
                context.addPath(contour)
                context.setStrokeColor(colors[0].copy(alpha: index.isMultiple(of: 3) ? 0.10 : 0.035)!)
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    private static func silhouette(family: Int, rotation: CGFloat, phase: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let lobes = [2, 3, 4, 5, 2][family]
        let amplitude: CGFloat = [0.15, 0.14, 0.105, 0.075, 0.07][family]
        for index in 0...360 {
            let angle = CGFloat(index) / 360 * .pi * 2
            let radius = 0.33 + amplitude * cos(CGFloat(lobes) * angle)
                + 0.018 * sin(3 * angle + phase)
            let x = radius * cos(angle) * (family == 4 ? 0.75 : 0.94)
            let y = radius * sin(angle)
            let point = CGPoint(x: 0.5 + x * cos(rotation) - y * sin(rotation),
                                y: 0.5 + x * sin(rotation) + y * cos(rotation))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func color(_ hex: String) -> CGColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return CGColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }

    #if canImport(UIKit)
    static func image(_ artwork: GateArtwork, pointSize: CGFloat, scale: CGFloat = 3) -> UIImage? {
        guard let cgImage = render(artwork, pixels: Int(pointSize * scale)) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
    #endif
}
