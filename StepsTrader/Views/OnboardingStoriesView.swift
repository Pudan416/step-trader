import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import AuthenticationServices
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

// MARK: - Slide Types

enum OnboardingSlideAction: Equatable {
    case none
    case requestHealth
    case requestNotifications
    case requestFamilyControls
}

enum OnboardingSlideType: Equatable {
    case coldOpen
    case theCanvas
    case paintDemo
    case colorCap
    case spendDemo
    case howItWorks
    case stepsSetup
    case sleepSetup
    case text
    case feedSelection
    case nowHereReveal
    case appleLogin
    case welcome
}

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let lines: [String]
    let symbol: String
    let gradient: [Color]
    let action: OnboardingSlideAction
    let slideType: OnboardingSlideType
    let microcopy: String?
    
    init(
        lines: [String],
        symbol: String = "",
        gradient: [Color] = [],
        action: OnboardingSlideAction = .none,
        slideType: OnboardingSlideType = .text,
        microcopy: String? = nil
    ) {
        self.lines = lines
        self.symbol = symbol
        self.gradient = gradient
        self.action = action
        self.slideType = slideType
        self.microcopy = microcopy
    }
}

// MARK: - Onboarding Phases (for progress bar grouping)

private enum OnboardingPhase {
    case story, setup, action
    
    static func phase(for index: Int) -> OnboardingPhase {
        switch index {
        case 0...5: return .story
        case 6...9: return .setup
        default:    return .action
        }
    }
}

// MARK: - Floating Elements

private enum FloaterKind { case body, mind, heart }

private struct OnboardingFloater: Identifiable {
    let id: Int
    let asset: String
    let kind: FloaterKind
    let baseX: CGFloat
    let baseY: CGFloat
    let size: CGFloat
    let phase: Double
    let speed: Double
    let rotation: Double
    let tintColor: Color
    let appearsAtSlide: Int
}

private let interactiveSlideIndices: Set<Int> = [2, 3, 4, 6, 7, 9, 11]

