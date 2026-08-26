import SwiftUI

struct RichCanvasLabSession: Equatable {
    private(set) var shuffleNonce = 0

    mutating func shuffle() {
        shuffleNonce &+= 1
    }
}

enum RichCanvasLabSnapshot {
    static func load(
        dayKey: String,
        loader: (String) -> DayCanvas?
    ) -> DayCanvas? {
        loader(dayKey)
    }
}

struct RichCanvasLabView: View {
    @ObservedObject var model: AppModel
    let loadCanvas: (String) -> DayCanvas?

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme
    @State private var canvas: DayCanvas?
    @State private var session = RichCanvasLabSession()
    @State private var lightHapticTick = 0

    init(
        model: AppModel,
        loadCanvas: @escaping (String) -> DayCanvas? = {
            CanvasStorageService.shared.loadCanvas(for: $0)
        }
    ) {
        self.model = model
        self.loadCanvas = loadCanvas
    }

    private var canvasIsEmpty: Bool {
        canvas?.elements.isEmpty != false
    }

    var body: some View {
        ZStack {
            if let canvas, !canvas.elements.isEmpty {
                RichCanvasView(
                    canvas: canvas,
                    shuffleNonce: session.shuffleNonce
                )
            } else {
                ContentUnavailableView(
                    "No canvas yet",
                    systemImage: "sparkles",
                    description: Text("Add happenings to today's canvas first.")
                )
            }

            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
        .sensoryFeedback(.impact(weight: .light), trigger: lightHapticTick)
        .task {
            canvas = RichCanvasLabSnapshot.load(
                dayKey: AppModel.dayKey(for: .now),
                loader: loadCanvas
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            DetailHeader(title: "Rich Canvas")
                .padding(.horizontal, 16)

            Spacer()

            Button {
                session.shuffle()
                lightHapticTick &+= 1
            } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.geist(.subheadline).weight(.semibold))
                    .foregroundStyle(AppAccentInk.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
            .buttonStyle(MattePressStyle())
            .disabled(canvasIsEmpty)
            .opacity(canvasIsEmpty ? 0.45 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
