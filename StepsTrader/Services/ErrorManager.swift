import Foundation

enum AppError: LocalizedError {
    case healthKitAuthorizationFailed(Error)
    case healthKitDataUnavailable
    case familyControlsAuthorizationFailed(Error)
    case persistenceError(Error)
    case networkError(Error)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .healthKitAuthorizationFailed(let error):
            return "HealthKit authorization failed: \(error.localizedDescription)"
        case .healthKitDataUnavailable:
            return "Health data is unavailable."
        case .familyControlsAuthorizationFailed(let error):
            return "Screen Time authorization failed: \(error.localizedDescription)"
        case .persistenceError(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}

@MainActor
class ErrorManager: ObservableObject {
    static let shared = ErrorManager()
    
    @Published var currentError: AppError?
    @Published var showErrorAlert = false
    
    func handle(_ error: Error) {
        if let appError = error as? AppError {
            currentError = appError
        } else {
            currentError = .unknown(error)
        }
        showErrorAlert = true
        
        // Log error (can be extended to send to crash reporting service)
        print("❌ ErrorManager caught: \(error.localizedDescription)")
    }
    
    func dismiss() {
        currentError = nil
        showErrorAlert = false
    }
}
