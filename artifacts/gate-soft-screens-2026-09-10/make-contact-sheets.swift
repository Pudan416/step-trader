import AppKit
import ImageIO
import UniformTypeIdentifiers

// Contact sheets only arrange the original screenshots; the screens are unedited.
@main struct ContactSheets {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let sheets: [(String, String, String, [(String, String, String)])] = [
            ("01-flow", "Nowhere / путь в приложение", "Shield — реконструкции. PayGate — снимок интерфейса с тестовыми данными.", [
                ("01-shield", "01  Блокировка", "Реконструкция системного экрана"),
                ("02-shield-notification", "02  После отправки уведомления", "Реконструкция системного экрана"),
                ("03-paygate", "03  Выбор времени", "Скриншот PayGate")
            ]),
            ("02-paygate-states", "Nowhere / состояния PayGate", "Снимки текущего SwiftUI-интерфейса. Мягкие градиенты, новые цвета.", [
                ("04-paygate-not-enough", "01  Не хватает colors", "Баланс 2 — все варианты недоступны"),
                ("05-paygate-day-reset", "02  Скоро закончится день", "Предупреждение о сбросе"),
                ("06-paygate-alternative", "03  Другой случайный объект", "Те же действия, новый образ")
            ]),

        ]
        for (name, title, subtitle, items) in sheets {
            let width = 1536, height = 1280
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.075, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, alpha: CGFloat = 1, bold: Bool = false) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                    .foregroundColor: NSColor(calibratedWhite: 1, alpha: alpha)
                ])
            }
            text(title, x: 64, y: 1203, size: 32, bold: true)
            text(subtitle, x: 64, y: 1163, size: 21, alpha: 0.6)
            for (index, item) in items.enumerated() {
                let x = CGFloat(64 + index * 480)
                text(item.1, x: x, y: 1101, size: 21, bold: true)
                let screenshot = NSImage(contentsOf: root.appendingPathComponent(item.0 + ".png"))!
                let h = 448 * screenshot.size.height / screenshot.size.width
                screenshot.draw(in: CGRect(x: x, y: 1090 - h, width: 448, height: h))
                text(item.2, x: x, y: 75, size: 17, alpha: 0.55)
            }
            NSGraphicsContext.restoreGraphicsState()
            let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent(name + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, context.makeImage()!, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
