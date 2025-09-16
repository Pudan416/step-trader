import FamilyControls
import Combine

@MainActor
final class FamilyControlsService: ObservableObject {
    @Published var selection = FamilyActivitySelection()

    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
}
