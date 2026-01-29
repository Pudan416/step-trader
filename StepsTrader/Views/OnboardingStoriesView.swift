import SwiftUI
import UIKit

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
    
    @State private var index: Int = 0
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
            onboardingBackground.ignoresSafeArea()

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
                .animation(.easeInOut, value: index)

                // Bottom button
                Button(action: next) {
                    Text(primaryButtonTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private var onboardingBackground: some View {
        Color.black
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? accent : Color.white.opacity(0.25))
                    .frame(height: 3)
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
        }
    }

    // MARK: - Text Slide
    
    @ViewBuilder
    private func textSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: slide.gradient.first?.opacity(0.4) ?? .clear, radius: 24, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 40)
            
            // Lines
            VStack(spacing: 8) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 26, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Steps Setup Slide
    
    @ViewBuilder
    private func stepsSetupSlide(slide: OnboardingSlide) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: slide.gradient.first?.opacity(0.4) ?? .clear, radius: 24, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 32)
            
            // Lines
            VStack(spacing: 6) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 24, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            
            // Steps value display
            Text(formatNumber(Int(stepsTarget)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            
            Text("steps")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 32)
            
            // Slider
            VStack(spacing: 8) {
                Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                    .tint(accent)
                    .padding(.horizontal, 40)
                
                HStack {
                    Text("5,000")
                    Spacer()
                    Text("15,000")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
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
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: slide.gradient.first?.opacity(0.4) ?? .clear, radius: 24, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 32)
            
            // Lines
            VStack(spacing: 6) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 24, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            
            // Sleep value display
            Text(String(format: "%.1f", sleepTarget))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(accent)
            
            Text("hours")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 32)
            
            // Slider
            VStack(spacing: 8) {
                Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                    .tint(accent)
                    .padding(.horizontal, 40)
                
                HStack {
                    Text("6h")
                    Spacer()
                    Text("10h")
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
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
                        .font(.system(size: idx == 0 ? 22 : 18, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Selection counter
            Text("\(selectedCount) / 4")
                .font(.system(size: 16, weight: .bold, design: .rounded))
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
        let categoryColor: Color = {
            switch category {
            case .move: return .green
            case .reboot: return .blue
            case .joy: return .orange
            }
        }()
        
        Button {
            model?.togglePreferredOption(optionId: option.id, category: category)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? categoryColor.opacity(0.3) : Color.white.opacity(0.08))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: option.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isSelected ? categoryColor : .white.opacity(0.6))
                }
                
                Text(option.titleEn)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? categoryColor.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? categoryColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
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
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: slide.gradient.first?.opacity(0.4) ?? .clear, radius: 24, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 32)
            
            // Lines
            VStack(spacing: 6) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 24, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            
            // Name input field
            TextField("", text: $userName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .placeholder(when: userName.isEmpty) {
                    Text("Your name")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.3))
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
            
            // Lines
            VStack(spacing: 6) {
                ForEach(Array(slide.lines.enumerated()), id: \.offset) { idx, line in
                    Text(line)
                        .font(.system(size: 24, weight: idx == 0 ? .bold : .medium, design: .rounded))
                        .foregroundColor(idx == 0 ? .white : .white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
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
                            .fill(
                                LinearGradient(
                                    colors: slide.gradient.map { $0.opacity(0.6) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            )
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 50, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // Camera badge
                    Circle()
                        .fill(accent)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                        )
                        .offset(x: 50, y: 50)
                }
            }
            .buttonStyle(.plain)
            
            // Skip text
            if avatarImage == nil {
                Text("Tap to add a photo")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 20)
            } else {
                Button {
                    avatarImage = nil
                } label: {
                    Text("Remove photo")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.red.opacity(0.8))
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
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: slide.gradient.map { $0.opacity(0.90) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: slide.gradient.first?.opacity(0.5) ?? .clear, radius: 30, x: 0, y: 15)

                    Image(systemName: slide.symbol)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 40)
            }
            
            // Welcome text with name
            VStack(spacing: 12) {
                Text("Welcome to Doom Control,")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(displayName)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                
                Text("Your time. Your rules.")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            
            Spacer()
            Spacer()
        }
    }

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        return nextText
    }
    
    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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
        }

        let lastIndex = slides.count - 1
        if index < lastIndex {
            withAnimation(.easeInOut) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
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
