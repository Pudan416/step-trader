#if DEBUG || INTERNAL_BUILD
import SwiftUI

struct HappeningSoundPadGrid: View {
    private static let columns = Array(
        repeating: GridItem(.flexible(minimum: 44), spacing: 7),
        count: 5
    )

    private let recipes: [HappeningSoundRecipe]
    @ObservedObject private var controller: DayObjectsMusicLabController
    private let beforeAudition: @MainActor () async -> Void

    init(
        recipes: [HappeningSoundRecipe] = HappeningSoundCatalog.recipes,
        controller: DayObjectsMusicLabController,
        beforeAudition: @escaping @MainActor () async -> Void
    ) {
        self.recipes = recipes
        self.controller = controller
        self.beforeAudition = beforeAudition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Happening sounds")
                .font(.geist(.caption).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            LazyVGrid(columns: Self.columns, spacing: 7) {
                ForEach(recipes, id: \.id) { recipe in
                    pad(for: recipe)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Happening sounds")
        .accessibilityValue("\(recipes.count) sounds")
        .accessibilityIdentifier("dayObjects.happeningPads")
    }

    private func pad(for recipe: HappeningSoundRecipe) -> some View {
        let status = controller.happeningPadStatus(for: recipe.id)
        let isLoading = status == .loading

        return Button {
            controller.beginHappeningPadAudition(recipe.id, beforeAudition: beforeAudition)
        } label: {
            ZStack {
                Text(recipe.label)
                    .font(.geist(.caption).monospacedDigit().weight(.semibold))
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(HappeningSoundPadButtonStyle())
        .disabled(status != .ready)
        .accessibilityLabel("Happening \(recipe.label), \(recipe.workingName)")
        .accessibilityHint("Plays this sound without adding a figure")
        .accessibilityValue(accessibilityValue(status))
        .accessibilityIdentifier("dayObjects.happeningPad.\(recipe.label)")
    }

    private func accessibilityValue(_ status: HappeningPadAuditionStatus) -> String {
        switch status {
        case .ready: "Ready"
        case .loading: "Loading"
        case .soundStopping: "Sound stopping"
        case .unavailable: "Sound unavailable"
        case .exporting: "Export in progress"
        }
    }

}

private struct HappeningSoundPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 1 : 0.86))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(configuration.isPressed ? 0.24 : 0.11))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(configuration.isPressed ? 0.42 : 0.18), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif
