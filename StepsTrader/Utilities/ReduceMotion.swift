import SwiftUI

// MARK: - Reduce Motion helpers
//
// Apple HIG: when "Reduce Motion" is enabled (Settings → Accessibility → Motion),
// motion-heavy transitions should fall back to a cross-fade (opacity) and springs
// should fall back to a short ease-in-out (or no animation).
//
// Two call-site patterns:
// 1. Declarative:
//        view.motionAnimation(.spring(...), value: state)
// 2. Imperative (use the env-derived `reduceMotion` flag):
//        withMotionAnimation(.spring(...), reduceMotion: reduceMotion) { state = ... }
//
// For transitions, branch on `@Environment(\.accessibilityReduceMotion)` at the
// call site:
//        view.transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))

extension View {
    /// Applies an animation only when Reduce Motion is OFF; otherwise applies a short cross-fade (or none).
    /// Use this for entrance/exit/scale/spring animations that are visually motion-heavy.
    func motionAnimation<V: Equatable>(
        _ animation: Animation? = .default,
        value: V,
        reducedMotionFallback: Animation? = .easeInOut(duration: 0.15)
    ) -> some View {
        modifier(MotionAnimationModifier(animation: animation, reducedMotionFallback: reducedMotionFallback, value: value))
    }
}

private struct MotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let reducedMotionFallback: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? reducedMotionFallback : animation, value: value)
    }
}

/// Convenience helper for one-shot `withAnimation`: respects Reduce Motion.
@MainActor
func withMotionAnimation<Result>(
    _ animation: Animation? = .default,
    reduceMotion: Bool,
    reducedMotionFallback: Animation? = .easeInOut(duration: 0.15),
    _ body: () -> Result
) -> Result {
    withAnimation(reduceMotion ? reducedMotionFallback : animation, body)
}
