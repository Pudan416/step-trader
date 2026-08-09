import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One app icon. Registry apps get our bundled asset with full styling control;
/// everything else gets the system-drawn `Label(token)`, which the system renders
/// in its own process and which cannot be recoloured, masked, or reshaped.
struct FeedIconView: View {
    let source: FeedIconSource
    let size: CGFloat
    #if canImport(FamilyControls)
    var token: ApplicationToken? = nil
    #endif

    var body: some View {
        switch source {
        case .asset(let imageName):
            assetIcon(imageName)
        case .systemLabel:
            systemIcon
        }
    }

    private func assetIcon(_ imageName: String) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder
    private var systemIcon: some View {
        #if canImport(FamilyControls)
        if let token {
            // Drawn out-of-process. Do not attempt to style it — masks and tints
            // are silently ignored, and clipping it produces a blank square.
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: size, height: size)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.42, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
    }
}
