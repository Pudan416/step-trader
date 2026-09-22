import SwiftUI

/// Full-screen viewing actions. Closing is independent of the audio engine state.
struct CanvasFullScreenDock<Share: View>: View {
    @Environment(\.canvasChromePalette) private var palette
    let onClose: () -> Void
    let onRemix: () -> Void
    @ViewBuilder let share: () -> Share

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.geist(size: 20, weight: .regular))
                    .foregroundStyle(palette.textColor)
                    .frame(width: 56, height: 56)
                    .canvasChromeSurface(in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close"))
            .accessibilityHint(String(localized: "Stops the day's music and closes full screen"))
            .accessibilityIdentifier("canvas_close_fullscreen_button")

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                share()
                    .accessibilityIdentifier("canvas_fullscreen_share_button")
                Button(action: onRemix) {
                    Label(String(localized: "Remix"), systemImage: "shuffle")
                        .font(.geist(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 56)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("canvas_remix_button")
            }
            .padding(.horizontal, 4)
            .canvasChromeSurface(in: Capsule())
        }
        .frame(maxWidth: 360)
    }
}

enum CanvasFullScreenRemixPresentation {
    static func isVisible(in state: CanvasPresentationState) -> Bool {
        state == .fullScreen
    }
}

struct CanvasMusicInfoOverlay: View {
    @Environment(\.canvasChromePalette) private var palette
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text(String(localized: "About the music"))
                        .font(.geist(size: 22, weight: .semibold))
                        .foregroundStyle(palette.textColor)

                    Spacer(minLength: 16)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.geist(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textColor.opacity(0.78))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close"))
                    .accessibilityIdentifier("canvas_music_info_close_button")
                }

                Text(String(localized: "I love music, though I never became a musician. So I made this little instrument. I often play it while I work or think."))
                    .font(.geist(.body))
                    .foregroundStyle(palette.textColor.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)

                Text(String(localized: "Sleep shapes the harmony. Activity shapes the rhythm. Happenings add bright, unexpected moments."))
                    .font(.geist(.body).weight(.medium))
                    .foregroundStyle(palette.textColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text("— Kosta")
                    .font(.geist(.subheadline))
                    .foregroundStyle(palette.textColor.opacity(0.68))
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("canvas_music_info_card")
        }
    }
}
