import SwiftUI
import UIKit

enum RichParticleDistribution {
    static func counts(
        eligibleIDs: [UUID],
        globalParticleCount: Int
    ) -> [UUID: Int] {
        guard !eligibleIDs.isEmpty, globalParticleCount > 0 else { return [:] }

        let quotient = globalParticleCount / eligibleIDs.count
        let remainder = globalParticleCount % eligibleIDs.count
        return Dictionary(uniqueKeysWithValues: eligibleIDs.enumerated().map { index, id in
            (id, quotient + (index < remainder ? 1 : 0))
        })
    }
}

struct RichDetailTierDistribution: Equatable {
    let accent: Int
    let medium: Int
    let large: Int

    init(accent: Int, medium: Int, large: Int) {
        self.accent = accent
        self.medium = medium
        self.large = large
    }

    init(items: [RichFigurePreviewItem]) {
        self.init(
            accent: items.filter { $0.style.detailTier == .accent }.count,
            medium: items.filter { $0.style.detailTier == .medium }.count,
            large: items.filter { $0.style.detailTier == .large }.count
        )
    }

    var compactDescription: String {
        "\(accent)A · \(medium)M · \(large)L"
    }
}

struct RichCanvasView: View {
    let canvas: DayCanvas
    let shuffleNonce: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderingIsActive) private var renderingIsActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var cache = RichRenderCache()
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var shouldAnimate: Bool {
        RenderingActivity.shouldAnimate(
            isViewActive: renderingIsActive,
            sceneIsActive: scenePhase == .active,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        let budget = RichRenderBudget.resolve(
            elementCount: canvas.elements.count,
            lowPowerMode: lowPowerMode
        )
        let items = RichFigureAssignment.previewItems(
            elements: canvas.elements,
            dayKey: canvas.dayKey,
            shuffleNonce: shuffleNonce
        )

        ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw
            )

            Color.black
                .opacity(0.22)
                .allowsHitTesting(false)

            richTimeline(items: items, budget: budget)

            RichCanvasHUD(
                cache: cache,
                budget: budget,
                items: items,
                lowPowerMode: lowPowerMode
            )
        }
        .clipped()
        .onAppear {
            cache.beginCadenceSession(requestedFPS: budget.requestedFPS)
        }
        .onChange(of: shouldAnimate) { _, _ in
            cache.beginCadenceSession(requestedFPS: budget.requestedFPS)
        }
        .onChange(of: budget.requestedFPS) { _, requestedFPS in
            cache.beginCadenceSession(requestedFPS: requestedFPS)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didReceiveMemoryWarningNotification
            )
        ) { _ in
            cache.removeAllGeometry()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name.NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func richTimeline(
        items: [RichFigurePreviewItem],
        budget: RichRenderBudget
    ) -> some View {
        let eligibleIDs = items.filter(\.style.particleEligible).map(\.id)
        let particleCounts = RichParticleDistribution.counts(
            eligibleIDs: eligibleIDs,
            globalParticleCount: budget.globalParticleCount
        )
        let canonicalTime = reduceMotionCanonicalTime

        return TimelineView(.animation(
            minimumInterval: 1 / Double(max(1, budget.requestedFPS)),
            paused: !shouldAnimate
        )) { timeline in
            let liveTime = timeline.date.timeIntervalSinceReferenceDate
            let renderTime = reduceMotion ? canonicalTime : liveTime

            Canvas(
                opaque: false,
                colorMode: .linear,
                rendersAsynchronously: false
            ) { context, size in
                if shouldAnimate {
                    cache.recordFrame(
                        time: liveTime,
                        requestedFPS: budget.requestedFPS
                    )
                }

                for item in items {
                    RichFigureRenderer.draw(
                        item: item,
                        context: &context,
                        canvasSize: size,
                        time: renderTime,
                        budget: budget,
                        particleCount: particleCounts[item.id, default: 0],
                        reduceMotion: reduceMotion,
                        cache: cache
                    )
                }

                // Labels are a separate foreground pass so later figures never
                // paint over text belonging to an earlier element.
                let labelCandidates = items.map { item in
                    let motion = RichFigureRenderer.motionState(
                        for: item,
                        canvasSize: size,
                        time: renderTime,
                        reduceMotion: reduceMotion
                    )
                    let envelope = RichFigureLayout.edgeSafeEnvelope(
                        for: item.layout,
                        canvasSize: size
                    )
                    let labelCenter = RichFigureLayout.labelCenter(
                        figureCenter: motion.center,
                        contentRadius: envelope.effectiveTargetDiameter
                            * item.layout.opticalScale * 0.5,
                        canvasSize: size
                    )
                    return RichFigureLabelCandidate(
                        id: item.id,
                        preferredCenter: labelCenter,
                        estimatedWidth: min(
                            156,
                            max(36, CGFloat(item.source.displayLabel.count) * 6 + 12)
                        )
                    )
                }
                let labelCenters = RichFigureLayout.resolvedLabelCenters(
                    candidates: labelCandidates,
                    canvasSize: size
                )
                for item in items {
                    guard let labelCenter = labelCenters[item.id] else { continue }
                    drawLabel(
                        item.source.displayLabel,
                        at: labelCenter,
                        context: &context
                    )
                }
            }
        }
    }

    private var reduceMotionCanonicalTime: Double {
        let seed = CanvasElement.makeSeed(
            optionId: "rich-reduce-motion-\(shuffleNonce)",
            dayKey: canvas.dayKey,
            index: canvas.elements.count
        )
        return Double(seed % 120_000) / 1_000
    }

    private func drawLabel(
        _ label: String,
        at center: CGPoint,
        context: inout GraphicsContext
    ) {
        let foreground: Color = context.environment.colorScheme == .dark
            ? .white
            : .black
        let outline: Color = context.environment.colorScheme == .dark
            ? .black
            : .white
        let font: Font = .system(size: 11, weight: .regular, design: .rounded)
        let outlineText = Text(label).font(font).foregroundStyle(outline)

        context.drawLayer { layer in
            layer.opacity = 0.45
            for offset in [
                CGSize(width: -1, height: -1),
                CGSize(width: 1, height: -1),
                CGSize(width: -1, height: 1),
                CGSize(width: 1, height: 1)
            ] {
                layer.draw(
                    outlineText,
                    at: CGPoint(
                        x: center.x + offset.width,
                        y: center.y + offset.height
                    ),
                    anchor: .center
                )
            }
        }
        context.draw(
            Text(label).font(font).foregroundStyle(foreground.opacity(0.9)),
            at: center,
            anchor: .center
        )
    }
}

