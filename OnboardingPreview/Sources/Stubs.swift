import SwiftUI
import os.log

// MARK: - FamilyControls stubs

struct FamilyActivitySelection: Equatable {
    var applicationTokens: Set<String> = []
    var categoryTokens: Set<String> = []
    init() {}
}

struct AppSelectionSheet: View {
    @Binding var selection: FamilyActivitySelection
    let templateApp: String?
    let onDone: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("App Selection (mock)")
                .font(.headline)
            Button("Done") { onDone() }
        }
        .padding()
    }
}

// MARK: - AppModel

@MainActor
final class AppModel: ObservableObject {
    let familyControlsService = MockFamilyControlsService()
    
    func ensureHealthAuthorizationAndRefresh() async {}
    func requestNotificationPermission() async {}
    func recalculateDailyEnergy() {}
    func createTicketGroup(name: String, templateApp: String?) -> MockTicketGroup {
        MockTicketGroup()
    }
    func addAppsToGroup(_ id: String, selection: FamilyActivitySelection) {}
}

struct MockTicketGroup {
    let id: String = UUID().uuidString
    let name: String = "Mock Group"
}

struct MockFamilyControlsService {
    func requestAuthorization() async throws {}
}

// MARK: - AuthenticationService

class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var currentUser: AppUser? = nil
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    func configureAppleRequest(_ request: Any) {}
    func handleAuthorization(_ authorization: Any) {
        isAuthenticated = true
        currentUser = AppUser(
            id: "preview",
            email: "preview@nowhere.app",
            nickname: nil,
            country: nil,
            avatarData: nil,
            avatarURL: nil,
            createdAt: Date(),
            hasSetCustomNickname: false
        )
    }
}

struct AppUser: Codable {
    let id: String
    let email: String?
    var nickname: String?
    var country: String?
    var avatarData: Data?
    var avatarURL: String?
    let createdAt: Date
    var hasSetCustomNickname: Bool
    
    var displayName: String {
        if hasSetCustomNickname, let nickname, !nickname.isEmpty {
            return nickname
        }
        return email?.components(separatedBy: "@").first ?? "Preview User"
    }
}

// MARK: - SupabaseSyncService

actor SupabaseSyncService {
    static let shared = SupabaseSyncService()
    
    func trackAnalyticsEvent(name: String, properties: [String: String] = [:], dedupeKey: String? = nil) {
        print("[Analytics] \(name): \(properties)")
    }
}

// MARK: - TargetResolver

enum TargetResolver {
    static func displayName(for bundleId: String) -> String {
        let map = [
            "com.burbn.instagram": "Instagram",
            "com.zhiliaoapp.musically": "TikTok",
            "com.google.ios.youtube": "YouTube",
            "com.atebits.Tweetie2": "X",
            "com.reddit.Reddit": "Reddit",
            "com.facebook.Facebook": "Facebook",
            "com.toyopagroup.picaboo": "Snapchat",
            "ph.telegra.Telegraph": "Telegram",
        ]
        return map[bundleId] ?? bundleId
    }
    
    static func supportsSingleAppPreset(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty
    }
    
    static func singleAppPresetValidationMessage(
        for selection: FamilyActivitySelection,
        templateBundleId: String?
    ) -> String? {
        nil
    }
}

// MARK: - AppLogger

enum AppLogger {
    static let app = Logger(subsystem: "preview", category: "App")
    static let auth = Logger(subsystem: "preview", category: "Auth")
    static let network = Logger(subsystem: "preview", category: "Network")
}

// MARK: - AppColors

enum AppColors {
    static let brandAccent = Color(red: 0xFF/255, green: 0xD3/255, blue: 0x69/255)
}

// MARK: - SharedKeys

enum SharedKeys {
    static let appGroupId = "group.preview"
    static let userStepsTarget = "userStepsTarget"
    static let userSleepTarget = "userSleepTarget"
    static let analyticsEventsQueue = "analyticsEventsQueue"
}

// MARK: - UserDefaults extension

extension UserDefaults {
    static func stepsTrader() -> UserDefaults { .standard }
}

// MARK: - Font extension (.systemSerif)

