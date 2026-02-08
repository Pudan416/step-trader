import SwiftUI
import UIKit

enum OnboardingFlowPhase {
    case introImages   // 8 full-screen images, YES on 8th
    case login         // Apple login (slide 9, login1)
    case mainOnboarding
}

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var locationPermissionRequester: LocationPermissionRequester
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let onComplete: () -> Void

    @State private var phase: OnboardingFlowPhase = .introImages
    @State private var onboardingPresented: Bool = true
    @State private var didCheckAuthOnLogin: Bool = false
    
    // Setup values - use @AppStorage for immediate sync with other views
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var userName: String = ""
    @State private var avatarImage: UIImage? = nil

    var body: some View {
        ZStack {
            switch phase {
            case .introImages:
                IntroImagesView(onYes: { advanceToLogin() })
            case .login:
                LoginView(
                    authService: authService,
                    showsClose: false,
                    useLogin1Background: true,
                    onAuthenticated: { advanceToMainOnboarding() }
                )
                .onAppear {
                    guard !didCheckAuthOnLogin else { return }
                    didCheckAuthOnLogin = true
                    Task { @MainActor in
                        await authService.checkAuthenticationState()
                        if authService.isAuthenticated {
                            advanceToMainOnboarding()
                        }
                    }
                }
                .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        advanceToMainOnboarding()
                    }
                }
            case .mainOnboarding:
                OnboardingStoriesView(
                    isPresented: $onboardingPresented,
                    slides: mainSlides(),
                    accent: AppColors.brandPink,
                    skipText: loc(appLanguage, "Skip"),
                    nextText: loc(appLanguage, "Next"),
                    startText: loc(appLanguage, "Let's go"),
                    allowText: loc(appLanguage, "Allow"),
                    showsSkip: false,
                    onLocationSlide: {
                        Task { @MainActor in
                            locationPermissionRequester.requestWhenInUse()
                        }
                    },
                    onHealthSlide: {
                        Task { await model.ensureHealthAuthorizationAndRefresh() }
                    },
                    onNotificationSlide: {
                        Task { await model.requestNotificationPermission() }
                    },
                    onFamilyControlsSlide: {
                        Task { try? await model.familyControlsService.requestAuthorization() }
                    },
                    onFinish: { finishOnboarding() },
                    model: model,
                    stepsTarget: $stepsTarget,
                    sleepTarget: $sleepTarget,
                    userName: $userName,
                    avatarImage: $avatarImage
                )
            }
        }
        .transition(.opacity)
    }

    private func advanceToLogin() {
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .login
        }
    }

    private func advanceToMainOnboarding() {
        if let user = authService.currentUser {
            if let nick = user.nickname, !nick.isEmpty {
                userName = nick
            }
            if let data = user.avatarData, let img = UIImage(data: data) {
                avatarImage = img
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .mainOnboarding
        }
    }

    private func finishOnboarding() {
        // Save setup values to app group (for extensions)
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        
        // Note: Activity preferences (activity/creativity/joys) are saved automatically
        // when toggled via model.togglePreferredOption()
        
        // Save username and avatar to profile
        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatarData = avatarImage?.jpegData(compressionQuality: 0.75)
        
        authService.updateProfile(
            nickname: trimmedName.isEmpty ? nil : trimmedName,
            country: authService.currentUser?.country,
            avatarData: avatarData
        )
        
        // Trigger energy recalculation with new settings
        Task { @MainActor in
            model.recalculateDailyEnergy()
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            onComplete()
        }
    }
    
    // MARK: - Main onboarding slides (after intro 1–8 and login 9)
    
    private func mainSlides() -> [OnboardingSlide] {
        [
            // 1 - Steps setup
            OnboardingSlide(
                lines: [
                    "How many steps a day",
                    "make me feel good?"
                ],
                symbol: "figure.walk",
                gradient: [.green, .mint],
                slideType: .stepsSetup
            ),
            
            // 2 - Move activities
            OnboardingSlide(
                lines: [
                    "Choose up to 4 things",
                    "that boost me."
                ],
                symbol: "figure.run",
                gradient: [.green, .teal],
                slideType: .activitySelection(.activity)
            ),
            
            // 3 - Sleep setup
            OnboardingSlide(
                lines: [
                    "No rest — no freedom.",
                    "How much sleep keeps me at my best?",
                    "My rules."
                ],
                symbol: "moon.zzz.fill",
                gradient: [.indigo, .purple],
                slideType: .sleepSetup
            ),
            
            // 4 - Reboot activities
            OnboardingSlide(
                lines: [
                    "Choose up to 4 ways",
                    "I rest and reset.",
                    "Whatever works."
                ],
                symbol: "arrow.clockwise.heart.fill",
                gradient: [.blue, .cyan],
                slideType: .activitySelection(.creativity)
            ),
            
            // 5 - Gallery activities
            OnboardingSlide(
                lines: [
                    "Freedom is a choice.",
                    "Choose 4 things",
                    "I want in my daily life.",
                    "Meaning > discipline."
                ],
                symbol: "heart.fill",
                gradient: [.orange, .pink],
                slideType: .activitySelection(.joys)
            ),
            
            // 6 - Almost there
            OnboardingSlide(
                lines: [
                    "Almost there.",
                    "Just the basics left."
                ],
                symbol: "checkmark.circle.fill",
                gradient: [.green, .mint]
            ),
            
            // 7 - Family Controls permission
            OnboardingSlide(
                lines: [
                    "Allow access to apps.",
                    "So I decide,",
                    "not the feed."
                ],
                symbol: "apps.iphone",
                gradient: [.indigo, .purple],
                action: .requestFamilyControls
            ),
            
            // 8 - Location permission
            OnboardingSlide(
                lines: [
                    "Allow location access.",
                    "To notice",
                    "when I'm back in the real world."
                ],
                symbol: "location.fill",
                gradient: [.blue, .cyan],
                action: .requestLocation
            ),
            
            // 9 - Health permission
            OnboardingSlide(
                lines: [
                    "Allow health access.",
                    "Steps. Creativity. Joys.",
                    "Nothing extra."
                ],
                symbol: "heart.text.square.fill",
                gradient: [.pink, .red],
                action: .requestHealth
            ),
            
            // 10 - Notifications permission
            OnboardingSlide(
                lines: [
                    "Turn on notifications",
                    "to stay connected.",
                    "No spam.",
                    "Turn them off anytime."
                ],
                symbol: "bell.badge.fill",
                gradient: [.orange, .yellow],
                action: .requestNotifications
            ),
            
            // 11 - Name input
            OnboardingSlide(
                lines: [
                    "What should we call me?",
                    "Pick a name for my journey."
                ],
                symbol: "person.fill",
                gradient: [.cyan, .blue],
                slideType: .nameInput
            ),
            
            // 12 - Avatar setup
            OnboardingSlide(
                lines: [
                    "Add a photo?",
                    "Show the world who owns their experience."
                ],
                symbol: "camera.fill",
                gradient: [.purple, .pink],
                slideType: .avatarSetup
            ),
            
            // 13 - Welcome with name
            OnboardingSlide(
                lines: [],
                symbol: "sparkles",
                gradient: [.pink, .purple],
                slideType: .welcomeWithName
            )
        ]
    }
}