private func generateFloaters(count: Int, totalSlides: Int) -> [OnboardingFloater] {
    let bodyAssets = ["body 1", "body 2", "body 3"]
    let mindAssets = ["mind 1"]
    let heartAssets = ["heart 1"]
    let kinds: [FloaterKind] = [.body, .mind, .heart, .body, .mind, .heart, .body, .mind, .body]
    let tintColors: [Color] = [
        Color(red: 0.3, green: 0.8, blue: 0.5),
        Color(red: 0.4, green: 0.6, blue: 1.0),
        Color(red: 1.0, green: 0.45, blue: 0.55),
        Color(red: 1.0, green: 0.75, blue: 0.3),
        Color(red: 0.6, green: 0.4, blue: 0.9),
        Color(red: 0.9, green: 0.35, blue: 0.4),
        Color(red: 0.3, green: 0.75, blue: 0.85),
        Color(red: 0.85, green: 0.6, blue: 0.3),
        Color(red: 0.5, green: 0.9, blue: 0.6),
    ]
    
    var floaters: [OnboardingFloater] = []
    var seed: UInt64 = 42
    
    let nextRandom: () -> Double = {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
    
    for i in 0..<count {
        let slide = (i % totalSlides) + 1
        let kind = kinds[i % kinds.count]
        let asset: String
        switch kind {
        case .body:  asset = bodyAssets[Int(nextRandom() * Double(bodyAssets.count)) % bodyAssets.count]
        case .mind:  asset = mindAssets[0]
        case .heart: asset = heartAssets[0]
        }
        
        let positions: [(CGFloat, CGFloat)] = [
            (0.15, 0.18), (0.82, 0.35), (0.25, 0.65),
            (0.75, 0.12), (0.50, 0.80), (0.10, 0.42),
            (0.88, 0.60), (0.35, 0.25), (0.65, 0.72),
        ]
        let pos = positions[i % positions.count]
        
        floaters.append(OnboardingFloater(
            id: i,
            asset: asset,
            kind: kind,
            baseX: pos.0,
            baseY: pos.1,
            size: CGFloat(120 + nextRandom() * 140),
            phase: nextRandom() * .pi * 2,
            speed: 0.3 + nextRandom() * 0.5,
            rotation: nextRandom() * .pi * 2,
            tintColor: tintColors[i % tintColors.count],
            appearsAtSlide: slide
        ))
    }
    return floaters.sorted { $0.appearsAtSlide < $1.appearsAtSlide }
}

// MARK: - Main View

struct OnboardingStoriesView: View {
    @Binding var isPresented: Bool
    let slides: [OnboardingSlide]
    let accent: Color
    let skipText: String
    let nextText: String
    let startText: String
    let allowText: String
    let onHealthSlide: (() -> Void)?
    let onNotificationSlide: (() -> Void)?
    let onFamilyControlsSlide: (() -> Void)?
    let onFinish: () -> Void
    
    var model: AppModel?
    @Binding var stepsTarget: Double
    @Binding var sleepTarget: Double
    var authService: AuthenticationService?
    @Binding var onboardingSelection: FamilyActivitySelection
    @Binding var selectedFeedApp: String?
    
    @State private var index: Int = 0
    @State private var showOnboardingPicker = false
    @State private var floaters: [OnboardingFloater] = []
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false
    @State private var didTriggerFamilyControlsRequest = false
    
    // Analytics
    @State private var slideAppearedAt: Date = Date()
    @State private var onboardingStartedAt: Date = Date()
    
    // Cold open
    @State private var coldOpenVisible: Int = 0
    
    // The canvas
    @State private var canvasAppeared = false
    
    // Paint demo
    @State private var paintStrokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var paintDarkPhase = false
    
    // Color cap
    @State private var tappedOrbs: Set<Int> = []
    @State private var ringProgress: Double = 0
    
    // Spend demo
    @State private var demoColorPool: Int = 100
    @State private var unlockedDemoApps: Set<String> = []
    @State private var showMidnightReset = false
    
    // How it works
    @State private var loopPhase: Int = 0
    
    // Now Here reveal
    @State private var revealPhase: Int = 0
    
    // Welcome name animation
    @State private var welcomeNameVisible = false

    var body: some View {
        ZStack {
            Canvas { context, size in
                let progress = slides.isEmpty ? 0 : Double(index) / Double(max(slides.count - 1, 1))
                let pal = EnergyGradientRenderer.palette(for: .warmSunset)
                let opacities = EnergyGradientRenderer.computeOpacities(
                    smoothedS: progress,
                    smoothedL: progress,
                    hasStepsData: progress > 0,
                    hasSleepData: progress > 0,
                    isDaylight: false
                )
                EnergyGradientRenderer.draw(
                    context: &context,
                    size: size,
                    opacities: opacities,
                    baseColor: pal.dark,
                    gradientStyle: .radial,
                    colorPalette: pal
                )
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                Image("onboarding_figuer_1")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .opacity(index == 0 ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.8), value: index)
            }
            .ignoresSafeArea(edges: .bottom)
            
            if !interactiveSlideIndices.contains(index) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    GeometryReader { geo in
                        let visible = floaters.filter { $0.appearsAtSlide <= index }
                        ForEach(visible) { f in
                            floaterView(f: f, t: t, size: geo.size)
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            
            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideContent(slide: slide, slideIndex: idx)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(idx)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .scrollDisabled(true)
                .animation(.easeInOut, value: index)

                Button(action: next) {
                    Text(primaryButtonTitle)
                        .font(.systemSerif(18, weight: .medium, relativeTo: .headline))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            
            GeometryReader { geo in
                Color.clear
                    .frame(width: geo.size.width / 3)
                    .contentShape(Rectangle())
                    .onTapGesture { goBack() }
                    .allowsHitTesting(index > 0)
            }
            
            Image("grain 1")
                .resizable()
                .scaledToFill()
                .blendMode(.overlay)
                .opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let isPaintSlide = slides.indices.contains(index) && slides[index].slideType == .paintDemo
                    if !isPaintSlide, value.translation.width > 60, index > 0 {
                        goBack()
                    }
                }
        )
        .onAppear {
            floaters = generateFloaters(count: 9, totalSlides: slides.count)
            onboardingStartedAt = Date()
            slideAppearedAt = Date()
            trackSlideViewed()
            triggerSlideEntryEffects()
        }
        .onChange(of: index) { _, _ in
            slideAppearedAt = Date()
            trackSlideViewed()
            triggerSlideEntryEffects()
        }
    }

    // MARK: - Back Navigation
    
    private func goBack() {
        guard index > 0 else { return }
        trackSlideCompleted(action: "back")
        withAnimation(.easeInOut) { index -= 1 }
    }

    // MARK: - Analytics
    
    private func trackSlideViewed() {
        guard slides.indices.contains(index) else { return }
        let slideName = String(describing: slides[index].slideType)
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_slide_viewed",
                properties: [
                    "slide_index": String(index),
                    "slide_name": slideName,
                    "flow_version": "v5"
                ]
            )
        }
    }
    
    private func trackSlideCompleted(action: String) {
        guard slides.indices.contains(index) else { return }
        let slideName = String(describing: slides[index].slideType)
        let durationMs = Int(Date().timeIntervalSince(slideAppearedAt) * 1000)
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_slide_completed",
                properties: [
                    "slide_index": String(index),
                    "slide_name": slideName,
                    "flow_version": "v5",
                    "duration_ms": String(durationMs),
                    "action_taken": action
                ]
            )
        }
    }

    // MARK: - Slide Entry Effects
    
    private func triggerSlideEntryEffects() {
        guard slides.indices.contains(index) else { return }
        let slide = slides[index]
        
        switch slide.slideType {
        case .coldOpen:
            coldOpenVisible = 0
            for i in 0..<slide.lines.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8 + 0.5) {
                    withAnimation(.easeIn(duration: 0.6)) { coldOpenVisible = i + 1 }
                }
            }
        case .theCanvas:
            canvasAppeared = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { canvasAppeared = true }
            }
        case .paintDemo:
            paintStrokes = []
            currentStroke = []
            paintDarkPhase = false
        case .colorCap:
            tappedOrbs = []
            ringProgress = 0
        case .spendDemo:
            demoColorPool = 100
            unlockedDemoApps = []
            showMidnightReset = false
        case .howItWorks:
            loopPhase = 0
            for i in 1...4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.5) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { loopPhase = i }
                }
            }
        case .nowHereReveal:
            revealPhase = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeIn(duration: 0.6)) { revealPhase = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.82)) { revealPhase = 2 }
                heavyHaptic()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation(.easeIn(duration: 0.5)) { revealPhase = 3 }
                successHaptic()
            }
        case .welcome:
            welcomeNameVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.5)) { welcomeNameVisible = true }
            }
        default:
            break
        }
    }

    // MARK: - Haptics
    
    private func lightHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    
    private func successHaptic() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func mediumHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    
    private func heavyHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }
    
    private func rigidHaptic() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    // MARK: - Floater Rendering

    private func floaterTransform(f: OnboardingFloater, t: Double, size: CGSize) -> (dx: CGFloat, dy: CGFloat, scale: CGFloat, rot: Double) {
        let w = size.width
        let h = size.height
        switch f.kind {
        case .body:
            let scale = 1.0 + sin(t * (0.7 + f.speed * 0.5) + f.phase) * 0.08
            return (0, 0, scale, f.rotation)
        case .mind:
            let s = 0.03 + f.speed * 0.04
            let dx = sin(t * s + f.phase) * w * 0.15
                + sin(t * s * 2.37 + f.phase * 2.3) * w * 0.06
            let dy = cos(t * s * 0.83 + f.phase * 1.7) * h * 0.12
                + cos(t * s * 1.97 + f.phase * 3.1) * h * 0.05
            let rot = f.rotation + atan2(
                cos(t * s * 0.83 + f.phase * 1.7) * (-s * 0.83),
                cos(t * s + f.phase) * s
            ) + .pi
            return (dx, dy, 1.0, rot)
        case .heart:
            return (0, 0, 1.0, f.rotation)
        }
    }
    
    @ViewBuilder
    private func floaterView(f: OnboardingFloater, t: Double, size: CGSize) -> some View {
        let tr = floaterTransform(f: f, t: t, size: size)
        Image(f.asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: f.size * tr.scale, height: f.size * tr.scale)
            .foregroundColor(f.tintColor)
            .opacity(0.8)
            .rotationEffect(.radians(tr.rot))
            .position(
                x: f.baseX * size.width + tr.dx,
                y: f.baseY * size.height + tr.dy
            )
    }

    // MARK: - Text Helpers

    @ViewBuilder
    private func onboardingLineText(_ line: String, size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> some View {
        Text(line)
            .font(.systemSerif(size, weight: .light, relativeTo: textStyle))
            .foregroundColor(.white.opacity(0.74))
            .multilineTextAlignment(.center)
            .lineSpacing(size >= 20 ? 4 : 3)
            .minimumScaleFactor(0.88)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Progress Bar (3 phases)
    
    private var progressBar: some View {
        HStack(spacing: 2) {
            ForEach(slides.indices, id: \.self) { i in
                let currentPhase = OnboardingPhase.phase(for: i)
                let prevPhase: OnboardingPhase? = i > 0 ? OnboardingPhase.phase(for: i - 1) : nil
                let isNewPhase = prevPhase != nil && prevPhase != currentPhase
                
                if isNewPhase {
                    Spacer().frame(width: 6)
                }
                
                Capsule()
                    .fill(i <= index ? accent : accent.opacity(0.12))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Progress", comment: "Onboarding – progress bar VoiceOver label"))
        .accessibilityValue(String(localized: "Slide \(index + 1) of \(slides.count)", comment: "Onboarding – progress bar VoiceOver value"))
    }

    // MARK: - Slide Router

    @ViewBuilder
    private func slideContent(slide: OnboardingSlide, slideIndex: Int) -> some View {
        switch slide.slideType {
        case .coldOpen:
            coldOpenSlide(slide: slide)
        case .theCanvas:
            theCanvasSlide(slide: slide)
        case .paintDemo:
            paintDemoSlide(slide: slide)
        case .colorCap:
            colorCapSlide(slide: slide)
        case .spendDemo:
            spendDemoSlide(slide: slide)
        case .howItWorks:
            howItWorksSlide(slide: slide)
        case .stepsSetup:
            stepsSetupSlide(slide: slide)
        case .sleepSetup:
            sleepSetupSlide(slide: slide)
        case .text:
            textSlide(slide: slide)
        case .feedSelection:
            feedSelectionSlide(slide: slide)
        case .nowHereReveal:
            nowHereRevealSlide(slide: slide)
        case .appleLogin:
            appleLoginSlide(slide: slide)
        case .welcome:
            welcomeSlide(slide: slide)
        }
    }

    // MARK: - Slide 1: Cold Open

    @ViewBuilder
    private func coldOpenSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()
            
            VStack(spacing: 16) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    if coldOpenVisible > idx {
                        onboardingLineText(line, size: 18, relativeTo: .body)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.horizontal, 44)
            
            Spacer()
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 2: The Canvas

    @ViewBuilder
    private func theCanvasSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 32)
            
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.06, blue: 0.12),
                            Color(red: 0.04, green: 0.04, blue: 0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 200, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(canvasAppeared ? 0.12 : 0), lineWidth: 1)
                )
                .shadow(color: accent.opacity(canvasAppeared ? 0.1 : 0), radius: 30, x: 0, y: 10)
                .scaleEffect(canvasAppeared ? 1 : 0.85)
                .opacity(canvasAppeared ? 1 : 0)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 3: Paint Demo (interactive)

    @ViewBuilder
    private func paintDemoSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
            
            ZStack {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 20),
                        with: .color(Color(red: 0.04, green: 0.04, blue: 0.08))
                    )
                    
                    if paintDarkPhase {
                        let navyGradient = Gradient(colors: [
                            .clear,
                            Color(red: 0, green: 0.15, blue: 0.27).opacity(0.4),
                            Color(red: 0, green: 0.23, blue: 0.42).opacity(0.6),
                        ])
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 20),
                            with: .linearGradient(
                                navyGradient,
                                startPoint: CGPoint(x: size.width / 2, y: 0),
                                endPoint: CGPoint(x: size.width / 2, y: size.height)
                            )
                        )
                    }
                    
                    let goldColor = Color(red: 1, green: 0.83, blue: 0.41)
                    
                    for stroke in paintStrokes {
                        drawStroke(stroke, in: &context, color: goldColor)
                    }
                    if !currentStroke.isEmpty {
                        drawStroke(currentStroke, in: &context, color: goldColor)
                    }
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .overlay(
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    currentStroke.append(value.location)
                                    if currentStroke.count % 6 == 0 { lightHaptic() }
                                }
                                .onEnded { _ in
                                    if !currentStroke.isEmpty {
                                        paintStrokes.append(currentStroke)
                                        currentStroke = []
                                    }
                                    if !paintDarkPhase && paintStrokes.count >= 3 {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            withAnimation(.easeInOut(duration: 1.5)) { paintDarkPhase = true }
                                            mediumHaptic()
                                        }
                                    }
                                }
                        )
                )
                
                if paintStrokes.isEmpty && currentStroke.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 28, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.25))
                        Text(String(localized: "touch and drag"))
                            .font(.systemSerif(13, weight: .light, relativeTo: .caption))
                            .foregroundColor(.white.opacity(0.25))
                    }
                    .allowsHitTesting(false)
                }
            }
            
            if paintDarkPhase {
                onboardingLineText(
                    String(localized: "the light from walking. the dark from rest."),
                    size: 14,
                    relativeTo: .footnote
                )
                .padding(.top, 16)
                .transition(.opacity)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    private func drawStroke(_ points: [CGPoint], in context: inout GraphicsContext, color: Color) {
        guard points.count > 1 else {
            if let p = points.first {
                let rect = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.6)))
            }
            return
        }
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let mid = CGPoint(
                x: (points[i - 1].x + points[i].x) / 2,
                y: (points[i - 1].y + points[i].y) / 2
            )
            path.addQuadCurve(to: mid, control: points[i - 1])
        }
        if let last = points.last {
            path.addLine(to: last)
        }
        context.stroke(path, with: .color(color.opacity(0.65)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 28, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Slide 4: Color Cap (interactive ring)

    private static let colorCategories: [(icon: String, label: String, color: Color)] = [
        ("figure.walk", "steps", Color(red: 1.0, green: 0.83, blue: 0.41)),
        ("bed.double", "sleep", Color(red: 0.35, green: 0.45, blue: 0.75)),
        ("figure.run", "body", Color(red: 0.3, green: 0.8, blue: 0.5)),
        ("brain.head.profile", "mind", Color(red: 0.4, green: 0.6, blue: 1.0)),
        ("heart", "heart", Color(red: 1.0, green: 0.45, blue: 0.55)),
    ]
    
    @ViewBuilder
    private func colorCapSlide(slide: OnboardingSlide) -> some View {
        let categories = Self.colorCategories
        
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 4)
                    .frame(width: 160, height: 160)
                
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: ringProgress)
                
                if !tappedOrbs.isEmpty {
                    Text("\(tappedOrbs.count * 20)")
                        .font(.systemSerif(36, weight: .thin, relativeTo: .largeTitle))
                        .foregroundColor(accent)
                        .contentTransition(.numericText())
                }
                
                ForEach(0..<5, id: \.self) { i in
                    let angle = (Double(i) / 5.0) * .pi * 2 - .pi / 2
                    let radius: CGFloat = 120
                    let x = cos(angle) * radius
                    let y = sin(angle) * radius
                    let isTapped = tappedOrbs.contains(i)
                    
                    Button {
                        guard !isTapped else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            tappedOrbs.insert(i)
                            ringProgress = Double(tappedOrbs.count) / 5.0
                        }
                        if tappedOrbs.count == 5 { successHaptic() } else { lightHaptic() }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: categories[i].icon)
                                .font(.system(size: 18, weight: .light))
                                .foregroundColor(isTapped ? categories[i].color : .white.opacity(0.25))
                            Text(String(localized: "+20"))
                                .font(.systemSerif(10, weight: .light, relativeTo: .caption2))
                                .foregroundColor(isTapped ? categories[i].color.opacity(0.8) : .white.opacity(0.2))
                        }
                        .frame(width: 54, height: 54)
                        .background(
                            Circle()
                                .fill(isTapped ? categories[i].color.opacity(0.12) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            Circle()
                                .stroke(isTapped ? categories[i].color.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .scaleEffect(isTapped ? 1.1 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .offset(x: x, y: y)
                }
            }
            .frame(width: 300, height: 300)
            
            if tappedOrbs.count == 5 {
                onboardingLineText(
                    String(localized: "you can't buy them — only live them."),
                    size: 15,
                    relativeTo: .footnote
                )
                .padding(.top, 8)
                .transition(.opacity)
            }
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 5: Spend Demo (interactive)

    private static let spendDemoApps: [(name: String, imageName: String, cost: Int)] = [
        ("Instagram", "instagram", 40),
        ("TikTok", "tiktok", 40),
        ("YouTube", "youtube", 40),
    ]
    
    @ViewBuilder
    private func spendDemoSlide(slide: OnboardingSlide) -> some View {
        let apps = Self.spendDemoApps
        
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 20)
            
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text("\(demoColorPool)")
                    .font(.systemSerif(28, weight: .thin, relativeTo: .title2))
                    .foregroundColor(accent)
                    .contentTransition(.numericText())
                Text(String(localized: "colors"))
                    .font(.systemSerif(14, weight: .light, relativeTo: .caption))
                    .foregroundColor(.white.opacity(0.35))
            }
            .padding(.bottom, 24)
            
            HStack(spacing: 24) {
                ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                    let isUnlocked = unlockedDemoApps.contains(app.name)
                    let canAfford = demoColorPool >= app.cost
                    
                    Button {
                        guard !isUnlocked, canAfford else {
                            if !canAfford { rigidHaptic() }
                            return
                        }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            demoColorPool -= app.cost
                            unlockedDemoApps.insert(app.name)
                        }
                        mediumHaptic()
                        
                        if demoColorPool < apps.map(\.cost).min()! {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                withAnimation(.easeIn(duration: 0.5)) { showMidnightReset = true }
                            }
                        }
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                Image(app.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                    .opacity(isUnlocked ? 1.0 : 0.35)
                                
                                if !isUnlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                if isUnlocked {
                                    Image(systemName: "lock.open.fill")
                                        .font(.system(size: 16, weight: .light))
                                        .foregroundColor(.green.opacity(0.8))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            
                            Text(isUnlocked
                                 ? String(localized: "open")
                                 : String(localized: "-\(app.cost)"))
                                .font(.systemSerif(12, weight: .light, relativeTo: .caption2))
                                .foregroundColor(isUnlocked ? .green.opacity(0.7) : (canAfford ? accent.opacity(0.7) : .white.opacity(0.2)))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnlocked)
                }
            }
            
            Group {
                if showMidnightReset {
                    onboardingLineText(
                        String(localized: "not enough. comes back at midnight."),
                        size: 14,
                        relativeTo: .footnote
                    )
                } else if unlockedDemoApps.isEmpty {
                    onboardingLineText(
                        String(localized: "tap an app to spend colors."),
                        size: 14,
                        relativeTo: .footnote
                    )
                } else if unlockedDemoApps.count < apps.count && demoColorPool >= (apps.first?.cost ?? 0) {
                    onboardingLineText(
                        String(localized: "tap another."),
                        size: 14,
                        relativeTo: .footnote
                    )
                }
            }
            .padding(.top, 20)
            .animation(.easeInOut, value: showMidnightReset)
            .animation(.easeInOut, value: unlockedDemoApps.count)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 6: How It Works (earn → spend → reset)

    @ViewBuilder
    private func howItWorksSlide(slide: OnboardingSlide) -> some View {
        let steps: [(icon: String, label: String)] = [
            ("figure.walk", String(localized: "earn")),
            ("lock.open", String(localized: "spend")),
            ("moon.fill", String(localized: "reset")),
        ]
        
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            HStack(spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    let visible = loopPhase > i
                    
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 64, height: 64)
                            Image(systemName: step.icon)
                                .font(.system(size: 22, weight: .ultraLight))
                                .foregroundColor(visible ? accent : .white.opacity(0.15))
                        }
                        Text(step.label)
                            .font(.systemSerif(13, weight: .light, relativeTo: .caption))
                            .foregroundColor(visible ? .white.opacity(0.6) : .white.opacity(0.15))
                    }
                    .opacity(visible ? 1 : 0.3)
                    .scaleEffect(visible ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: visible)
                    
                    if i < steps.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .ultraLight))
                            .foregroundColor(.white.opacity(loopPhase > i ? 0.25 : 0.08))
                    }
                }
            }
            
            if loopPhase >= 4 {
                onboardingLineText(
                    String(localized: "at midnight, it resets."),
                    size: 15,
                    relativeTo: .footnote
                )
                .padding(.top, 24)
                .transition(.opacity)
            }
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 7: Steps Setup
    
    @ViewBuilder
    private func stepsSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            Text(formatGroupedNumber(Int(stepsTarget)))
                .font(.systemSerif(60, weight: .thin, relativeTo: .largeTitle))
                .foregroundColor(accent)
                .contentTransition(.numericText())
            
            Text(String(localized: "steps", comment: "Onboarding – steps unit label"))
                .font(.systemSerif(16, weight: .light, relativeTo: .subheadline))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 28)
            
            VStack(spacing: 8) {
                Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                    .tint(accent)
                    .padding(.horizontal, 40)
                    .onChange(of: stepsTarget) { _, _ in lightHaptic() }
                
                HStack {
                    Text(String(localized: "5,000", comment: "Onboarding – steps slider minimum"))
                    Spacer()
                    Text(String(localized: "15,000", comment: "Onboarding – steps slider maximum"))
                }
                .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 44)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Slide 8: Sleep Setup
    
    @ViewBuilder
    private func sleepSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            Text(String(format: "%.1f", sleepTarget))
                .font(.systemSerif(60, weight: .thin, relativeTo: .largeTitle))
                .foregroundColor(accent)
                .contentTransition(.numericText())
            
            Text(String(localized: "hours", comment: "Onboarding – sleep unit label"))
                .font(.systemSerif(16, weight: .light, relativeTo: .subheadline))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 28)
            
            VStack(spacing: 8) {
                Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                    .tint(accent)
                    .padding(.horizontal, 40)
                    .onChange(of: sleepTarget) { _, _ in lightHaptic() }
                
                HStack {
                    Text(String(localized: "6h", comment: "Onboarding – sleep slider minimum"))
                    Spacer()
                    Text(String(localized: "10h", comment: "Onboarding – sleep slider maximum"))
                }
                .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 44)
            }
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 9: Text (health permission)
    
    @ViewBuilder
    private func textSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            
            if let microcopy = slide.microcopy {
                Text(microcopy)
                    .font(.systemSerif(14, weight: .light, relativeTo: .footnote))
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.top, 16)
            }
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 10: Feed Selection (skippable)
    
    private static let popularApps: [(bundleId: String, name: String, imageName: String)] = [
        ("com.burbn.instagram", "Instagram", "instagram"),
        ("com.zhiliaoapp.musically", "TikTok", "tiktok"),
        ("com.google.ios.youtube", "YouTube", "youtube"),
        ("com.atebits.Tweetie2", "X", "x"),
        ("com.reddit.Reddit", "Reddit", "reddit"),
        ("com.facebook.Facebook", "Facebook", "facebook"),
        ("com.toyopagroup.picaboo", "Snapchat", "snapchat"),
        ("ph.telegra.Telegraph", "Telegram", "telegram"),
    ]

    @ViewBuilder
    private func feedSelectionSlide(slide: OnboardingSlide) -> some View {
        let popularApps = Self.popularApps
        
        let hasSelection = !onboardingSelection.applicationTokens.isEmpty
            || !onboardingSelection.categoryTokens.isEmpty
        let isSingleAppConnected = TargetResolver.supportsSingleAppPreset(onboardingSelection)
        let isLockedToSelectedPreset = isSingleAppConnected && selectedFeedApp != nil
        
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 40)
            .padding(.bottom, 32)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(popularApps, id: \.bundleId) { app in
                    let isSelected = selectedFeedApp == app.bundleId && hasSelection
                    let isDisabled = isLockedToSelectedPreset && selectedFeedApp != app.bundleId
                    
                    Button {
                        guard !isDisabled else { return }
                        selectedFeedApp = app.bundleId
                        onboardingSelection = FamilyActivitySelection()
                        
                        if !didTriggerFamilyControlsRequest {
                            didTriggerFamilyControlsRequest = true
                            onFamilyControlsSlide?()
                        }
                        
                        showOnboardingPicker = true
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                Image(app.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.systemSerif(16, relativeTo: .subheadline))
                                        .foregroundStyle(accent)
                                        .background(Circle().fill(.black).padding(2))
                                        .offset(x: 4, y: -4)
                                }
                            }
                            
                            Text(app.name)
                                .font(.systemSerif(11, weight: .light, relativeTo: .caption2))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.35 : 1)
                }
            }
            .padding(.horizontal, 20)

            if hasSelection {
                Text(String(localized: "i'll nudge you when colors are ready to spend."))
                    .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                    .foregroundColor(accent.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.opacity)
            }
            
            Spacer()
            
            if !hasSelection {
                Button {
                    trackSlideCompleted(action: "skipped")
                    withAnimation(.easeInOut) { index += 1 }
                } label: {
                    Text(String(localized: "skip for now"))
                        .font(.systemSerif(15, weight: .light, relativeTo: .subheadline))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showOnboardingPicker, onDismiss: {
            let picked = !onboardingSelection.applicationTokens.isEmpty
                || !onboardingSelection.categoryTokens.isEmpty
            if !picked {
                selectedFeedApp = nil
            } else {
                successHaptic()
            }
        }) {
            #if canImport(FamilyControls) && os(iOS)
            AppSelectionSheet(
                selection: $onboardingSelection,
                templateApp: selectedFeedApp,
                onDone: { showOnboardingPicker = false }
            )
            #else
            AppSelectionSheet(
                selection: $onboardingSelection,
                templateApp: selectedFeedApp,
                onDone: { showOnboardingPicker = false }
            )
            #endif
        }
    }

    // MARK: - Slide 11: NOWHERE → NOW HERE (earned reveal)
    
    @ViewBuilder
    private func nowHereRevealSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                if revealPhase >= 1 {
                    onboardingLineText(
                        String(localized: "i called it nowhere."),
                        size: 20,
                        relativeTo: .title3
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                if revealPhase >= 2 {
                    HStack(spacing: 16) {
                        Text("NOW")
                            .font(.systemSerif(44, weight: .thin, relativeTo: .largeTitle))
                            .foregroundColor(accent)
                        
                        Rectangle()
                            .fill(accent.opacity(0.3))
                            .frame(width: 2, height: 36)
                            .transition(.opacity)
                        
                        Text("HERE")
                            .font(.systemSerif(44, weight: .thin, relativeTo: .largeTitle))
                            .foregroundColor(accent)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                if revealPhase >= 3 {
                    onboardingLineText(
                        String(localized: "i still read it as now here."),
                        size: 18,
                        relativeTo: .body
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 36)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Slide 12: Apple Login
    
    @ViewBuilder
    private func appleLoginSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 20, relativeTo: .title3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 48)
            
            if let auth = authService, auth.isAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.systemSerif(20, weight: .thin, relativeTo: .title3))
                        .foregroundColor(.green.opacity(0.8))
                    Text(String(localized: "Signed in", comment: "Onboarding – Apple sign-in success state"))
                        .font(.systemSerif(18, weight: .light, relativeTo: .body))
                        .foregroundColor(.white.opacity(0.7))
                }
                .transition(.opacity.combined(with: .scale))
            }
            
            if authService?.isLoading == true {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 16)
            }
            
            Spacer()
            
            if authService?.isAuthenticated != true {
                Button {
                    trackSlideCompleted(action: "skipped")
                    withAnimation(.easeInOut) { index += 1 }
                } label: {
                    Text(String(localized: "continue without signing in"))
                        .font(.systemSerif(15, weight: .light, relativeTo: .subheadline))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 8)
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Slide 13: Welcome
    
    @ViewBuilder
    private func welcomeSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                Text(String(localized: "welcome to nowhere"))
                    .font(.systemSerif(24, weight: .light, relativeTo: .title2))
                    .foregroundColor(.white.opacity(0.7))
                
                if let name = authService?.currentUser?.displayName,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.systemSerif(36, weight: .thin, relativeTo: .title))
                        .foregroundColor(accent)
                        .scaleEffect(welcomeNameVisible ? 1.0 : 0.85)
                        .opacity(welcomeNameVisible ? 1.0 : 0)
                }
                
                Text(String(localized: "you're here."))
                    .font(.systemSerif(18, weight: .light, relativeTo: .body))
                    .foregroundColor(.white.opacity(0.45))
                    .opacity(welcomeNameVisible ? 1 : 0)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Button Logic

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        if slides[index].slideType == .appleLogin {
            if authService?.isAuthenticated == true { return nextText }
            return String(localized: "Sign in", comment: "Onboarding – Apple sign-in button label")
        }
        return nextText
    }

    // MARK: - Navigation

    private func next() {
        if slides.indices.contains(index) {
            let slide = slides[index]
            
            switch slide.action {
            case .requestHealth:
                if !didTriggerHealthRequest {
                    didTriggerHealthRequest = true
                    onHealthSlide?()
                    successHaptic()
                }
            case .requestNotifications:
                if !didTriggerNotificationRequest {
                    didTriggerNotificationRequest = true
                    onNotificationSlide?()
                }
            case .requestFamilyControls:
                if !didTriggerFamilyControlsRequest {
                    didTriggerFamilyControlsRequest = true
                    onFamilyControlsSlide?()
                }
            case .none:
                break
            }
            
            if slide.slideType == .appleLogin,
               let auth = authService, !auth.isAuthenticated {
                triggerAppleSignIn(auth: auth)
                return
            }
            
            if slide.slideType == .feedSelection {
                let hasApps = !onboardingSelection.applicationTokens.isEmpty
                    || !onboardingSelection.categoryTokens.isEmpty
                if hasApps, !didTriggerNotificationRequest {
                    didTriggerNotificationRequest = true
                    onNotificationSlide?()
                }
            }
        }

        trackSlideCompleted(action: index == slides.count - 1 ? "finished" : "next")
        
        let lastIndex = slides.count - 1
        if index < lastIndex {
            withAnimation(.easeInOut) { index += 1 }
        } else {
            mediumHaptic()
            finish()
        }
    }
    
    private func triggerAppleSignIn(auth: AuthenticationService) {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        auth.configureAppleRequest(request)
        
        let delegate = AppleSignInDelegate { result in
            switch result {
            case .success(let authorization):
                auth.handleAuthorization(authorization)
                successHaptic()
            case .failure(let error):
                AppLogger.auth.error("Apple Sign In failed: \(error.localizedDescription)")
            }
        }
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = delegate
        
        objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        controller.performRequests()
    }

    private func finish() {
        withAnimation(.easeInOut) {
            isPresented = false
        }
        onFinish()
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Apple Sign In Delegate

@MainActor
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let completion: (Result<ASAuthorization, Error>) -> Void
    
    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}

