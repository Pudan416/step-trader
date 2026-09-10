import AppKit
import ImageIO
import UniformTypeIdentifiers

// swiftc -parse-as-library Shared/GateArtwork.swift artifacts/gate-artwork-review/render-objects.swift -o /tmp/gate-review
// /tmp/gate-review Shared/GateArtworkImages artifacts/gate-artwork-review/objects.png
@main struct Review {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let width = 1600, height = 1130
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.075, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ alpha: CGFloat = 1) {
            (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(white: 1, alpha: alpha)])
        }
        text("Nowhere / реальные формы happenings", 48, 1050, 34)
        text("Те же контуры и материалы. Случайный объект доступен даже до первого события.", 48, 1010, 22, 0.6)
        let names = ["Вогнутый квадрат", "Четырёхлистник", "Ветряной цветок", "Снежинка", "Мягкий квадрат", "Треугольник", "Шестиугольник"]
        for row in 0..<3 {
            text(GateArtwork.materialIDs[row], 48, CGFloat(960 - row * 300), 18, 0.6)
            for column in 0..<7 {
                let artwork = GateArtwork(seed: UInt32(row * 7 + column))
                let image = NSImage(contentsOf: root.appendingPathComponent(artwork.resourceName + ".png"))!
                let x = CGFloat(36 + column * 218), y = CGFloat(740 - row * 300)
                image.draw(in: CGRect(x: x, y: y, width: 210, height: 210))
                text(names[column], x + 10, y - 20, 17, 0.75)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
    }
}
