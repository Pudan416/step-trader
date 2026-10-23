enum ScenePhase { case active }
enum UsageBudgetMonitoringError { case notAuthorized; var userFacingMessage: String { "Not authorized" } }
struct Request { let windowRaw = "minutes10"; let groupId = "stable-group" }
@MainActor final class RootFixture {
    let model = Model()
    let scenePhase = ScenePhase.active
    let canPresentSessionUI = true
    let isUITest = false
    var isProcessingWidgetUnlock = false
    var pendingWidgetUnlock: (request: Request, receivedAt: Date)? = (Request(), .now)
    func trigger() { processPendingWidgetUnlock() }
    /*__ROOT__*/
}
@main @MainActor struct RootWidgetAccountAuthorizationHarness {
    static func main() async {
        defer { SharedKeys.defaults.removePersistentDomain(forName: SharedKeys.suite) }
        let root = RootFixture()
        root.trigger()
        await withCheckedContinuation { root.model.familyControlsService.entered = $0 }
        root.model.historyWorkGeneration = UUID()
        root.model.totalStepsBalance = 500
        // A new incoming purchase owns this flag. Old A's defer cannot reset it.
        root.isProcessingWidgetUnlock = true
        root.model.familyControlsService.continuation?.resume()
        root.model.familyControlsService.continuation = nil
        for _ in 0..<20 { await Task.yield() }
        precondition(root.model.charges == 0 && root.model.totalStepsBalance == 500,
            "Root's delayed A authorization must not charge B")
        precondition(root.model.snapshots == 0, "Old root defer must not publish a B snapshot")
        precondition(root.isProcessingWidgetUnlock, "Old root defer must not reset a new incoming purchase")

        let fresh = RootFixture()
        fresh.trigger()
        await withCheckedContinuation { fresh.model.familyControlsService.entered = $0 }
        fresh.model.familyControlsService.continuation?.resume()
        fresh.model.familyControlsService.continuation = nil
        for _ in 0..<20 { await Task.yield() }
        precondition(fresh.model.charges == 1 && fresh.model.totalStepsBalance == 90)
        precondition(fresh.model.snapshots == 1 && !fresh.isProcessingWidgetUnlock)
        print("PASS root widget authorization keeps original account generation across system prompt")
    }
}
