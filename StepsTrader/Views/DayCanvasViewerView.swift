import SwiftUI
import UIKit

// MARK: - Day Canvas Viewer
/// Full-screen viewer for a past day's canvas. Renders the **persisted** canvas
/// (loaded from disk, with Supabase fallback) at the canvas's frozen time so the
/// composition is pixel-identical to what the user saw on that date.
///
/// Behavior:
/// - Tap canvas → toggle immersive mode (hide top bar + bottom card)
/// - Swipe down on bottom card → dismiss
/// - Share button → ImageRenderer export, presented via `CanvasShareSheet`
/// - Long-press canvas → context menu (Save to Photos / Share)
struct DayCanvasViewerView: View {
    @ObservedObject var model: AppModel
    let dayKey: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    @State private var dayCanvas: DayCanvas?
    @State private var snapshot: PastDaySnapshot?
    @State private var isLoading = true
    @State private var isImmersive = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false
    @State private var posterStyle: PosterStyle = .museum

    private var canvasIsEmpty: Bool {
        guard let dc = dayCanvas else { return true }
        return dc.elements.isEmpty
    }

    private var fixedTime: Date {
        if let modified = dayCanvas?.lastModified { return modified }
        return Self.endOfDay(for: dayKey)
    }

    private var displayDate: Date {
        CachedFormatters.dayKey.date(from: dayKey) ?? Date()
    }

    var body: some View {
        ZStack {
            backgroundLayer
            canvasLayer
            overlayLayer
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .preferredColorScheme(theme.colorScheme)
        .task { await load() }
        .sheet(isPresented: $showShareSheet, onDismiss: { shareImage = nil }) {
            if let image = shareImage {
                CanvasShareSheet(items: [image])
            }
        }
    }

    // MARK: - Layers

    private var backgroundLayer: some View {
        theme.backgroundColor
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var canvasLayer: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(theme.adaptivePrimaryText)
        } else if let dc = dayCanvas, !dc.elements.isEmpty {
            GeometryReader { geo in
                let frameSize = GenerativeCanvasView.framedCanvasSize
                let fitScale = min(
                    geo.size.width / frameSize.width,
                    geo.size.height / frameSize.height
                )
                let displayWidth = frameSize.width * fitScale
                let displayHeight = frameSize.height * fitScale

                CanvasPosterView(
                    style: posterStyle,
                    date: displayDate,
                    userName: AuthenticationService.shared.currentUser?.displayName,
                    steps: snapshot?.steps,
                    sleepHours: snapshot?.sleepHours,
                    inkEarned: snapshot?.inkEarned,
                    inkSpent: snapshot?.inkSpent
                ) {
                    canvasContent(dc)
                }
                .frame(width: frameSize.width, height: frameSize.height)
                .scaleEffect(fitScale)
                .frame(width: displayWidth, height: displayHeight)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isImmersive.toggle()
                    }
                }
                .contextMenu {
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        Label(String(localized: "Save to Photos", comment: "DayCanvasViewer – context menu"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        Task { await prepareAndShare() }
                    } label: {
                        Label(String(localized: "Share", comment: "DayCanvasViewer – context menu"), systemImage: "square.and.arrow.up")
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: posterStyle)
            }
            .ignoresSafeArea()
        } else {
            emptyCanvasPlaceholder
        }
    }

