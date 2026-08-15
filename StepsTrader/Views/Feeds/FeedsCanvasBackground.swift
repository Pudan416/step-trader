import SwiftUI

/// The user's canvas, blurred, as the whole Feeds page's background.
///
/// It is the page's background rather than a card's: the reference has no
/// container at all, the artwork runs edge to edge behind the dock and the tab
/// bar, and that full bleed is the point — the canvas is what distinguishes
/// Nowhere from any other blocker.
///
/// Two deliberate choices. `fixedTime` freezes the render to a single frame,
/// because the live view animates continuously and under an 18pt blur that
/// motion is invisible — it would cost battery to show nobody anything. And
/// there is no dimming scrim: legibility is bought with shadows on the text
/// that needs it, not by throwing a curtain over the artwork.
struct FeedsCanvasBackground: View {
    @State private var dayCanvas = DayCanvas(dayKey: AppModel.dayKey(for: .now))
    @State private var hasLoaded = false
    @State private var fixedTime = Date.now

    var body: some View {
        GenerativeCanvasView(
            elements: dayCanvas.elements,
            dayKey: dayCanvas.dayKey,
            sleepPoints: dayCanvas.sleepPoints,
            stepsPoints: dayCanvas.stepsPoints,
            sleepColor: Color(hex: dayCanvas.sleepColorHex),
            stepsColor: Color(hex: dayCanvas.stepsColorHex),
            decayNorm: dayCanvas.decayNorm,
            backgroundColor: AppColors.Night.background,
            showLabelsOnCanvas: false,
            showsOutlinedLabels: false,
            hasStepsData: dayCanvas.resolvedHasStepsData,
            hasSleepData: dayCanvas.resolvedHasSleepData,
            fixedTime: fixedTime
        )
        .blur(radius: 18)
        // The blur samples past the edges; scaling up hides the transparent
        // fringe a plain blur leaves at the bounds.
        .scaleEffect(1.15)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let key = AppModel.dayKey(for: .now)
        if let loaded = CanvasStorageService.shared.loadCanvas(for: key) {
            dayCanvas = loaded
        }
        fixedTime = .now
    }
}
