import SwiftUI

// MARK: - Glass card modifier (iOS 26+ liquid glass, fallback ultraThinMaterial)

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.clear)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    func glassCircle(size: CGFloat, opacity: CGFloat = 1) -> some View {
        self.modifier(GlassCircleModifier(size: size, opacity: opacity))
    }
}

// MARK: - Circle variant

private struct GlassCircleModifier: ViewModifier {
    let size: CGFloat
    let opacity: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular, in: Circle())
                        .opacity(opacity)
                }
                .clipShape(Circle())
        } else {
            content
                .background(
                    Circle().fill(.ultraThinMaterial).opacity(opacity)
                )
                .clipShape(Circle())
        }
    }
}
