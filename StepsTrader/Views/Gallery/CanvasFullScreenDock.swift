import SwiftUI

/// Three viewing actions. Closing is independent of the audio engine state.
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

struct CanvasFullScreenSoundControlPresentation: Equatable {
    let title: String
    let systemImage: String
    let isEnabled: Bool

    init(appearance: CanvasSoundButtonAppearance) {
        switch appearance {
        case .readyToPlay:
            self.init(title: "Play", systemImage: "play.fill", isEnabled: true)
        case .starting:
            self.init(title: "Starting sound", systemImage: "hourglass", isEnabled: false)
        case .playing:
            self.init(title: "Sound off", systemImage: "speaker.slash.fill", isEnabled: true)
        case .retry:
            self.init(title: "Retry sound", systemImage: "arrow.clockwise", isEnabled: true)
        }
    }

    init(title: String, systemImage: String, isEnabled: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
    }
}

enum CanvasFullScreenSoundAction: Equatable {
    case retryInPlace
    case turnOffAndExit
    case none

    static func resolve(appearance: CanvasSoundButtonAppearance) -> Self {
        switch appearance {
        case .readyToPlay, .retry: .retryInPlace
        case .playing: .turnOffAndExit
        case .starting: .none
        }
    }
}
