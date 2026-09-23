import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Native app icon from the selected Screen Time token.
struct FeedIconView: View {
    let source: FeedIconSource
    let size: CGFloat
    #if canImport(FamilyControls)
    var token: ApplicationToken? = nil
    #endif

    var body: some View { systemIcon }

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
                    .font(.geist(size: size * 0.42, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
    }
}