    private var emptyCanvasPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(theme.adaptiveMutedText)
            Text(String(localized: "This day was uncolored.", comment: "DayCanvasViewer – empty state"))
                .font(.systemSerif(20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(theme.adaptiveMutedText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlayLayer: some View {
        VStack {
            if !isImmersive { topBar }
            Spacer()
            if !isImmersive { posterStylePicker.padding(.bottom, 24) }
        }
        .animation(.easeInOut(duration: 0.35), value: isImmersive)
    }

    // MARK: - Canvas Content (shared between viewer & export)

    @ViewBuilder
    private func canvasContent(_ dc: DayCanvas, isOffscreenRender: Bool = false) -> some View {
        ZStack {
            EnergyGradientBackground(
                stepsPoints: dc.stepsPoints,
                sleepPoints: dc.sleepPoints,
                hasStepsData: dc.stepsPoints > 0,
                hasSleepData: dc.sleepPoints > 0,
                showGrain: true,
                gradientStyleOverride: dc.gradientStyle,
                gradientPaletteOverride: dc.gradientPalette,
                textureOverride: dc.textureRaw
            )

            GenerativeCanvasView(
                elements: dc.elements,
                sleepPoints: dc.sleepPoints,
                stepsPoints: dc.stepsPoints,
                sleepColor: Color(hex: dc.sleepColorHex),
                stepsColor: Color(hex: dc.stepsColorHex),
                decayNorm: dc.decayNorm,
                backgroundColor: .clear,
                labelColor: theme.textPrimary,
                showLabelsOnCanvas: true,
                showsOutlinedLabels: false,
                showsBackgroundGradient: false,
                hasStepsData: dc.stepsPoints > 0,
                hasSleepData: dc.sleepPoints > 0,
                fixedTime: fixedTime,
                isOffscreenRender: isOffscreenRender
            )
        }
    }

    // MARK: - Poster Style Picker

    private var posterStylePicker: some View {
        HStack(spacing: 10) {
            ForEach(PosterStyle.allCases) { style in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        posterStyle = style
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: style.iconName)
                            .font(.system(size: 12, weight: .medium))
                        Text(style.displayName)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(posterStyle == style ? .white : theme.adaptivePrimaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(posterStyle == style
                            ? AnyShapeStyle(AppColors.brandAccent)
                            : AnyShapeStyle(.ultraThinMaterial))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close", comment: "DayCanvasViewer – close VoiceOver"))

            Spacer()

            if !canvasIsEmpty {
                Button {
                    Task { await prepareAndShare() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(theme.adaptivePrimaryText)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Share canvas", comment: "DayCanvasViewer – share VoiceOver"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        snapshot = model.loadPastDaySnapshots()[dayKey]

        let key = dayKey
        let local = await Task.detached(priority: .userInitiated) {
            CanvasStorageService.shared.loadCanvas(for: key)
        }.value

        if let local {
            dayCanvas = local
        } else if let remote = await SupabaseSyncService.shared.fetchDayCanvas(for: key) {
            dayCanvas = remote
            CanvasStorageService.shared.saveCanvas(remote)
        }

        isLoading = false
    }

    // MARK: - Sharing

    @MainActor
    private func prepareAndShare() async {
        guard let image = renderShareableImage() else { return }
        shareImage = image
        showShareSheet = true
    }

    @MainActor
    private func saveToPhotos() async {
        guard let image = renderShareableImage() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }

    @MainActor
    private func renderShareableImage() -> UIImage? {
        guard let dc = dayCanvas, !dc.elements.isEmpty else { return nil }

        let userName = AuthenticationService.shared.currentUser?.displayName

        // 9:16 output (1080×1920) so the image fits Stories, Reels, and Posts
        let outputW: CGFloat = 1080
        let outputH: CGFloat = 1920
        let posterAspect = posterStyle.nativeAspect
        // Fit poster inside with horizontal margins
        let posterW = outputW * 0.92
        let posterH = posterW / posterAspect

        let shareable = ZStack {
            posterStyle.padColor

            CanvasPosterView(
                style: posterStyle,
                date: displayDate,
                userName: userName,
                steps: snapshot?.steps,
                sleepHours: snapshot?.sleepHours,
                inkEarned: snapshot?.inkEarned,
                inkSpent: snapshot?.inkSpent
            ) {
                canvasContent(dc, isOffscreenRender: true)
            }
            .frame(width: posterW, height: posterH)
        }
        .frame(width: outputW, height: outputH)
        .environment(\.appTheme, theme)

        let renderer = ImageRenderer(content: shareable)
        renderer.scale = 1.0
        renderer.proposedSize = .init(width: outputW, height: outputH)
        return renderer.uiImage
    }

    // MARK: - Helpers

    static func endOfDay(for dayKey: String) -> Date {
        let date = CachedFormatters.dayKey.date(from: dayKey) ?? Date()
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
    }
}

#Preview {
    DayCanvasViewerView(
        model: DIContainer.shared.makeAppModel(),
        dayKey: AppModel.dayKey(for: Date())
    )
}
