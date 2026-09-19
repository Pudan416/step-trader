import SwiftUI

enum CanvasExportRoute: Equatable {
    case legacySwiftUI
    case editorialMetal

    init(canvas: DayCanvas) {
        self = canvas.resolvedVisualStyle == .editorial
            ? .editorialMetal
            : .legacySwiftUI
    }
}

struct DayCanvasArtworkLayerPolicy: Equatable {
    enum AnimationSnapshotSource: Equatable {
        case legacySwiftUI
        case editorialMetal
    }

    let usesEditorial: Bool
    let usesLegacyBackground: Bool
    let usesRasterTexture: Bool
    let usesInteractiveAnimationOverlay: Bool
    let animationSnapshotSource: AnimationSnapshotSource

    init(style: CanvasVisualStyle) {
        usesEditorial = style == .editorial
        usesLegacyBackground = style == .legacy
        usesRasterTexture = style == .legacy
        usesInteractiveAnimationOverlay = true
        animationSnapshotSource = .legacySwiftUI
    }
}

/// Constructs exactly one renderer branch. Keeping Legacy in a lazy closure is
/// important: its animated background, overlay, and raster texture must not be
/// allocated underneath the Editorial Metal canvas.
struct DayCanvasArtworkView<LegacyArtwork: View>: View {
    let style: CanvasVisualStyle
    let editorial: EditorialCanvasRenderInput
    let isAnimating: Bool
    let soundPulseBus: DayObjectsSoundPulseBus?
    let presentationMode: DayObjectsPresentationMode
    private let legacyArtwork: () -> LegacyArtwork

    init(
        style: CanvasVisualStyle,
        editorial: EditorialCanvasRenderInput,
        isAnimating: Bool,
        soundPulseBus: DayObjectsSoundPulseBus? = nil,
        presentationMode: DayObjectsPresentationMode = .canvas,
        @ViewBuilder legacyArtwork: @escaping () -> LegacyArtwork
    ) {
        self.style = style
        self.editorial = editorial
        self.isAnimating = isAnimating
        self.soundPulseBus = soundPulseBus
        self.presentationMode = presentationMode
        self.legacyArtwork = legacyArtwork
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .editorial:
            DayObjectsView(
                sceneInput: editorial.sceneInput,
                digitalImpact: editorial.digitalImpact,
                isAnimating: isAnimating,
                soundPulseBus: soundPulseBus,
                presentationMode: presentationMode
            )
        case .legacy:
            legacyArtwork()
        }
    }
}
