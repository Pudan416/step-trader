import SwiftUI

/// A brief launch presentation over the live root, which can prepare underneath.
/// State belongs to the window root, so tab changes and foregrounding do not replay it.
struct NowhereLaunchPresentation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPresented = !ProcessInfo.processInfo.arguments.contains("ui-testing")
    @State private var wordmarkOpacity = 0.0
    @State private var gradientProgress = 0.0
    @State private var coverOpacity = 1.0

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    NowhereLaunchView(
                        wordmarkOpacity: wordmarkOpacity,
                        gradientProgress: gradientProgress
                    )
                    .opacity(coverOpacity)
                    .transition(.identity)
                    .statusBarHidden(true)
                    .task { await present() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Never leave a launch cover waiting over a resumed app.
                if phase == .background { isPresented = false }
            }
    }

    @MainActor
    private func present() async {
        do {
            if reduceMotion {
                wordmarkOpacity = 1
                gradientProgress = 1
                try await Task.sleep(for: .milliseconds(350))
            } else {
                try await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.22)) { wordmarkOpacity = 1 }
                try await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeInOut(duration: 0.65)) { gradientProgress = 1 }
                try await Task.sleep(for: .milliseconds(800))
            }
            withAnimation(.easeOut(duration: 0.2)) { coverOpacity = 0 }
            try await Task.sleep(for: .milliseconds(200))
            isPresented = false
        } catch {
            // Cancellation (including backgrounding) must not strand the cover.
            isPresented = false
        }
    }
}

struct NowhereLaunchView: View {
    var wordmarkOpacity: Double
    var gradientProgress: Double

    private var wordmark: some View {
        Text(verbatim: "NOWHERE")
            .font(.nowhereDisplay(48))
            .tracking(1)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }

    var body: some View {
        ZStack {
            Color.black
            wordmark
                .foregroundStyle(.white)
                .overlay {
                    // Read the existing daily backdrop palette. This observes
                    // ready colors only; it never requests a canvas snapshot.
                    TodayCanvasUnlockFill(darkToLight: true)
                        .mask(wordmark)
                        .mask(alignment: .leading) {
                            GeometryReader { geometry in
                                Rectangle()
                                    .frame(width: geometry.size.width * gradientProgress)
                            }
                        }
                }
                .opacity(wordmarkOpacity)
                .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("NOWHERE")
    }
}

#Preview("Launch · gradient") {
    NowhereLaunchView(wordmarkOpacity: 1, gradientProgress: 1)
}
