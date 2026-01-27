import SwiftUI

enum OnboardingSlideAction: Equatable {
    case none
    case requestLocation
    case requestHealth
    case requestNotifications
    case requestFamilyControls
}

struct OnboardingSlide: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let gradient: [Color]
    let bullets: [String]
    let action: OnboardingSlideAction
}

struct OnboardingStoriesView: View {
    @Binding var isPresented: Bool
    let slides: [OnboardingSlide]
    let accent: Color
    let skipText: String
    let nextText: String
    let startText: String
    let allowText: String
    let onLocationSlide: (() -> Void)?
    let onHealthSlide: (() -> Void)?
    let onNotificationSlide: (() -> Void)?
    let onFamilyControlsSlide: (() -> Void)?
    let onFinish: () -> Void
    @State private var index: Int = 0
    @State private var didTriggerLocationRequest = false
    @State private var didTriggerHealthRequest = false
    @State private var didTriggerNotificationRequest = false
    @State private var didTriggerFamilyControlsRequest = false

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                header
                    .padding(.top, 18)

                progressBar
                    .padding(.top, 6)

                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { idx, slide in
                        slideCard(slide: slide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.bottom, 12)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: index)

                HStack(spacing: 16) {
                    Button(action: finish) {
                        Text(skipText)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.90))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel(skipText)
                    .accessibilityHint("Skips the onboarding and goes to the main app")

                    Button(action: next) {
                        Text(primaryButtonTitle)
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel(primaryButtonTitle)
                    .accessibilityHint("Continues to the next onboarding slide or starts the app")
                }
                .padding(.bottom, 32)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, 10)
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [accent.opacity(0.35), Color.clear],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.22), Color.clear],
                center: .bottomLeading,
                startRadius: 60,
                endRadius: 520
            )
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(slides.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= index ? accent : Color.white.opacity(0.35))
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: index)
            }
        }
        .padding(.horizontal, 24)
    }

    private var header: some View {
        HStack(spacing: 12) {
            appLogo

            VStack(alignment: .leading, spacing: 2) {
                Text("DOOM CTRL")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Fuel → Shields → Control")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topTrailing) {
            Button(action: finish) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.trailing, 16)
        }
    }

    private var appLogo: some View {
        Group {
            if let uiImage = appIconImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .frame(width: 44, height: 44)
                    Text("DC")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
    }

    @ViewBuilder
    private func slideCard(slide: OnboardingSlide) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: slide.gradient.map { $0.opacity(0.90) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: slide.gradient.first?.opacity(0.35) ?? .clear, radius: 20, x: 0, y: 12)

                Image(systemName: slide.symbol)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)
            }
            .padding(.top, 10)

            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                Text(slide.subtitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(slide.bullets, id: \.self) { text in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: slide.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text(text)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.90))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var primaryButtonTitle: String {
        guard slides.indices.contains(index) else { return nextText }
        let lastIndex = slides.count - 1
        if index == lastIndex { return startText }
        if slides[index].action != .none { return allowText }
        return nextText
    }

    private func appIconImage() -> UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let last = files.last
        else { return nil }
        return UIImage(named: last)
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
