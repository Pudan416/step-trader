import SwiftUI
import UIKit
import AuthenticationServices
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Slide Types

enum OnboardingSlideAction: Equatable {
    case none
    case requestLocation
    case requestHealth
    case requestNotifications
    case requestFamilyControls
}

enum OnboardingSlideType: Equatable {
    case text
    case stepsSetup
    case sleepSetup
    case activitySelection(EnergyCategory)
    case nameInput
    case avatarSetup
    case welcomeWithName
    case feedSelection
    case appleLogin
    case canvasDemo
    case raysDemo
}

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let lines: [String]
    let symbol: String
    let gradient: [Color]
    let action: OnboardingSlideAction
    let slideType: OnboardingSlideType
    
    init(
        lines: [String],
        symbol: String,
        gradient: [Color],
        action: OnboardingSlideAction = .none,
        slideType: OnboardingSlideType = .text
    ) {
        self.lines = lines
        self.symbol = symbol
        self.gradient = gradient
        self.action = action
        self.slideType = slideType
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

private func generateFloaters(count: Int, totalSlides: Int) -> [OnboardingFloater] {
    let bodyAssets = ["body 1", "body 2", "body 3"]
    let mindAssets = ["mind 1"]
    let heartAssets = ["heart 1"]
    let kinds: [FloaterKind] = [.body, .mind, .heart, .body, .mind, .heart, .body, .mind, .body, .heart, .mind, .body, .heart]
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
        Color(red: 0.7, green: 0.3, blue: 0.7),
        Color(red: 0.95, green: 0.55, blue: 0.2),
        Color(red: 0.4, green: 0.7, blue: 0.5),
        Color(red: 0.8, green: 0.4, blue: 0.6),
    ]
    
    var floaters: [OnboardingFloater] = []
    var seed: UInt64 = 42
    
    func nextRandom() -> Double {
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
            (0.20, 0.85), (0.90, 0.15), (0.45, 0.45),
            (0.70, 0.90),
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
    var showsSkip: Bool = true
    let onLocationSlide: (() -> Void)?
    let onHealthSlide: (() -> Void)?
    let onNotificationSlide: (() -> Void)?
    let onFamilyControlsSlide: (() -> Void)?
    let onFinish: () -> Void
    
    // Model for interactive slides
    var model: AppModel?
    @Binding var stepsTarget: Double
    @Binding var sleepTarget: Double
    @Binding var userName: String
    @Binding var avatarImage: UIImage?
    var authService: AuthenticationService?
    @Binding var onboardingSelection: FamilyActivitySelection
    @Binding var selectedFeedApp: String?
    
    @State private var index: Int = 0
    @State private var showOnboardingPicker = false
    @State private var floaters: [OnboardingFloater] = []
    @FocusState private var isNameFieldFocused: Bool
    @State private var showImageSourcePicker: Bool = false
    @State private var showImagePicker: Bool = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var didTriggerLocationRequest = false
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false
    @State private var didTriggerFamilyControlsRequest = false

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
            }
            .ignoresSafeArea(edges: .bottom)
            
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
            
            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 60)
                    .padding(.bottom, 24)

                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideContent(slide: slide)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(true)
                .animation(.easeInOut, value: index)

                Button(action: next) {
                    Text(primaryButtonTitle)
                        .font(.systemSerif(18, weight: .medium))
                        .foregroundColor(.black.opacity(isNextDisabled ? 0.4 : 1))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(accent.opacity(isNextDisabled ? 0.35 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(isNextDisabled)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            
            Image("grain 1")
                .resizable()
                .scaledToFill()
                .blendMode(.overlay)
                .opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            floaters = generateFloaters(count: 13, totalSlides: slides.count)
        }
    }

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
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                    Capsule()
                    .fill(i <= index ? accent : accent.opacity(0.15))
                    .frame(height: 2)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func slideContent(slide: OnboardingSlide) -> some View {
        switch slide.slideType {
        case .text:
            textSlide(slide: slide)
        case .stepsSetup:
            stepsSetupSlide(slide: slide)
        case .sleepSetup:
            sleepSetupSlide(slide: slide)
        case .activitySelection(let category):
            activitySelectionSlide(slide: slide, category: category)
        case .nameInput:
            nameInputSlide(slide: slide)
        case .avatarSetup:
            avatarSetupSlide(slide: slide)
        case .welcomeWithName:
            welcomeWithNameSlide(slide: slide)
        case .feedSelection:
            feedSelectionSlide(slide: slide)
        case .appleLogin:
            appleLoginSlide(slide: slide)
        case .canvasDemo:
            canvasDemoSlide(slide: slide)
        case .raysDemo:
            raysDemoSlide(slide: slide)
        }
    }

    // MARK: - Text Slide
    
    @ViewBuilder
    private func textSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Steps Setup Slide
    
    @ViewBuilder
    private func stepsSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            Text(formatGroupedNumber(Int(stepsTarget)))
                .font(.system(size: 60, weight: .thin))
                .foregroundColor(accent)
            
            Text("steps")
                .font(.systemSerif(16, weight: .light))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 28)
            
            VStack(spacing: 8) {
                Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                    .tint(accent)
                    .padding(.horizontal, 40)
                
                HStack {
                    Text("5,000")
                    Spacer()
                    Text("15,000")
                }
                .font(.systemSerif(13, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 44)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Sleep Setup Slide
    
    @ViewBuilder
    private func sleepSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            Text(String(format: "%.1f", sleepTarget))
                .font(.system(size: 60, weight: .thin))
                .foregroundColor(accent)
            
            Text("hours")
                .font(.systemSerif(16, weight: .light))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 28)
            
            VStack(spacing: 8) {
                Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                    .tint(accent)
                    .padding(.horizontal, 40)
                
                HStack {
                    Text("6h")
                    Spacer()
                    Text("10h")
                }
                .font(.systemSerif(13, weight: .light))
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 44)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Activity Selection Slide
    
    @ViewBuilder
    private func activitySelectionSlide(slide: OnboardingSlide, category: EnergyCategory) -> some View {
        let options = model?.availableOptions(for: category) ?? []
        let selectedCount = options.filter { model?.isPreferredOptionSelected($0.id, category: category) == true }.count
        
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Text("\(selectedCount) / 4")
                .font(.systemSerif(16, weight: .light))
                .foregroundColor(selectedCount == 4 ? accent : .white.opacity(0.5))
                .padding(.bottom, 16)
            
            // Options grid
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(options) { option in
                        activityOptionButton(option: option, category: category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    @ViewBuilder
    private func activityOptionButton(option: EnergyOption, category: EnergyCategory) -> some View {
        let isSelected = model?.isPreferredOptionSelected(option.id, category: category) == true
        
        Button {
            model?.togglePreferredOption(optionId: option.id, category: category)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? accent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                        .frame(width: 50, height: 50)
                    Image(systemName: option.icon)
                        .font(.system(size: 22, weight: .thin))
                        .foregroundColor(isSelected ? accent : .white.opacity(0.5))
                }
                Text(option.titleEn)
                    .font(.systemSerif(13, weight: .light))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? accent.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? accent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Name Input Slide
    
    @ViewBuilder
    private func nameInputSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 40)
            
            TextField("", text: $userName)
                .font(.systemSerif(32, weight: .light))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .placeholder(when: userName.isEmpty) {
                    Text("My name")
                        .font(.systemSerif(32, weight: .light))
                        .foregroundColor(.white.opacity(0.25))
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(accent.opacity(0.5), lineWidth: 2)
                        )
                )
                .padding(.horizontal, 32)
                .focused($isNameFieldFocused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isNameFieldFocused = true
                    }
                }
            
            Spacer()
            Spacer()
        }
        .onTapGesture {
            isNameFieldFocused = false
        }
    }
    
    // MARK: - Avatar Setup Slide
    
    @ViewBuilder
    private func avatarSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 40)
            
            // Avatar picker
            Button {
                showImageSourcePicker = true
            } label: {
                ZStack {
                    if let image = avatarImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 140, height: 140)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(accent, lineWidth: 3)
                            )
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            .frame(width: 140, height: 140)
                        Image(systemName: "person")
                            .font(.system(size: 50, weight: .thin))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Circle()
                        .fill(accent)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "camera")
                                .font(.system(size: 18, weight: .thin))
                                .foregroundColor(.black)
                        )
                        .offset(x: 50, y: 50)
                }
            }
            .buttonStyle(.plain)
            
            // Skip text
            if avatarImage == nil {
                Text("Tap to add a photo")
                    .font(.systemSerif(16, weight: .light))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 20)
            } else {
                Button {
                    avatarImage = nil
                } label: {
                    Text("Remove photo")
                        .font(.systemSerif(16, weight: .light))
                        .foregroundColor(.red.opacity(0.7))
                }
                .padding(.top, 20)
            }
            
            Spacer()
            Spacer()
        }
        .confirmationDialog(
            "Choose Photo",
            isPresented: $showImageSourcePicker,
            titleVisibility: .visible
        ) {
            Button("Camera") {
                imageSourceType = .camera
                showImagePicker = true
            }
            Button("Photo Library") {
                imageSourceType = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $avatarImage, sourceType: imageSourceType)
        }
    }
    
    // MARK: - Welcome With Name Slide
    
    @ViewBuilder
    private func welcomeWithNameSlide(slide: OnboardingSlide) -> some View {
        let displayName = userName.isEmpty ? "User" : userName
        
        VStack(spacing: 0) {
            Spacer()
            
            // Avatar or Icon
            if let image = avatarImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(accent, lineWidth: 3)
                    )
                    .shadow(color: accent.opacity(0.4), radius: 20, x: 0, y: 10)
                    .padding(.bottom, 32)
            }
            
            VStack(spacing: 12) {
                Text("Welcome to Nowhere,")
                    .font(.systemSerif(24, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(displayName)
                    .font(.system(size: 36, weight: .thin))
                    .foregroundColor(accent)
                
                Text("Present. Intentional. Alive.")
                    .font(.systemSerif(20, weight: .light))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
    }

    // MARK: - Canvas Demo Slide
    
    @ViewBuilder
    private func canvasDemoSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Rays Demo Slide
    
    @ViewBuilder
    private func raysDemoSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            
            VStack(spacing: 10) {
                raysRow(icon: "figure.walk", label: "Steps", value: "20/20", icon2: "bed.double", label2: "Sleep", value2: "20/20")
                
                HStack(spacing: 8) {
                    raysChip(icon: "figure.run", label: "Body", value: "20/20")
                    raysChip(icon: "brain.head.profile", label: "Mind", value: "20/20")
                    raysChip(icon: "heart", label: "Heart", value: "20/20")
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            Spacer()
        }
    }
    
    @ViewBuilder
    private func raysRow(icon: String, label: String, value: String, icon2: String, label2: String, value2: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 36)
                Spacer()
                Text(value)
                    .font(.systemSerif(16, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.08))
            )
            
            HStack(spacing: 0) {
                Image(systemName: icon2)
                    .font(.system(size: 16, weight: .thin))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 36)
                Spacer()
                Text(value2)
                    .font(.systemSerif(16, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.08))
            )
        }
    }
    
    @ViewBuilder
    private func raysChip(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .thin))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28)
            Spacer()
            Text(value)
                .font(.systemSerif(14, weight: .light))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - Feed Selection Slide
    
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
        
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(18, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 40)
            .padding(.bottom, 32)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(popularApps, id: \.bundleId) { app in
                    let isSelected = selectedFeedApp == app.bundleId && hasSelection
                    
                    Button {
                        selectedFeedApp = app.bundleId
                        onboardingSelection = FamilyActivitySelection()
                        showOnboardingPicker = true
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                Image(app.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11)
                                            .stroke(isSelected ? accent : .clear, lineWidth: 2)
                                    )
                                    .shadow(color: isSelected ? accent.opacity(0.4) : .clear, radius: 8)
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(accent)
                                        .background(Circle().fill(.black).padding(2))
                                        .offset(x: 4, y: -4)
                                }
                            }
                            
                            Text(app.name)
                                .font(.systemSerif(11, weight: .light))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? accent.opacity(0.15) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(isSelected ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .sheet(isPresented: $showOnboardingPicker, onDismiss: {
            let picked = !onboardingSelection.applicationTokens.isEmpty
                || !onboardingSelection.categoryTokens.isEmpty
            if !picked {
                selectedFeedApp = nil
            }
        }) {
            #if canImport(FamilyControls)
            AppSelectionSheet(
                selection: $onboardingSelection,
                templateApp: selectedFeedApp,
                onDone: { showOnboardingPicker = false }
            )
            #endif
        }
    }
    
    // MARK: - Apple Login Slide
    
    @ViewBuilder
    private func appleLoginSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 12) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.systemSerif(20, weight: .light))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 48)
            
            if let auth = authService, auth.isAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20, weight: .thin))
                        .foregroundColor(.green.opacity(0.8))
                    Text("Signed in")
                        .font(.systemSerif(18, weight: .light))
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
            Spacer()
        }
    }

    private var isNextDisabled: Bool {
        guard slides.indices.contains(index) else { return false }
        if slides[index].slideType == .feedSelection {
            return onboardingSelection.applicationTokens.isEmpty
                && onboardingSelection.categoryTokens.isEmpty
        }
        return false
    }

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        if slides[index].slideType == .appleLogin {
            if authService?.isAuthenticated == true { return nextText }
            return "Login"
        }
        return nextText
    }

    private func next() {
        if slides.indices.contains(index) {
            let action = slides[index].action
            switch action {
            case .requestLocation:
                if !didTriggerLocationRequest {
                    didTriggerLocationRequest = true
                    onLocationSlide?()
                }
            case .requestHealth:
                if !didTriggerHealthRequest {
                    didTriggerHealthRequest = true
                    onHealthSlide?()
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
            
            if slides[index].slideType == .appleLogin,
               let auth = authService, !auth.isAuthenticated {
                triggerAppleSignIn(auth: auth)
                return
            }
        }

        let lastIndex = slides.count - 1
        if index < lastIndex {
            withAnimation(.easeInOut) { index += 1 }
        } else {
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

// MARK: - Apple Sign In Delegate

@MainActor
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let completion: (Result<ASAuthorization, Error>) -> Void
    
    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return UIWindow()
        }
        return window
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
#Preview("Onboarding") {
    OnboardingStoriesView(
        isPresented: .constant(true),
        slides: [
            OnboardingSlide(
                lines: ["Recently, I've found myself lost in “nowhere.”", "Working, scrolling, sleeping", "Over and over every day."],
                symbol: "eye.slash",
                gradient: [Color(white: 0.15), Color(white: 0.08)]
            ),
            OnboardingSlide(
                lines: ["So I built this app", "to turn “nowhere“", "into “now here“"],
                symbol: "paintpalette",
                gradient: [.indigo, .purple]
            ),
            OnboardingSlide(
                lines: ["Each day becomes a canvas", "colored by real-life actions"],
                symbol: "rectangle.on.rectangle.angled",
                gradient: [.blue, .teal],
                slideType: .canvasDemo
            ),
            OnboardingSlide(
                lines: ["Walking adds bright color.", "I need about 7k steps to feel good.", "How about you?"],
                symbol: "figure.walk",
                gradient: [.green, .mint],
                slideType: .stepsSetup
            ),
            OnboardingSlide(
                lines: ["Sleep adds the darker tones.", "My sweet spot is 9 hours.", "What is yours?"],
                symbol: "moon.zzz",
                gradient: [.indigo, .purple],
                slideType: .sleepSetup
            ),
            OnboardingSlide(
                lines: ["To color up your canvas", "share your steps and sleep data"],
                symbol: "heart.text.square",
                gradient: [.pink, .red],
                action: .requestHealth
            ),
            OnboardingSlide(
                lines: ["Hitting your targets brings 20 rays.", "Body, mind, heart activities", "give you even more."],
                symbol: "sun.max",
                gradient: [.orange, .yellow],
                slideType: .raysDemo
            ),
            OnboardingSlide(
                lines: ["Rays are something like a currency", "You can't buy them, but..."],
                symbol: "iphone.slash",
                gradient: [.red, .orange],
                action: .requestFamilyControls
            ),
            OnboardingSlide(
                lines: ["...you can spend them to unlock other apps.", "Pick the first one to try it."],
                symbol: "apps.iphone",
                gradient: [.red, .pink],
                slideType: .feedSelection
            ),
            OnboardingSlide(
                lines: ["To unlock the chosen app", "you'll get a notification.", "Better to allow them."],
                symbol: "bell",
                gradient: [.blue, .cyan],
                action: .requestNotifications
            ),
            OnboardingSlide(
                lines: ["Your canvas is different every day.", "You can set it as your wallpaper.", "That's convenient and... pretty."],
                symbol: "photo",
                gradient: [.teal, .blue]
            ),
            OnboardingSlide(
                lines: ["By the way, I'm Konstantin.", "And you are?"],
                symbol: "person",
                gradient: [.indigo, .purple],
                slideType: .appleLogin
            ),
            OnboardingSlide(
                lines: ["You are now here."],
                symbol: "eye",
                gradient: [.indigo, .purple]
            ),
        ],
        accent: AppColors.brandAccent,
        skipText: "Skip",
        nextText: "Next",
        startText: "Let's go",
        allowText: "Allow",
        showsSkip: false,
        onLocationSlide: nil,
        onHealthSlide: nil,
        onNotificationSlide: nil,
        onFamilyControlsSlide: nil,
        onFinish: {},
        model: nil,
        stepsTarget: .constant(7_000),
        sleepTarget: .constant(9.0),
        userName: .constant(""),
        avatarImage: .constant(nil),
        authService: nil,
        onboardingSelection: .constant(FamilyActivitySelection()),
        selectedFeedApp: .constant(nil)
    )
}
#endif
