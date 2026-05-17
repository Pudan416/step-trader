import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 4: // ARGB (16-bit)
            (r, g, b, a) = (
                (int >> 8 & 0xF) * 17,
                (int >> 4 & 0xF) * 17,
                (int & 0xF) * 17,
                (int >> 12 & 0xF) * 17
            )
        case 6: // RGB (24-bit)
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: // ARGB (32-bit)
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, int >> 24)
        default:
            (r, g, b, a) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let r8 = UInt8((max(0, min(1, r)) * 255).rounded())
        let g8 = UInt8((max(0, min(1, g)) * 255).rounded())
        let b8 = UInt8((max(0, min(1, b)) * 255).rounded())
        return String(format: "#%02X%02X%02X", r8, g8, b8)
    }

    /// Linear interpolation between two colors in sRGB space.
    static func lerp(_ a: Color, _ b: Color, t: Double) -> Color {
        let t = min(1, max(0, t))
        let uiA = UIColor(a)
        let uiB = UIColor(b)
        var rA: CGFloat = 0, gA: CGFloat = 0, bA: CGFloat = 0, aA: CGFloat = 0
        var rB: CGFloat = 0, gB: CGFloat = 0, bB: CGFloat = 0, aB: CGFloat = 0
        uiA.getRed(&rA, green: &gA, blue: &bA, alpha: &aA)
        uiB.getRed(&rB, green: &gB, blue: &bB, alpha: &aB)
        let ct = CGFloat(t)
        return Color(
            .sRGB,
            red: Double(rA + (rB - rA) * ct),
            green: Double(gA + (gB - gA) * ct),
            blue: Double(bA + (bB - bA) * ct),
            opacity: Double(aA + (aB - aA) * ct)
        )
    }

    /// Desaturate toward gray by a factor 0...1
    func desaturated(by factor: Double) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let newSat = max(0, s * CGFloat(1.0 - factor))
        return Color(UIColor(hue: h, saturation: newSat, brightness: b, alpha: a))
    }
}
