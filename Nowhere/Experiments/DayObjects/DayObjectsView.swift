import SwiftUI

struct DayObjectsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let sceneInput: DayObjectSceneInput
    let digitalImpact: DayObjectDigitalImpact
    let isAnimating: Bool
    let soundPulseBus: DayObjectsSoundPulseBus?
    let presentationMode: DayObjectsPresentationMode
    let lunarPhysicsIsActive: Bool
    let lunarInteractionBus: DayObjectLunarInteractionBus?
    let onWallImpact: @MainActor (DayObjectWallImpact) -> Void
    let onLunarPhysicsReturnCompleted: @MainActor () -> Void

    private let scene: DayObjectScene
    private let environment: DayObjectEnvironment

    init(
        sceneInput: DayObjectSceneInput,
        digitalImpact: DayObjectDigitalImpact = .none,
        isAnimating: Bool = true,
        soundPulseBus: DayObjectsSoundPulseBus? = nil,
        presentationMode: DayObjectsPresentationMode = .canvas,
        lunarPhysicsIsActive: Bool = false,
        lunarInteractionBus: DayObjectLunarInteractionBus? = nil,
        onWallImpact: @escaping @MainActor (DayObjectWallImpact) -> Void = { _ in },
        onLunarPhysicsReturnCompleted: @escaping @MainActor () -> Void = {}
    ) {
        self.sceneInput = sceneInput
        self.digitalImpact = digitalImpact
        self.isAnimating = isAnimating
        self.soundPulseBus = soundPulseBus
        self.presentationMode = presentationMode
        self.lunarPhysicsIsActive = lunarPhysicsIsActive
        self.lunarInteractionBus = lunarInteractionBus
        self.onWallImpact = onWallImpact
        self.onLunarPhysicsReturnCompleted = onLunarPhysicsReturnCompleted
        scene = DayObjectScene.make(input: sceneInput)
        environment = DayObjectEnvironment(
            motionEnergy: sceneInput.motionEnergy,
            visualClarity: sceneInput.visualClarity
        )
    }

    var body: some View {
        ZStack {
            if !presentationMode.isTransparentOverlay {
                LinearGradient(
                    colors: ([scene.palette.backgroundBase] + scene.palette.backgroundFields).map(Self.color),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            DayObjectsMetalView(
                scene: scene,
                environment: environment,
                digitalImpact: digitalImpact,
                isAnimating: isAnimating && scenePhase == .active,
                soundPulseBus: soundPulseBus,
                presentationMode: presentationMode,
                lunarPhysicsIsActive: lunarPhysicsIsActive,
                lunarAngularMotionIsEnabled: !reduceMotion,
                lunarInteractionBus: lunarInteractionBus,
                onWallImpact: onWallImpact,
                onLunarPhysicsReturnCompleted: onLunarPhysicsReturnCompleted
            )
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day Objects canvas")
        .accessibilityValue("Spent colors \(digitalImpact.spentColors)")
        .accessibilityIdentifier("dayObjects.canvas")
    }

    private static func color(_ linearRGB: SIMD3<Float>) -> Color {
        Color(
            .sRGBLinear,
            red: Double(linearRGB.x),
            green: Double(linearRGB.y),
            blue: Double(linearRGB.z),
            opacity: 1
        )
    }
}