// MARK: - Placeholder Extension

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Onboarding v5") {
    let previewSlides: [OnboardingSlide] = [
        OnboardingSlide(
            lines: ["i keep ending days i never touched."],
            slideType: .coldOpen
        ),
        OnboardingSlide(
            lines: [
                "i wanted a mirror",
                "that could hold a whole day.",
                "not a dashboard. not a score."
            ],
            slideType: .theCanvas
        ),
        OnboardingSlide(
            lines: ["swipe to color it."],
            slideType: .paintDemo
        ),
        OnboardingSlide(
            lines: [
                "one hundred colors. that's a full day.",
                "tap each to see."
            ],
            slideType: .colorCap
        ),
    ]

    OnboardingStoriesView(
        isPresented: .constant(true),
        slides: previewSlides,
        accent: AppColors.brandAccent,
        skipText: "Skip",
        nextText: "Next",
        startText: "Let's go",
        allowText: "Allow",
        onHealthSlide: { },
        onNotificationSlide: { },
        onFamilyControlsSlide: { },
        onFinish: {},
        stepsTarget: .constant(7_000),
        sleepTarget: .constant(9.0),
        onboardingSelection: .constant(FamilyActivitySelection()),
        selectedFeedApp: .constant(nil as String?)
    )
}
#endif
