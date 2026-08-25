import SwiftUI

struct DayObjectsView: View {
    @Environment(\.scenePhase) private var scenePhase

    let sceneInput: DayObjectSceneInput
    let isAnimating: Bool

    private let scene: DayObjectScene
    private let environment: DayObjectEnvironment

    init(sceneInput: DayObjectSceneInput, isAnimating: Bool = true) {
        self.sceneInput = sceneInput
        self.isAnimating = isAnimating
        scene = DayObjectScene.make(input: sceneInput)
        environment = DayObjectEnvironment(
            motionEnergy: sceneInput.motionEnergy,
            visualClarity: sceneInput.visualClarity,
            reduceMotion: sceneInput.reduceMotion
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: ([scene.palette.backgroundBase] + scene.palette.backgroundFields).map(Self.color),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            DayObjectsMetalView(
                scene: scene,
                environment: environment,
                isAnimating: isAnimating && scenePhase == .active
            )
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day Objects canvas")
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
