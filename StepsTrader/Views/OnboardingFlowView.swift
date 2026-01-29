import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var authService: AuthenticationService
    @ObservedObject var locationPermissionRequester: LocationPermissionRequester
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let onComplete: () -> Void

    @State private var showLogin: Bool = true
    @State private var onboardingPresented: Bool = true
    @State private var didCheckAuth: Bool = false
    
    // Setup values - use @AppStorage for immediate sync with other views
    @AppStorage("userStepsTarget") private var stepsTarget: Double = 10_000
    @AppStorage("userSleepTarget") private var sleepTarget: Double = 8.0
    @State private var userName: String = ""
    @State private var avatarImage: UIImage? = nil

    var body: some View {
        ZStack {
            if showLogin {
                LoginView(
                    authService: authService,
                    showsClose: false,
                    onAuthenticated: { advanceToOnboarding() }
                )
            } else {
                OnboardingStoriesView(
                    isPresented: $onboardingPresented,
                    slides: allSlides(),
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
        .onAppear {
            guard !didCheckAuth else { return }
            didCheckAuth = true
            Task { @MainActor in
                await authService.checkAuthenticationState()
                if authService.isAuthenticated {
                    advanceToOnboarding()
                }
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && showLogin {
                advanceToOnboarding()
            }
        }
    }

    private func advanceToOnboarding() {
        withAnimation(.easeInOut(duration: 0.3)) {
            onboardingPresented = true
            showLogin = false
        }
    }

    private func finishOnboarding() {
        // Save setup values to app group (for extensions)
        let defaults = UserDefaults.stepsTrader()
        defaults.set(stepsTarget, forKey: "userStepsTarget")
        defaults.set(sleepTarget, forKey: "userSleepTarget")
        
        // Note: Activity preferences (move/reboot/joy) are saved automatically
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
    
    // MARK: - All 17 Slides
    
    private func allSlides() -> [OnboardingSlide] {
        [
            // 1 - Apps are built to take your time
            OnboardingSlide(
                lines: [
                    "Apps are built to take your time.",
                    "Infinite feeds.",
                    "Endless scroll."
                ],
                symbol: "hourglass",
                gradient: [.purple, .pink]
            ),
            
            // 2 - You spend time
            OnboardingSlide(
                lines: [
                    "You spend time.",
                    "They collect data.",
                    "They profit."
                ],
                symbol: "dollarsign.circle.fill",
                gradient: [.red, .orange]
            ),
            
            // 3 - But you're free
            OnboardingSlide(
                lines: [
                    "But you're free.",
                    "You can choose.",
                    "You can stop doomscrolling — your way."
                ],
                symbol: "bird.fill",
                gradient: [.cyan, .blue]
            ),
            
            // 4 - Doom Control is resistance
            OnboardingSlide(
                lines: [
                    "Doom Control is resistance.",
                    "For people who want their time back."
                ],
                symbol: "shield.checkered",
                gradient: [.pink, .purple]
            ),
            
            // 5 - Do what you want
            OnboardingSlide(
                lines: [
                    "Do what you want.",
                    "Enjoy the real world.",
                    "With people who choose the same."
                ],
                symbol: "sun.max.fill",
                gradient: [.yellow, .orange]
            ),
            
            // 6 - Ready to join?
            OnboardingSlide(
                lines: [
                    "Ready to join?",
                    "Ready for Doom Control?",
                    "Just a few questions.",
                    "No right answers."
                ],
                symbol: "questionmark.circle.fill",
                gradient: [.green, .teal]
            ),
            
            // 7 - Steps setup
            OnboardingSlide(
                lines: [
                    "How many steps a day",
                    "make you feel good?"
                ],
                symbol: "figure.walk",
                gradient: [.green, .mint],
                slideType: .stepsSetup
            ),
            
            // 8 - Move activities
            OnboardingSlide(
                lines: [
                    "Choose up to 4 things",
                    "that boost you."
                ],
                symbol: "figure.run",
                gradient: [.green, .teal],
                slideType: .activitySelection(.move)
            ),
            
            // 9 - Sleep setup
            OnboardingSlide(
                lines: [
                    "No rest — no freedom.",
                    "How much sleep keeps you at your best?",
                    "Your rules."
                ],
                symbol: "moon.zzz.fill",
                gradient: [.indigo, .purple],
                slideType: .sleepSetup
            ),
            
            // 10 - Reboot activities
            OnboardingSlide(
                lines: [
                    "Choose up to 4 ways",
                    "you rest and reset.",
                    "Whatever works."
                ],
                symbol: "arrow.clockwise.heart.fill",
                gradient: [.blue, .cyan],
                slideType: .activitySelection(.reboot)
            ),
            
            // 11 - Choice activities
            OnboardingSlide(
                lines: [
                    "Freedom is a choice.",
                    "Choose 4 things",
                    "you want in your daily life.",
                    "Meaning > discipline."
                ],
                symbol: "heart.fill",
                gradient: [.orange, .pink],
                slideType: .activitySelection(.joy)
            ),
            
            // 12 - Almost there
            OnboardingSlide(
                lines: [
                    "Almost there.",
                    "Just the basics left."
                ],
                symbol: "checkmark.circle.fill",
                gradient: [.green, .mint]
            ),
            
            // 13 - Family Controls permission
            OnboardingSlide(
                lines: [
                    "Allow access to apps.",
                    "So you decide,",
                    "not the feed."
                ],
                symbol: "apps.iphone",
                gradient: [.indigo, .purple],
                action: .requestFamilyControls
            ),
            
            // 14 - Location permission
            OnboardingSlide(
                lines: [
                    "Allow location access.",
                    "To notice",
                    "when you're back in the real world."
                ],
                symbol: "location.fill",
                gradient: [.blue, .cyan],
                action: .requestLocation
            ),
            
            // 15 - Health permission
            OnboardingSlide(
                lines: [
                    "Allow health access.",
                    "Sleep. Movement. Recovery.",
                    "Nothing extra."
                ],
                symbol: "heart.text.square.fill",
                gradient: [.pink, .red],
                action: .requestHealth
            ),
            
            // 16 - Notifications permission
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
            
            // 17 - Name input
            OnboardingSlide(
                lines: [
                    "What should we call you?",
                    "Pick a name for your journey."
                ],
                symbol: "person.fill",
                gradient: [.cyan, .blue],
                slideType: .nameInput
            ),
            
            // 18 - Avatar setup
            OnboardingSlide(
                lines: [
                    "Add a photo?",
                    "Show the world who's in control."
                ],
                symbol: "camera.fill",
                gradient: [.purple, .pink],
                slideType: .avatarSetup
            ),
            
            // 19 - Welcome with name
            OnboardingSlide(
                lines: [],
                symbol: "sparkles",
                gradient: [.pink, .purple],
                slideType: .welcomeWithName
            )
        ]
    }
}
