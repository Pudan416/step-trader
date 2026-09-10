import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct Review {
    static func main() throws {
        let width = 1440, height = 1060
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.038, green: 0.038, blue: 0.08, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let white = NSColor(calibratedWhite: 0.95, alpha: 1)
        ("NOWHERE / RANDOM OBJECTS" as NSString).draw(at: CGPoint(x: 60, y: 978), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: white])
        ("Decorative objects for Shield + PayGate. Available from the first day." as NSString).draw(at: CGPoint(x: 60, y: 940), withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: white.withAlphaComponent(0.55)])
        let seeds: [UInt32] = [44100105, 93222711, 39831142, 12941108, 43032274, 126666]
        for (index, seed) in seeds.enumerated() {
            let x = 60 + (index % 3) * 460
            let y = 110 + (1 - index / 3) * 400
            let image = GateArtworkRenderer.render(GateArtwork(seed: seed), pixels: 840)!
            context.draw(image, in: CGRect(x: x + 40, y: y + 20, width: 330, height: 330))
            (String(format: "%02d", index + 1) as NSString).draw(at: CGPoint(x: x + 194, y: y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: white.withAlphaComponent(0.4)])
        }
        NSGraphicsContext.restoreGraphicsState()
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }
}
