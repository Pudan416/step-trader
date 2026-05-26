import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import AuthenticationServices
#if canImport(FamilyControls) && os(iOS)
import FamilyControls
#endif

// Models, floaters, and Apple Sign In are in:
//   Onboarding/OnboardingModels.swift
//   Onboarding/OnboardingFloaters.swift
//   Onboarding/AppleSignInCoordinator.swift

// MARK: - Main View

struct OnboardingStoriesView: View {
    @Binding var isPresented: Bool
    let slides: [OnboardingSlide]
    let accent: Color
    let skipText: String
    let nextText: String
    let startText: String
    let allowText: String
    let flowVersion: String
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
    var bedtimeMinutes: Binding<Int>?
    /// DEBUG: finish the full flow from Settings demo / live replay without stepping through every slide.
    var showsDebugSkipAll: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index: Int = 0
    @State private var showOnboardingPicker = false
    @State private var floaters: [OnboardingFloater] = []
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false
    @State private var didTriggerFamilyControlsRequest = false
    @State private var needsNotificationAfterFeed = false
    @State private var showFeedHint = false
    @State private var showTourPrompt = false
    
    // Analytics
    @State private var slideAppearedAt: Date = Date.now
    
    // Cold open
    @State private var coldOpenVisible: Int = 0
    
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
    
    // v8: Canvas animation phases
    @State private var canvasSleepProgress: Double = 0
    @State private var canvasStepsProgress: Double = 0
    @State private var resetBedtimeReady: Bool = false
    @State private var balancePhase: Int = 0
    @State private var bodyMindHeartVisible: Int = 0
    @State private var welcomeV8Phase: Int = 0
    @State private var welcomeV8Split: CGFloat = 0