extension Font {
    static func systemSerif(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Number formatting

func formatGroupedNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

// MARK: - Mock Image Provider
// On macOS preview, named images from the iOS asset catalog don't exist.
// This extension returns SF Symbol placeholders so the layout renders correctly.

extension Image {
    private static let sfSymbolFallback: [String: String] = [
        "instagram": "camera.fill",
        "tiktok": "music.note",
        "youtube": "play.rectangle.fill",
        "x": "xmark",
        "reddit": "bubble.left.fill",
        "facebook": "f.cursive",
        "snapchat": "camera.metering.spot",
        "telegram": "paperplane.fill",
        "onboarding_figuer_1": "person.fill",
        "grain 1": "circle.fill",
        "body 1": "figure.walk",
        "body 2": "figure.run",
        "body 3": "figure.cooldown",
        "mind 1": "brain.head.profile",
        "heart 1": "heart.fill",
    ]
    
    init(assetOrSymbol name: String) {
        if let symbol = Self.sfSymbolFallback[name] {
            self.init(systemName: symbol)
        } else {
            self.init(name)
        }
    }
}

// MARK: - EnergyGradientRenderer

enum GradientPalette: String, CaseIterable {
    case warmSunset, roseGarden, ember, dusk
}

enum EnergyGradientRenderer {
    struct Palette {
        let bright: Color
        let warm: Color
        let cool: Color
        let dark: Color
        let daylightBase: Color
    }
    
    struct Opacities {
        let gold: Double
        let coral: Double
        let navy: Double
        let night: Double
    }
    
    enum GradientStyle { case radial, linear }
    
    static func palette(for scheme: GradientPalette) -> Palette {
        switch scheme {
        case .warmSunset:
            return Palette(
                bright: Color(red: 1.0, green: 0.75, blue: 0.4),
                warm: Color(red: 0.99, green: 0.54, blue: 0.45),
                cool: Color(red: 0.0, green: 0.23, blue: 0.42),
                dark: Color(red: 0.0, green: 0.15, blue: 0.27),
                daylightBase: Color(red: 0.95, green: 0.86, blue: 0.78)
            )
        default:
            return palette(for: .warmSunset)
        }
    }
    
    static func computeOpacities(
        smoothedS Ss: Double,
        smoothedL Ls: Double,
        hasStepsData: Bool,
        hasSleepData: Bool,
        isDaylight: Bool = false
    ) -> Opacities {
        let goldOp = hasStepsData ? min(Ss, 1.0) : 0
        let coralOp = hasStepsData ? min(Ss * 0.8, 1.0) : 0
        let navyOp = hasSleepData ? min(Ls * 0.9, 1.0) : 0
        let nightOp = hasSleepData ? min(Ls * 0.7, 1.0) : 0
        return Opacities(gold: goldOp, coral: coralOp, navy: navyOp, night: nightOp)
    }
    
    static func draw(
        context: inout GraphicsContext,
        size: CGSize,
        opacities: Opacities,
        baseColor: Color,
        gradientStyle: GradientStyle,
        colorPalette: Palette
    ) {
        let bg = Path(CGRect(origin: .zero, size: size))
        context.fill(bg, with: .color(colorPalette.dark))
        
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.45)
        
        if opacities.night > 0.01 {
            let nightGrad = Gradient(colors: [colorPalette.cool.opacity(opacities.night), .clear])
            context.fill(bg, with: .radialGradient(nightGrad, center: center, startRadius: 0, endRadius: size.width * 0.8))
        }
        if opacities.navy > 0.01 {
            let navyGrad = Gradient(colors: [colorPalette.cool.opacity(opacities.navy * 0.6), .clear])
            context.fill(bg, with: .radialGradient(navyGrad, center: CGPoint(x: size.width * 0.4, y: size.height * 0.6), startRadius: 0, endRadius: size.width * 0.6))
        }
        if opacities.coral > 0.01 {
            let coralGrad = Gradient(colors: [colorPalette.warm.opacity(opacities.coral * 0.5), .clear])
            context.fill(bg, with: .radialGradient(coralGrad, center: CGPoint(x: size.width * 0.6, y: size.height * 0.35), startRadius: 0, endRadius: size.width * 0.5))
        }
        if opacities.gold > 0.01 {
            let goldGrad = Gradient(colors: [colorPalette.bright.opacity(opacities.gold * 0.4), .clear])
            context.fill(bg, with: .radialGradient(goldGrad, center: center, startRadius: 0, endRadius: size.width * 0.45))
        }
    }
}
