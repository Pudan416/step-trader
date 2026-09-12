#if DEBUG || INTERNAL_BUILD
import SwiftUI

/// Transparent performance layer for the unobstructed single Day Objects
/// canvas. It reports normalized samples and owns no audio resources.
struct DayObjectsLeadGestureSurface: View {
    let isEnabled: Bool
    let uiExclusionRegion: DayObjectNormalizedRect?
    let onBegin: @MainActor (LeadGestureSample) -> Void
    let onUpdate: @MainActor (LeadGestureSample) -> Void
    let onEnd: @MainActor () -> Void

    @State private var isTracking = false
    @State private var rejectedBeginning = false
    @State private var previousPoint: SIMD2<Double>?
    @State private var previousTime: TimeInterval?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture(in: geometry.size))
        }
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Canvas Lead")
        .accessibilityValue(
            isEnabled
                ? "Touch performance available"
                : "Touch performance unavailable"
        )
        .accessibilityIdentifier("dayObjects.leadSurface")
        .onChange(of: isEnabled) { wasEnabled, enabled in
            if wasEnabled && !enabled { cancelGesture() }
        }
        .onDisappear { cancelGesture() }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let now = Date.timeIntervalSinceReferenceDate
                let point = normalized(value.location, in: size)
                if !isTracking && !rejectedBeginning {
                    guard Self.allowsGestureBeginning(
                        at: point,
                        isEnabled: isEnabled,
                        uiExclusionRegion: uiExclusionRegion
                    ) else {
                        rejectedBeginning = true
                        return
                    }
                    isTracking = true
                    previousPoint = point
                    previousTime = now
                    _ = Self.forwardGestureBeginning(
                        sample(point: point, speed: 0),
                        isEnabled: isEnabled,
                        uiExclusionRegion: uiExclusionRegion,
                        onBegin: onBegin
                    )
                    return
                }
                guard isTracking else { return }
                let speed = normalizedSpeed(to: point, at: now)
                previousPoint = point
                previousTime = now
                onUpdate(sample(point: point, speed: speed))
            }
            .onEnded { _ in
                finishGesture()
            }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> SIMD2<Double> {
        let width = max(Double(size.width), 1)
        let height = max(Double(size.height), 1)
        return SIMD2(
            min(max(Double(location.x) / width, 0), 1),
            min(max(Double(location.y) / height, 0), 1)
        )
    }

    private func normalizedSpeed(to point: SIMD2<Double>, at now: TimeInterval) -> Double {
        guard let previousPoint, let previousTime else { return 0 }
        let elapsed = max(now - previousTime, 1.0 / 240)
        let delta = point - previousPoint
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
        let speed = distance / elapsed
        return speed.isFinite ? max(speed, 0) : 0
    }

    private func sample(point: SIMD2<Double>, speed: Double) -> LeadGestureSample {
        .init(normalizedX: point.x, normalizedY: point.y, speed: speed)
    }

    private func finishGesture() {
        if isTracking { onEnd() }
        resetTracking()
    }

    private func cancelGesture() {
        if isTracking { onEnd() }
        resetTracking()
    }

    private func resetTracking() {
        isTracking = false
        rejectedBeginning = false
        previousPoint = nil
        previousTime = nil
    }

    static func allowsGestureBeginning(
        at point: SIMD2<Double>,
        isEnabled: Bool,
        uiExclusionRegion: DayObjectNormalizedRect?
    ) -> Bool {
        isEnabled && !(uiExclusionRegion?.contains(point) ?? false)
    }

    @discardableResult
    static func forwardGestureBeginning(
        _ sample: LeadGestureSample,
        isEnabled: Bool,
        uiExclusionRegion: DayObjectNormalizedRect?,
        onBegin: (LeadGestureSample) -> Void
    ) -> Bool {
        let point = SIMD2(sample.normalizedX, sample.normalizedY)
        guard allowsGestureBeginning(
            at: point,
            isEnabled: isEnabled,
            uiExclusionRegion: uiExclusionRegion
        ) else { return false }
        onBegin(sample)
        return true
    }
}
#endif