    var body: some View {
        ZStack {
            Canvas { context, size in
                let baseProgress = slides.isEmpty ? 0 : Double(index) / Double(max(slides.count - 1, 1))
                let currentType = slides[safe: index]?.slideType ?? .text

                let v8SlideTypes: Set<OnboardingSlideType> = [
                    .coldOpen, .theApp, .canvasSleep, .canvasSteps, .balance,
                    .resetBedtime, .bodyMindHeart, .colorCapV8,
                    .notificationPermission, .welcomeV8
                ]
                let isV8 = v8SlideTypes.contains(currentType)

                let sleepVal: Double
                let stepsVal: Double
                switch currentType {
                case .coldOpen, .theApp:
                    sleepVal = baseProgress * 0.15
                    stepsVal = baseProgress * 0.15
                case .canvasSleep:
                    sleepVal = 0.08 + canvasSleepProgress * 0.17
                    stepsVal = 0.06
                case .canvasSteps:
                    sleepVal = 0.10
                    stepsVal = 0.08 + canvasStepsProgress * 0.20
                case .resetBedtime:
                    sleepVal = 0.14
                    stepsVal = 0.16
                case .balance:
                    let p = min(Double(balancePhase) / 3.0, 1.0)
                    sleepVal = 0.18 + p * 0.10
                    stepsVal = 0.15 + p * 0.13
                default:
                    if isV8 || currentType == .text || currentType == .feedSelection || currentType == .appleLogin {
                        sleepVal = 0.35
                        stepsVal = 0.35
                    } else {
                        sleepVal = baseProgress
                        stepsVal = baseProgress
                    }
                }

                let pal = EnergyGradientRenderer.palette(for: .warmSunset)
                let opacities = EnergyGradientRenderer.computeOpacities(
                    smoothedS: stepsVal,
                    smoothedL: sleepVal,
                    hasStepsData: stepsVal > 0,
                    hasSleepData: sleepVal > 0
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
            .animation(.easeInOut(duration: 1.2), value: index)
            .animation(.easeInOut(duration: 1.0), value: canvasSleepProgress)
            .animation(.easeInOut(duration: 1.0), value: canvasStepsProgress)
            .animation(.easeInOut(duration: 1.0), value: balancePhase)
            
            VStack(spacing: 0) {
                Spacer()
                let hideImage: Set<OnboardingSlideType> = [.canvasSleep, .canvasSteps, .balance, .bodyMindHeart, .colorCapV8]
                let currentSlideType = slides[safe: index]?.slideType ?? .text
                #if canImport(UIKit)
                if UIImage(named: "onboarding_figuer_1") != nil {
                    Image("onboarding_figuer_1")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .opacity(hideImage.contains(currentSlideType) ? 0 : (index == 0 ? 0.3 : 1))
                        .animation(.easeInOut(duration: 0.8), value: index)
                        .animation(.easeInOut(duration: 0.8), value: currentSlideType)
                }
                #endif
            }
            .ignoresSafeArea(edges: .bottom)
            
            if !reduceMotion, !(slides[safe: index]?.slideType.isInteractive ?? false) {
                if index >= 7 {
                    GenerativeCanvasView(
                        elements: Self.onboardingCanvasElements,
                        sleepPoints: 80,
                        stepsPoints: 80,
                        sleepColor: Color(hex: "#4A6FA5"),
                        stepsColor: Color(hex: "#FED415"),
                        decayNorm: 0,
                        backgroundColor: .clear,
                        showLabelsOnCanvas: false,
                        showsOutlinedLabels: false,
                        showsBackgroundGradient: false,
                        timeScale: 0.25
                    )
                    .blur(radius: index > 7 ? 20 : 0)
                    .animation(.easeInOut(duration: 0.5), value: index)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
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
            }
            
            VStack(spacing: 0) {
                progressBar
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Button {
                                goBack()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .minimumHitTarget()
                            }
                            .accessibilityLabel(String(localized: "Back"))
                            .transition(.opacity)
                            .offset(x: -36)
                        }
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.25), value: index)

                Group {
                    if slides.indices.contains(index) {
                        slideContent(slide: slides[index], slideIndex: index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .id(index)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: index)

                VStack(spacing: 8) {
                    if showFeedHint {
                        Text(String(localized: "first you need to add any one app"))
                            .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                            .foregroundStyle(accent)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if isAppleLoginSkippable {
                        Button(action: next) {
                            Text(skipText)
                                .font(.systemSerif(14, weight: .light, relativeTo: .subheadline))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                    } else {
                        Button(action: next) {
                            Text(primaryButtonTitle)
                                .font(.headline)
                                .foregroundStyle(AppAccentInk.primary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(isFeedSlideWithoutSelection ? accent.opacity(0.35) : accent)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(isFeedSlideWithoutSelection)
                        .overlay {
                            if isFeedSlideWithoutSelection {
                                Color.clear.contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.3)) { showFeedHint = true }
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .seconds(2.5))
                                            withAnimation(.easeInOut(duration: 0.3)) { showFeedHint = false }
                                        }
                                    }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showFeedHint)
                .padding(.horizontal, 24)
                .padding(.bottom, isInStoryPhase ? 8 : 40)

                if isInStoryPhase {
                    Button {
                        trackSlideCompleted(action: "skipped_intro")
                        withAnimation(.easeInOut) { index = firstSetupSlideIndex }
                    } label: {
                        Text(skipText)
                            .font(.systemSerif(15, weight: .light, relativeTo: .subheadline))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
            }
            
            Image("grain (small)")
                .resizable()
                .scaledToFill()
                .blendMode(.overlay)
                .opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if showsDebugSkipAll {
                Button {
                    finish(wantsTour: false)
                } label: {
                    Text("Skip onboarding")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .padding(.leading, 16)
                .padding(.top, 12)
            }
        }
        #endif
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = abs(value.translation.height)
                    guard dx > 60, dx > dy, index > 0 else { return }
                    goBack()
                }
        )
        .onAppear {
            floaters = generateFloaters(count: 9, totalSlides: slides.count)
            slideAppearedAt = Date.now
            trackSlideViewed()
            triggerSlideEntryEffects()
        }
        .onChange(of: index) { _, _ in
            slideAppearedAt = Date.now
            trackSlideViewed()
            triggerSlideEntryEffects()
            showFeedHint = false
        }
        .alert(
            String(localized: "do you want me to show you around?"),
            isPresented: $showTourPrompt
        ) {
            Button(String(localized: "yes, please")) { finish(wantsTour: true) }
            Button(String(localized: "no, thanks"), role: .cancel) { finish(wantsTour: false) }
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
                    "flow_version": flowVersion
                ]
            )
        }
    }
    
    private func trackSlideCompleted(action: String) {
        guard slides.indices.contains(index) else { return }
        let slideName = String(describing: slides[index].slideType)
        let durationMs = Int(Date.now.timeIntervalSince(slideAppearedAt) * 1000)
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(
                name: "onboarding_slide_completed",
                properties: [
                    "slide_index": String(index),
                    "slide_name": slideName,
                    "flow_version": flowVersion,
                    "duration_ms": String(durationMs),
                    "action_taken": action
                ]
            )
        }
    }

    // MARK: - Slide Entry Effects
    
    @State private var slideEffectTask: Task<Void, Never>?

    private func triggerSlideEntryEffects() {
        slideEffectTask?.cancel()
        guard slides.indices.contains(index) else { return }
        let slide = slides[index]
        
        switch slide.slideType {
        case .coldOpen:
            coldOpenVisible = 0
            let lineCount = slide.lines.count
            slideEffectTask = Task { @MainActor in
                for i in 0..<lineCount {
                    try? await Task.sleep(for: .milliseconds(Int(Double(i) * 800 + 500)))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.6)) { coldOpenVisible = i + 1 }
                }
            }
        case .colorCap:
            tappedOrbs = []
            ringProgress = 0
        case .spendDemo:
            demoColorPool = 100
            unlockedDemoApps = []
            showMidnightReset = false
            selectedDemoTariff = nil
        case .howItWorks:
            loopPhase = 0
            slideEffectTask = Task { @MainActor in
                for i in 1...4 {
                    try? await Task.sleep(for: .milliseconds(i * 500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { loopPhase = i }
                }
            }
        case .nowHereReveal:
            revealPhase = 0
            nowhereSplit = 0
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.6)) { revealPhase = 1 }
                
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) {
                    revealPhase = 2
                    nowhereSplit = 20
                }
                heavyHaptic()
                
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.5)) { revealPhase = 3 }
                successHaptic()
            }
        case .welcome:
            welcomeNameVisible = false
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { welcomeNameVisible = true }
            }
        case .theApp:
            coldOpenVisible = 0
            let lineCount = slide.lines.count
            slideEffectTask = Task { @MainActor in
                for i in 0..<lineCount {
                    try? await Task.sleep(for: .milliseconds(Int(Double(i) * 700 + 400)))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeIn(duration: 0.5)) { coldOpenVisible = i + 1 }
                }
            }
        case .canvasSleep:
            canvasSleepProgress = 0
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.5)) { canvasSleepProgress = 1.0 }
            }
        case .canvasSteps:
            canvasStepsProgress = 0
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.5)) { canvasStepsProgress = 1.0 }
            }
        case .resetBedtime:
            resetBedtimeReady = false
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.6)) { resetBedtimeReady = true }
                lightHaptic()
            }
        case .balance:
            balancePhase = 0
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.0)) { balancePhase = 1 }
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.0)) { balancePhase = 2 }
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.0)) { balancePhase = 3 }
                successHaptic()
            }
        case .bodyMindHeart:
            bodyMindHeartVisible = 0
            slideEffectTask = Task { @MainActor in
                for i in 1...3 {
                    try? await Task.sleep(for: .milliseconds(i * 600))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { bodyMindHeartVisible = i }
                    lightHaptic()
                }
            }
        case .welcomeV8:
            welcomeV8Phase = 0
            welcomeV8Split = 0
            welcomeNameVisible = false
            slideEffectTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.6)) { welcomeV8Phase = 1 }
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) {
                    welcomeV8Phase = 2
                    welcomeV8Split = 20
                }
                heavyHaptic()
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.5)) { welcomeNameVisible = true }
            }
        default:
            break
        }
    }

    // MARK: - Haptics
    // TODO: Migrate to .sensoryFeedback() modifiers
    
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

    // MARK: - App Icon Helper

    @ViewBuilder
    private var appIconView: some View {
        #if canImport(UIKit)
        if let img = Self.resolvedAppIcon {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.3))
        }
        #else
        Image(systemName: "app.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.3))
        #endif
    }

    #if canImport(UIKit)
    private static let resolvedAppIcon: UIImage? = {
        if let named = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let img = UIImage(named: named), img.size.width > 0 {
            return img
        }
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            var best: UIImage?
            var bestArea: CGFloat = 0
            for name in files {
                guard let img = UIImage(named: name) else { continue }
                let area = img.size.width * img.size.height
                if area > bestArea { bestArea = area; best = img }
            }
            if let best { return best }
        }
        for candidate in ["AppIcon60x60", "AppIcon76x76", "AppIcon"] {
            if let img = UIImage(named: candidate), img.size.width > 0 { return img }
        }
        let pngCandidates = [
            "Icon-iOS-Default-60x60@3x",
            "Icon-iOS-Default-1024x1024@1x",
            "AppIcon60x60@3x",
        ]
        for name in pngCandidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url),
               let img = UIImage(data: data) {
                return img
            }
        }
        return nil
    }()
    #endif

    // MARK: - Text Helpers

    @ViewBuilder
    private func onboardingLineText(_ line: String, size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> some View {
        Text(line)
            .font(.systemSerif(size, weight: .light, relativeTo: textStyle))
            .foregroundStyle(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .lineSpacing(size >= 20 ? 4 : 3)
            .minimumScaleFactor(0.88)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Progress Bar (3 phases)
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? accent : accent.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 2.5)
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
        case .theApp:
            theAppSlide(slide: slide)
        case .canvasSleep:
            canvasSleepSlide(slide: slide)
        case .canvasSteps:
            canvasStepsSlide(slide: slide)
        case .balance:
            balanceSlide(slide: slide)
        case .resetBedtime:
            resetBedtimeSlide(slide: slide)
        case .bodyMindHeart:
            bodyMindHeartSlide(slide: slide)
        case .colorCapV8:
            colorCapV8Slide(slide: slide)
        case .notificationPermission:
            notificationPermissionSlide(slide: slide)
        case .welcomeV8:
            welcomeV8Slide(slide: slide)
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

    // MARK: - Color Cap (interactive ring)

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
                        .foregroundStyle(accent)
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
                                .foregroundStyle(isTapped ? categories[i].color : .white.opacity(0.25))
                            Text(String(localized: "+20"))
                                .font(.systemSerif(10, weight: .light, relativeTo: .caption))
                                .foregroundStyle(isTapped ? categories[i].color.opacity(0.8) : .white.opacity(0.2))
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
                    .accessibilityLabel("\(categories[i].label), 20 colors")
                    .accessibilityHint(isTapped
                        ? String(localized: "Already added")
                        : String(localized: "Tap to add to your daily total"))
                    .accessibilityAddTraits(isTapped ? .isSelected : [])
                }
            }
            .frame(width: 300, height: 300)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Color sources"))
            .accessibilityValue(String(localized: "\(tappedOrbs.count) of 5 tapped, \(tappedOrbs.count * 20) colors"))
            
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

    // MARK: - Slide: Spend Demo (feeds-style with time limits)

    private static let spendDemoTariffs: [(label: String, minutes: Int, cost: Int)] = [
        ("10 min", 10, 4),
        ("30 min", 30, 10),
        ("1 hour", 60, 20),
    ]
    
    @State private var selectedDemoTariff: Int? = nil
    
    @ViewBuilder
    private func spendDemoSlide(slide: OnboardingSlide) -> some View {
        let tariffs = Self.spendDemoTariffs
        let isUnlocked = !unlockedDemoApps.isEmpty
        
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
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                Text(String(localized: "colors"))
                    .font(.systemSerif(14, weight: .light, relativeTo: .caption))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 20)
            
            ZStack {
                Image("instagram")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .opacity(isUnlocked ? 1.0 : 0.4)
                
                if isUnlocked {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(.green.opacity(0.8))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom, 16)
            
            if !isUnlocked {
                Text(String(localized: "Instagram is closed."))
                    .font(.systemSerif(14, weight: .light, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.bottom, 16)
            }
            
            VStack(spacing: 10) {
                ForEach(Array(tariffs.enumerated()), id: \.offset) { i, tariff in
                    let canAfford = demoColorPool >= tariff.cost
                    let isSelected = selectedDemoTariff == i
                    
                    Button {
                        guard !isUnlocked, canAfford else {
                            if !canAfford { rigidHaptic() }
                            return
                        }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedDemoTariff = i
                            demoColorPool -= tariff.cost
                            unlockedDemoApps.insert("instagram")
                        }
                        mediumHaptic()
                    } label: {
                        HStack {
                            Text(tariff.label)
                                .font(.systemSerif(16, weight: .light, relativeTo: .body))
                                .foregroundStyle(isSelected ? accent : .white.opacity(canAfford ? 0.7 : 0.25))
                            
                            Spacer()
                            
                            Text("\(tariff.cost) colors")
                                .font(.systemSerif(14, weight: .light, relativeTo: .subheadline))
                                .foregroundStyle(isSelected ? accent : .white.opacity(canAfford ? 0.45 : 0.15))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? accent.opacity(0.12) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? accent.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnlocked)
                }
            }
            .padding(.horizontal, 32)
            
            Group {
                if isUnlocked, let tariffIdx = selectedDemoTariff {
                    let t = tariffs[tariffIdx]
                    onboardingLineText(
                        String(localized: "\(t.label) for \(t.cost) colors. that's the deal."),
                        size: 14,
                        relativeTo: .footnote
                    )
                } else {
                    onboardingLineText(
                        String(localized: "pick a window to unlock it."),
                        size: 14,
                        relativeTo: .footnote
                    )
                }
            }
            .padding(.top, 16)
            .animation(.easeInOut, value: isUnlocked)
            
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
                                .foregroundStyle(visible ? accent : .white.opacity(0.15))
                        }
                        Text(step.label)
                            .font(.systemSerif(13, weight: .light, relativeTo: .caption))
                            .foregroundStyle(visible ? .white.opacity(0.6) : .white.opacity(0.15))
                    }
                    .opacity(visible ? 1 : 0.3)
                    .scaleEffect(visible ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: visible)
                    
                    if i < steps.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(loopPhase > i ? 0.25 : 0.08))
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
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            
            Text(String(localized: "steps", comment: "Onboarding – steps unit label"))
                .font(.systemSerif(16, weight: .light, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.4))
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
                .foregroundStyle(.white.opacity(0.3))
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
            
            Text(sleepTarget.formatted(.number.precision(.fractionLength(1))))
                .font(.systemSerif(60, weight: .thin, relativeTo: .largeTitle))
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            
            Text(String(localized: "hours", comment: "Onboarding – sleep unit label"))
                .font(.systemSerif(16, weight: .light, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.4))
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
                .foregroundStyle(.white.opacity(0.3))
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
                    .foregroundStyle(.white.opacity(0.35))
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
                                .font(.systemSerif(11, weight: .light, relativeTo: .caption))
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
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
                    .foregroundStyle(accent.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.opacity)
            }

            if !hasSelection, let microcopy = slide.microcopy {
                Text(microcopy)
                    .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }
            
            Spacer()
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
            AppSelectionSheet(
                selection: $onboardingSelection,
                templateApp: selectedFeedApp,
                onDone: { showOnboardingPicker = false }
            )
        }
    }

    // MARK: - Slide: NOWHERE → NOW HERE (split reveal)
    
    @State private var nowhereSplit: CGFloat = 0
    
    @ViewBuilder
    private func nowHereRevealSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                if revealPhase >= 1 {
                    onboardingLineText(
                        slide.lines.first ?? "",
                        size: 20,
                        relativeTo: .title3
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                HStack(spacing: 0) {
                    Text("NOW")
                        .font(.systemSerif(48, weight: .thin, relativeTo: .largeTitle))
                        .foregroundStyle(revealPhase >= 2 ? accent : .white.opacity(0.74))
                        .offset(x: -nowhereSplit)
                    
                    Rectangle()
                        .fill(accent.opacity(nowhereSplit > 0 ? 0.4 : 0))
                        .frame(width: max(nowhereSplit * 0.15, 0), height: 40)
                    
                    Text("HERE")
                        .font(.systemSerif(48, weight: .thin, relativeTo: .largeTitle))
                        .foregroundStyle(revealPhase >= 2 ? accent : .white.opacity(0.74))
                        .offset(x: nowhereSplit)
                }
                .opacity(revealPhase >= 1 ? 1 : 0)
                
                if revealPhase >= 3 {
                    onboardingLineText(
                        String(localized: "so i made this app."),
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

    @State private var appleSignInError: String?
    @State private var showAppleSignInError = false

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
            .padding(.bottom, 24)

            if let microcopy = slide.microcopy {
                Text(microcopy)
                    .font(.systemSerif(14, weight: .light, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
            }

            if let auth = authService, auth.hasAppleAccount {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.systemSerif(20, weight: .thin, relativeTo: .title3))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(String(localized: "Signed in", comment: "Onboarding – Apple sign-in success state"))
                        .font(.systemSerif(18, weight: .light, relativeTo: .body))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .transition(.opacity.combined(with: .scale))
            } else if let auth = authService {
                SignInWithAppleButton(.signIn) { request in
                    auth.configureAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        auth.handleAuthorization(authorization)
                        successHaptic()
                        slideEffectTask?.cancel()
                        slideEffectTask = Task { @MainActor in
                            for _ in 0..<40 {
                                try? await Task.sleep(for: .milliseconds(250))
                                guard !Task.isCancelled else { return }
                                if auth.hasAppleAccount {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    guard !Task.isCancelled else { return }
                                    trackSlideCompleted(action: "signed_in")
                                    withAnimation(.easeInOut) { index += 1 }
                                    return
                                }
                            }
                        }
                    case .failure(let error):
                        let code = (error as NSError).code
                        if code == ASAuthorizationError.canceled.rawValue { return }
                        appleSignInError = error.localizedDescription
                        showAppleSignInError = true
                    }
                }
                .signInWithAppleButtonStyle(.whiteOutline)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 40)
            }

            if authService?.isLoading == true {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 16)
            }

            Spacer()
            Spacer()
        }
        .alert(String(localized: "Error"), isPresented: $showAppleSignInError) {
            Button(String(localized: "OK")) {}
        } message: {
            Text(appleSignInError ?? "")
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
                    .foregroundStyle(.white.opacity(0.7))
                
                if let name = authService?.currentUser?.displayName,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.systemSerif(36, weight: .thin, relativeTo: .title))
                        .foregroundStyle(accent)
                        .scaleEffect(welcomeNameVisible ? 1.0 : 0.85)
                        .opacity(welcomeNameVisible ? 1.0 : 0)
                }
                
                Text(String(localized: "you're here."))
                    .font(.systemSerif(18, weight: .light, relativeTo: .body))
                    .foregroundStyle(.white.opacity(0.45))
                    .opacity(welcomeNameVisible ? 1 : 0)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: The App (slide 1)

    @ViewBuilder
    private func theAppSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Spacer()

            appIconView
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.2), radius: 20, x: 0, y: 8)
                .padding(.bottom, 32)

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

    // MARK: - v8 Slide: Canvas + Sleep (slide 2)

    @ViewBuilder
    private func canvasSleepSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)

            SleepDurationStepper(hours: $sleepTarget)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: Canvas + Steps (slide 3)

    @ViewBuilder
    private func canvasStepsSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)

            StepGoalDrumPicker(value: $stepsTarget)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: Balance (index 5)

    @ViewBuilder
    private func balanceSlide(slide: OnboardingSlide) -> some View {
        let bedtimeText: String = {
            guard let mins = bedtimeMinutes?.wrappedValue else { return "23:00" }
            let h = mins / 60
            let m = mins % 60
            return String(format: "%d:%02d", h == 24 ? 0 : h, m)
        }()

        VStack(spacing: 0) {
            Spacer()

            if balancePhase >= 3 {
                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(accent.opacity(0.6))
                    .transition(.scale.combined(with: .opacity))
                    .padding(.bottom, 32)
            }

            VStack(spacing: 16) {
                onboardingLineText(
                    String(localized: "\(sleepTarget.formatted(.number.precision(.fractionLength(1)))) hours of sleep and \(formatGroupedNumber(Int(stepsTarget))) steps will make your canvas fully balanced."),
                    size: 18,
                    relativeTo: .body
                )

                onboardingLineText(
                    String(localized: "and your day ends at \(bedtimeText)."),
                    size: 18,
                    relativeTo: .body
                )

                Text(String(localized: "you can change this later."))
                    .font(.systemSerif(13, weight: .light, relativeTo: .footnote))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 36)

            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: Reset + Bedtime (index 4)

    @ViewBuilder
    private func resetBedtimeSlide(slide: OnboardingSlide) -> some View {
        let allowedMinutes = Array(stride(from: 21 * 60, through: 23 * 60 + 45, by: 15))
            + Array(stride(from: 0, through: 3 * 60, by: 15))

        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            .opacity(resetBedtimeReady ? 1 : 0)
            .offset(y: resetBedtimeReady ? 0 : 12)

            if let binding = bedtimeMinutes {
                DayResetTimePicker(selectedMinutes: binding, allowedMinutes: allowedMinutes)
                    .opacity(resetBedtimeReady ? 1 : 0)
                    .offset(y: resetBedtimeReady ? 0 : 20)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: Body, Mind, Heart (slide 6)

    private static let v8BMHCategories: [(icon: String, label: String, color: Color, desc: String)] = [
        ("figure.run", "body", Color(red: 0.3, green: 0.8, blue: 0.5),
         "movement, exercise, fresh air — anything physical."),
        ("brain.head.profile", "mind", Color(red: 0.4, green: 0.6, blue: 1.0),
         "reading, learning, creating — feeding your mind."),
        ("heart", "heart", Color(red: 1.0, green: 0.45, blue: 0.55),
         "people, kindness, connection — what you feel."),
    ]

    @ViewBuilder
    private func bodyMindHeartSlide(slide: OnboardingSlide) -> some View {
        let cats = Self.v8BMHCategories

        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)

            VStack(spacing: 20) {
                ForEach(Array(cats.enumerated()), id: \.offset) { i, cat in
                    if bodyMindHeartVisible > i {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(cat.color.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                Image(systemName: cat.icon)
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(cat.color)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(cat.label)
                                    .font(.systemSerif(16, weight: .medium, relativeTo: .body))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text(cat.desc)
                                    .font(.systemSerif(13, weight: .light, relativeTo: .caption))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(cat.color.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Onboarding Canvas Elements (slide 8+)

    private static let onboardingCanvasElements: [CanvasElement] = {
        let palette = CanvasColorPalette.paletteHex
        let specs: [(cat: EnergyCategory, optionId: String, kind: ElementKind, size: CGFloat, pos: CGPoint, variant: Int)] = [
            (.body,  "stretching",      .circle, 0.26, CGPoint(x: 0.22, y: 0.08), 0),
            (.body,  "physical effort",  .circle, 0.24, CGPoint(x: 0.72, y: 0.06), 1),
            (.mind,  "calm",            .circle, 0.13, CGPoint(x: 0.10, y: 0.30), 0),
            (.heart, "connection",       .ray,    0.20, CGPoint(x: 0.88, y: 0.28), 1),
            (.body,  "walking",          .circle, 0.28, CGPoint(x: 0.50, y: 0.42), 2),
            (.mind,  "focusing",         .circle, 0.12, CGPoint(x: 0.25, y: 0.50), 3),
            (.heart, "gratitude",        .ray,    0.18, CGPoint(x: 0.75, y: 0.52), 4),
            (.mind,  "learning",         .circle, 0.14, CGPoint(x: 0.45, y: 0.60), 5),
            (.heart, "joy",              .ray,    0.16, CGPoint(x: 0.08, y: 0.62), 6),
            (.body,  "resting",          .circle, 0.22, CGPoint(x: 0.40, y: 0.78), 0),
            (.mind,  "thinking",         .circle, 0.15, CGPoint(x: 0.42, y: 0.90), 7),
            (.heart, "observing",        .ray,    0.19, CGPoint(x: 0.88, y: 0.85), 8),
        ]
        let refDate = Date(timeIntervalSinceReferenceDate: 1000)
        return specs.enumerated().map { (i, spec) in
            CanvasElement(
                id: UUID(),
                kind: spec.kind,
                category: spec.cat,
                optionId: spec.optionId,
                label: spec.optionId,
                hexColor: palette[i % palette.count],
                size: spec.size,
                basePosition: spec.pos,
                phaseOffset: Double(i) * 0.8,
                driftSpeed: 0.15,
                driftAmplitude: 0.02,
                pulseFrequency: 0.2,
                pulseAmplitude: 0.02,
                rotationSpeed: 5,
                opacity: 0.75,
                createdAt: refDate,
                assetVariant: spec.variant,
                shapeSeed: UInt64(i * 7919 + 42),
                activityCount: Int.random(in: 5...25)
            )
        }
    }()

    // MARK: - v8 Slide: Color Cap (slide 7)

    @ViewBuilder
    private func colorCapV8Slide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }

                HStack(spacing: 8) {
                    Text("100")
                        .font(.systemSerif(36, weight: .thin, relativeTo: .largeTitle))
                        .foregroundStyle(accent)
                    Text(String(localized: "colors"))
                        .font(.systemSerif(16, weight: .light, relativeTo: .body))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial.opacity(0.6))
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - v8 Slide: Notification Permission (slide 11)

    @ViewBuilder
    private func notificationPermissionSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(accent.opacity(0.6))
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, line in
                    onboardingLineText(line, size: 18, relativeTo: .body)
                }
            }
            .padding(.horizontal, 36)

            Spacer()
            Spacer()
        }
    }

    // MARK: - v8 Slide: Welcome (slide 13)

    @ViewBuilder
    private func welcomeV8Slide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text(String(localized: "welcome to"))
                    .font(.systemSerif(20, weight: .light, relativeTo: .title3))
                    .foregroundStyle(.white.opacity(0.5))
                    .opacity(welcomeV8Phase >= 1 ? 1 : 0)

                HStack(spacing: 0) {
                    Text("NOW")
                        .font(.systemSerif(48, weight: .thin, relativeTo: .largeTitle))
                        .foregroundStyle(welcomeV8Phase >= 2 ? accent : .white.opacity(0.74))
                        .offset(x: -welcomeV8Split)

                    Rectangle()
                        .fill(accent.opacity(welcomeV8Split > 0 ? 0.4 : 0))
                        .frame(width: max(welcomeV8Split * 0.15, 0), height: 40)

                    Text("HERE")
                        .font(.systemSerif(48, weight: .thin, relativeTo: .largeTitle))
                        .foregroundStyle(welcomeV8Phase >= 2 ? accent : .white.opacity(0.74))
                        .offset(x: welcomeV8Split)
                }

                if welcomeNameVisible,
                   let name = authService?.currentUser?.displayName,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.systemSerif(28, weight: .thin, relativeTo: .title))
                        .foregroundStyle(accent.opacity(0.8))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 36)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Skip Intro

    private var isInStoryPhase: Bool {
        guard slides.indices.contains(index) else { return false }
        return OnboardingPhase.phase(for: slides[index].slideType) == .story
    }

    private var firstSetupSlideIndex: Int {
        slides.firstIndex { OnboardingPhase.phase(for: $0.slideType) == .setup } ?? 0
    }

    private var isFeedSlideWithoutSelection: Bool {
        guard slides.indices.contains(index),
              slides[index].slideType == .feedSelection else { return false }
        return onboardingSelection.applicationTokens.isEmpty
            && onboardingSelection.categoryTokens.isEmpty
    }

    private var isAppleLoginSkippable: Bool {
        guard slides.indices.contains(index) else { return false }
        return slides[index].slideType == .appleLogin && authService?.hasAppleAccount != true
    }

    // MARK: - Button Logic

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        if slides[index].slideType == .appleLogin {
            if authService?.hasAppleAccount == true { return nextText }
            return skipText
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
                if !didTriggerNotificationRequest || needsNotificationAfterFeed {
                    didTriggerNotificationRequest = true
                    needsNotificationAfterFeed = false
                    onNotificationSlide?()
                }
            case .none:
                break
            }
            
            
            
            if slide.slideType == .feedSelection {
                let hasApps = !onboardingSelection.applicationTokens.isEmpty
                    || !onboardingSelection.categoryTokens.isEmpty
                if hasApps {
                    needsNotificationAfterFeed = true
                }
            }
        }

        trackSlideCompleted(action: index == slides.count - 1 ? "finished" : "next")
        
        let lastIndex = slides.count - 1
        if index < lastIndex {
            withAnimation(.easeInOut) { index += 1 }
        } else {
            mediumHaptic()
            showTourPrompt = true
        }
    }
    
    private func finish(wantsTour: Bool) {
        UserDefaults.standard.set(wantsTour, forKey: "shouldStartCoachMark")
        withAnimation(.easeInOut) {
            isPresented = false
        }
        onFinish()
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
#Preview("Onboarding") {
    OnboardingStoriesView(
        isPresented: .constant(true),
        slides: OnboardingSlides.makeSlides(),
        accent: AppColors.brandAccent,
        skipText: "Skip",
        nextText: "Next",
        startText: "Let's go",
        allowText: "Allow",
        flowVersion: OnboardingSlides.flowVersion,
        onHealthSlide: { },
        onNotificationSlide: { },
        onFamilyControlsSlide: { },
        onFinish: {},
        stepsTarget: .constant(7_000),
        sleepTarget: .constant(9.0),
        onboardingSelection: .constant(FamilyActivitySelection()),
        selectedFeedApp: .constant(nil as String?),
        bedtimeMinutes: .constant(23 * 60)
    )
}
#endif
