import SwiftUI
import UIKit

// MARK: - Liquid Glass primitives (iOS 26+ with graceful fallback)

/// Visual style for the Liquid Glass treatment.
/// - `.lens`: highly transparent, strong refraction + specular. Best for
///   floating chrome (tab bars, FABs, banners) over rich content.
/// - `.lensTinted`: same lens look, with a subtle adaptive tint wash
///   underneath for legibility of body text without giving up refraction.
/// - `.frosted`: more material, less refraction. Use only when even
///   `.lensTinted` is not enough (long-form reading, modals).
enum LiquidGlassStyle {
    case lens
    case lensTinted
    case frosted
}

/// Selects how a glass surface picks its tint color.
/// - `.auto`: follows the global slowly-cycling shimmer color (default).
/// - `.off`: no tint, clean clear lens.
/// - `.fixed(color)`: pins to a specific color forever.
enum GlassTint: Equatable {
    case auto
    case off
    case fixed(Color)
}

// MARK: - Environment value: current global shimmer color

private struct GlassShimmerColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// Currently active "shimmer" tint, published by `GlassShimmerProvider` at
    /// the root of the app. `nil` outside a provider scope (defaults to no tint).
    var glassShimmerColor: Color? {
        get { self[GlassShimmerColorKey.self] }
        set { self[GlassShimmerColorKey.self] = newValue }
    }
}

// MARK: - Shimmer provider (one TimelineView for the whole app)

/// Wraps the root view tree and publishes a slowly-oscillating color through
/// the environment. The two endpoints of the oscillation come from the
/// user's currently selected `GradientPalette` (Settings → Appearance):
/// the lightest tone (`bright`)
/// and the darkest tone (`dark`). Glass surfaces with `tint: .auto`
/// automatically pick it up via the iOS 26 `Glass.tint(_:)` API.
///
/// Cost: one TimelineView running at ~6fps. Only views reading
/// `@Environment(\.glassShimmerColor)` are re-evaluated when the color drifts.
struct GlassShimmerProvider<Content: View>: View {
    /// Seconds for one complete light → dark → light cycle.
    var cycleDuration: Double = 24
    /// Redraw rate. 6fps is plenty for a slow color drift.
    var fps: Double = 6
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SharedKeys.gradientPalette) private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue

    private var palette: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: GradientPalette.normalized(rawValue: gradientPaletteRaw))
    }

    private var endpoints: (light: Color, dark: Color) {
        (palette.bright, palette.dark)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let twoPi = Double.pi * 2
            // sin gives a soft hold at the endpoints (slows down near 0 and 1)
            let phase = (sin(twoPi * t / cycleDuration - .pi / 2) + 1) / 2
            let color = Self.mix(endpoints.light, endpoints.dark, t: phase)
            content()
                .environment(\.glassShimmerColor, color)
        }
    }

    private static func mix(_ a: Color, _ b: Color, t: Double) -> Color {
        let ua = UIColor(a)
        let ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let tt = CGFloat(t)
        return Color(
            red: Double(r1 + (r2 - r1) * tt),
            green: Double(g1 + (g2 - g1) * tt),
            blue: Double(b1 + (b2 - b1) * tt)
        )
    }
}

// MARK: - Tint strengths

/// Centralized tint values so all glass surfaces share the same wash strength.
enum AppGlassTint {
    /// How much tint the iOS 26 `.clear` lens carries. Keep low — lens is already busy.
    static let lensStrength: Double = 0.20
    /// Frosted glass can carry slightly more tint and stay readable.
    static let frostedStrength: Double = 0.24
    /// Pre–iOS 26 fallback: a flat color over `.ultraThinMaterial`.
    static let fallbackStrength: Double = 0.12
}

@available(iOS 26.0, *)
func makeTintedLensGlass(tint: Color?) -> Glass {
    var g = Glass.clear.interactive()
    if let tint { g = g.tint(tint.opacity(AppGlassTint.lensStrength)) }
    return g
}

@available(iOS 26.0, *)
func makeTintedFrostedGlass(tint: Color?) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint.opacity(AppGlassTint.frostedStrength)) }
    return g
}

// MARK: - Card modifier

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var style: LiquidGlassStyle = .lens
    var tint: GlassTint = .auto

    @Environment(\.glassShimmerColor) private var shimmerColor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var resolvedTint: Color? {
        switch tint {
        case .auto:           return shimmerColor
        case .off:            return nil
        case .fixed(let c):   return c
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let t = resolvedTint

        if reduceTransparency {
            content
                .background(adaptiveOpaqueFill, in: shape)
                .overlay(shape.strokeBorder(rim, lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            switch style {
            case .lens:
                content.glassEffect(makeTintedLensGlass(tint: t), in: shape)
            case .lensTinted:
                content
                    .background(neutralTintWash, in: shape)
                    .glassEffect(makeTintedLensGlass(tint: t), in: shape)
            case .frosted:
                content.glassEffect(makeTintedFrostedGlass(tint: t), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    if style == .lensTinted {
                        shape.fill(neutralTintWash)
                    }
                    if let t {
                        shape.fill(t.opacity(AppGlassTint.fallbackStrength))
                    }
                }
                .overlay(shape.strokeBorder(rim, lineWidth: 0.5))
        }
    }

    private var neutralTintWash: Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.28)
    }

    private var rim: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.primary.opacity(0.10)
    }

    private var adaptiveOpaqueFill: Color {
        colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.96)
    }
}

extension View {
    /// Liquid Glass card. Defaults to `.lens` with the global cycling tint.
    /// Use `tint: .off` for clean lens, `tint: .fixed(.something)` to pin a color.
    func glassCard(
        cornerRadius: CGFloat = 16,
        style: LiquidGlassStyle = .lens,
        tint: GlassTint = .auto
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, style: style, tint: tint))
    }
}

// MARK: - Halo shadow for short labels over gradient/canvas/lens

private struct ContrastingLabelShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    /// Subtle halo. Kept tight (radius ≤ 1.5) so it functions as an
    /// edge-anti-alias rather than a visible glow.
    func body(content: Content) -> some View {
        let halo = colorScheme == .dark ? Color.black : Color.white
        return content
            .shadow(color: halo.opacity(0.35), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: halo.opacity(0.18), radius: 1.5, x: 0, y: 0)
    }
}

extension View {
    /// Adds an adaptive halo so short labels stay legible when placed
    /// directly on top of the energy gradient, generative canvas, or `.lens`
    /// glass without their own card.
    func contrastingOnGlass() -> some View {
        modifier(ContrastingLabelShadow())
    }

    /// Expands the tappable region to at least `size`pt while keeping the
    /// same visual layout.
    func minimumHitTarget(_ size: CGFloat = 44) -> some View {
        frame(minWidth: size, minHeight: size).contentShape(Rectangle())
    }
}

// MARK: - Brand ink token

/// Single source of truth for foreground ink that sits on
/// `AppColors.brandAccent` capsules and CTAs.
enum AppAccentInk {
    static var primary: Color { Color(red: 0.08, green: 0.08, blue: 0.08) }
}
