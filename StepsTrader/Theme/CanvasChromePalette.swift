import SwiftUI
import simd

/// Stable control colors derived from saved background pigment, never a rendered frame.
/// Curated tonal families bound saturation; measured contrast keeps text and actions readable.
struct CanvasChromePalette: Equatable {
    enum Family: CaseIterable { case sage, blue, lilac, clay, neutral }

    let family: Family
    let surface: DayObjectRGB
    let textPrimary: DayObjectRGB
    let textSecondary: DayObjectRGB
    let accent: DayObjectRGB
    let onAccent: DayObjectRGB
    let track: DayObjectRGB
    let earned: DayObjectRGB

    static let fallback = resolve(backgroundColors: [])

    static func resolve(backgroundColors: [DayObjectRGB]) -> Self {
        // Sorting makes the result independent of input order, including float accumulation.
        let colors = backgroundColors.sorted {
            if $0.sRGB.x != $1.sRGB.x { return $0.sRGB.x < $1.sRGB.x }
            if $0.sRGB.y != $1.sRGB.y { return $0.sRGB.y < $1.sRGB.y }
            return $0.sRGB.z < $1.sRGB.z
        }
        var pigment = SIMD3<Float>.zero
        var hueVector = SIMD2<Float>.zero
        var weight: Float = 0
        for color in colors {
            let lab = color.perceptualOKLab
            let chroma = simd_length(SIMD2(lab.y, lab.z))
            // Near-white and gray palette entries should not erase the day's hue.
            guard chroma > 0.025 else { continue }
            let importance = min(chroma, 0.18)
            pigment += color.sRGB * importance
            hueVector += SIMD2(lab.y, lab.z) * importance
            weight += importance
        }
        let source = weight > 0 ? DayObjectRGB(sRGB: pigment / weight) : DayObjectRGB(hex: "#808080")
        let family: Family
        if weight == 0 || simd_length(hueVector / max(weight, 0.001)) < 0.015 {
            family = .neutral
        } else {
            let direction = simd_normalize(hueVector)
            family = Family.allCases.filter { $0 != .neutral }.max { lhs, rhs in
                func similarity(_ item: Family) -> Float {
                    let lab = DayObjectRGB(hex: item.tokens.reference).perceptualOKLab
                    return simd_dot(direction, simd_normalize(SIMD2(lab.y, lab.z)))
                }
                return similarity(lhs) < similarity(rhs)
            } ?? .neutral
        }
        let t = family.tokens
        func mix(_ a: DayObjectRGB, _ b: DayObjectRGB, _ amount: Float) -> DayObjectRGB {
            DayObjectRGB(sRGB: a.sRGB * (1 - amount) + b.sRGB * amount)
        }
        let surface = mix(DayObjectRGB(hex: t.surface), source.darkened(by: 0.28), family == .neutral ? 0 : 0.12)
        let text = DayObjectRGB(hex: t.text).lightened(toMinimumContrast: 7, against: surface.linearRGB)
        let secondary = DayObjectRGB(hex: t.secondary).lightened(toMinimumContrast: 4.5, against: surface.linearRGB)
        let softSource = source.lightened(toMinimumContrast: 8, against: surface.linearRGB)
        let accent = mix(DayObjectRGB(hex: t.accent), softSource, family == .neutral ? 0 : 0.18)
            .lightened(toMinimumContrast: 7, against: surface.linearRGB)
        return Self(family: family, surface: surface, textPrimary: text, textSecondary: secondary,
                    accent: accent, onAccent: surface,
                    track: mix(surface, secondary, 0.20), earned: mix(surface, accent, 0.44))
    }

    var surfaceColor: Color { color(surface) }
    var textColor: Color { color(textPrimary) }
    var secondaryColor: Color { color(textSecondary) }
    var accentColor: Color { color(accent) }
    var onAccentColor: Color { color(onAccent) }
    var trackColor: Color { color(track) }
    var earnedColor: Color { color(earned) }

    private func color(_ value: DayObjectRGB) -> Color {
        Color(.sRGB, red: Double(value.sRGB.x), green: Double(value.sRGB.y), blue: Double(value.sRGB.z))
    }
}

private extension CanvasChromePalette.Family {
    var tokens: (reference: String, surface: String, text: String, secondary: String, accent: String) {
        switch self {
        case .sage: ("#78966B", "#223429", "#F2F4E8", "#BDC9B5", "#D7EDB0")
        case .blue: ("#6987A5", "#202D3C", "#F1F4F7", "#BBC8D8", "#BEDFFA")
        case .lilac: ("#9581AA", "#32283C", "#F7F2FA", "#D0C1DA", "#E2CDF4")
        case .clay: ("#AE7E68", "#3B2B28", "#FCF3EB", "#DCC5B8", "#F4D0BA")
        case .neutral: ("#808080", "#2B3030", "#F2F3F0", "#C4CBC7", "#DCE5DC")
        }
    }
}

extension EnvironmentValues {
    @Entry var canvasChromePalette = CanvasChromePalette.fallback
}

private struct CanvasChromeSurface<S: Shape>: ViewModifier {
    @Environment(\.canvasChromePalette) private var palette
    let shape: S

    func body(content: Content) -> some View {
        content.background(palette.surfaceColor, in: shape)
    }
}

extension View {
    func canvasChromeSurface<S: Shape>(in shape: S) -> some View {
        modifier(CanvasChromeSurface(shape: shape))
    }
}
