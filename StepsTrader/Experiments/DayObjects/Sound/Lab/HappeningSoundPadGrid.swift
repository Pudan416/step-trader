#if DEBUG || INTERNAL_BUILD
import SwiftUI

struct HappeningSoundPadGrid: View {
    typealias Audition = @MainActor (HappeningSoundRecipeID) async throws -> Void

    private static let columns = Array(
        repeating: GridItem(.flexible(minimum: 44), spacing: 7),
        count: 5
    )

    private let recipes: [HappeningSoundRecipe]
    private let audition: Audition

    @State private var loadingRecipeIDs: Set<HappeningSoundRecipeID> = []
    @State private var unavailableRecipeIDs: Set<HappeningSoundRecipeID> = []

    init(
        recipes: [HappeningSoundRecipe] = HappeningSoundCatalog.recipes,
        audition: @escaping Audition
    ) {
        self.recipes = recipes
        self.audition = audition
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
        .accessibilityValue("30 sounds")
        .accessibilityIdentifier("dayObjects.happeningPads")
    }

    private func pad(for recipe: HappeningSoundRecipe) -> some View {
        let isLoading = loadingRecipeIDs.contains(recipe.id)
        let isUnavailable = unavailableRecipeIDs.contains(recipe.id)

        return Button {
            beginAudition(recipe.id)
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
        .disabled(isLoading || isUnavailable)
        .accessibilityLabel("Happening sound \(recipe.label), \(familyName(recipe.family))")
        .accessibilityHint("Plays this sound without adding a figure")
        .accessibilityValue(accessibilityValue(isLoading: isLoading, isUnavailable: isUnavailable))
        .accessibilityIdentifier("dayObjects.happeningPad.\(recipe.label)")
    }

    private func beginAudition(_ recipeID: HappeningSoundRecipeID) {
        guard loadingRecipeIDs.insert(recipeID).inserted else { return }

        Task { @MainActor in
            defer { loadingRecipeIDs.remove(recipeID) }
            do {
                try await audition(recipeID)
            } catch HappeningSamplePoolError.recipeUnavailable,
                    HappeningSamplePoolError.resourceUnavailable {
                unavailableRecipeIDs.insert(recipeID)
            } catch {
                // Session and lifecycle failures remain retryable. Only a
                // recipe/resource decode failure permanently disables a pad.
            }
        }
    }

    private func accessibilityValue(isLoading: Bool, isUnavailable: Bool) -> String {
        if isUnavailable { return "Sound unavailable" }
        if isLoading { return "Loading" }
        return "Ready"
    }

    private func familyName(_ family: HappeningRecipeFamily) -> String {
        switch family {
        case .synthPluck: "synth pluck"
        case .acousticMallet: "acoustic mallet"
        case .acousticBell: "acoustic bell"
        case .softOneShot: "soft one-shot"
        case .texture: "texture"
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
