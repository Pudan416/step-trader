import AppKit
import ImageIO
import UniformTypeIdentifiers

// Arrange unedited simulator captures of production components on test backgrounds.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let w = 1568, h = 1040
let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
    (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)])
}
text("Nowhere · цвет дня", 40, 975, 30)
text("Реальные компоненты приложения на четырёх тестовых фонах", 40, 941, 18)
for (i, item) in [("sage", "Зелёный"), ("blue", "Синий"), ("lilac", "Сиреневый"), ("clay", "Глиняный")].enumerated() {
    let x = CGFloat(40 + i * 384)
    text(item.1, x, 895, 20)
    let screenshot = NSImage(contentsOf: root.appendingPathComponent(item.0 + ".png"))!
    let height = 336 * screenshot.size.height / screenshot.size.width
    screenshot.draw(in: CGRect(x: x, y: 874 - height, width: 336, height: height))
}
text("Сравнение компонентов: открытая панель и нижние кнопки показаны вместе для оценки цветов.", 40, 60, 16)
NSGraphicsContext.restoreGraphicsState()
let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent("palette-review.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, context.makeImage()!, nil)
CGImageDestinationFinalize(dest)