struct RichCanvasHUD: View {
    let cache: RichRenderCache
    let budget: RichRenderBudget
    let items: [RichFigurePreviewItem]
    let lowPowerMode: Bool
    @State private var isExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let stats = cache.cadenceSnapshot()
            let detailTiers = RichDetailTierDistribution(items: items)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Group {
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                "\(String(format: "%.1f", stats.observedFPS)) FPS · "
                                + "\(items.count) items · \(detailTiers.compactDescription) · "
                                + (lowPowerMode ? "Low Power" : "Normal")
                            )
                            Text(
                                "target: \(budget.requestedFPS) · contours: \(budget.contourCount) · "
                                + "rings: \(budget.orbitalRingCount)"
                            )
                            Text(
                                "filaments: \(budget.filamentCount) · "
                                + "particles: \(budget.globalParticleCount) · "
                                + "glows: \(budget.glowPassCount) · "
                                + "slow: \(stats.slowIntervalCount)"
                            )
                        }
                    } else {
                        Label(
                            "\(Int(stats.observedFPS.rounded())) FPS",
                            systemImage: "waveform.path.ecg"
                        )
                    }
                }
                .font(.geist(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(12)
            .padding(.top, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

#Preview("Rich Canvas Lab") {
    RichCanvasView(canvas: .richCanvasPreview, shuffleNonce: 0)
        .frame(width: 390, height: 844)
        .environment(\.renderingIsActive, true)
}

private extension DayCanvas {
    static var richCanvasPreview: DayCanvas {
        let colors = [
            "#FFB703", "#FB8500", "#E63946", "#9B5DE5", "#00B4D8",
            "#2A9D8F", "#90BE6D", "#F9C74F", "#F15BB5", "#4361EE"
        ]
        var canvas = DayCanvas(dayKey: "2026-08-16")
        canvas.stepsPoints = 16
        canvas.sleepPoints = 13
        canvas.hasStepsData = true
        canvas.hasSleepData = true
        canvas.gradientStyle = GradientStyle.mesh.rawValue
        canvas.gradientPalette = GradientPalette.ember.rawValue
        canvas.textureRaw = CanvasTexture.grainSmall.rawValue
        canvas.elements = (0..<10).map { index in
            let column = index % 4
            let row = index / 4
            return CanvasElement(
                id: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        index + 1
                    )
                )!,
                kind: index.isMultiple(of: 2) ? .circle : .ray,
                optionId: "preview-\(index)",
                label: [
                    "Walk", "Read", "Focus", "Run", "Rest",
                    "Create", "Swim", "Learn", "Cycle", "Breathe"
                ][index],
                hexColor: colors[index],
                hexColor2: colors[(index + 3) % colors.count],
                size: 0.16 + CGFloat(index) * 0.014,
                basePosition: CGPoint(
                    x: 0.18 + CGFloat(column) * 0.21,
                    y: 0.20 + CGFloat(row) * 0.30
                ),
                phaseOffset: Double(index) * 0.57,
                driftSpeed: 0.10 + Double(index) * 0.006,
                driftAmplitude: 0.02,
                pulseFrequency: 0.2,
                pulseAmplitude: 0.02,
                rotationSpeed: 5,
                opacity: 0.7,
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index)),
                shapeSeed: UInt64(index + 1)
            )
        }
        return canvas
    }
}
