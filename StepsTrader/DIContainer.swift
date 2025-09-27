import Foundation

// MARK: - Dependency Injection Container
final class DIContainer {
    static let shared = DIContainer()
    
    private init() {}
    
    func makeHealthKitService() -> any HealthKitServiceProtocol {
        HealthKitService()
    }
    
    @MainActor
    func makeFamilyControlsService() -> any FamilyControlsServiceProtocol {
        FamilyControlsService()
    }
    
    func makeNotificationService() -> any NotificationServiceProtocol {
        NotificationManager()
    }
    
    func makeBudgetEngine() -> any BudgetEngineProtocol {
        BudgetEngine()
    }
    
    @MainActor
    func makeAppModel() -> AppModel {
        AppModel(
            healthKitService: makeHealthKitService(),
            familyControlsService: makeFamilyControlsService(),
            notificationService: makeNotificationService(),
            budgetEngine: makeBudgetEngine()
        )
    }
}
