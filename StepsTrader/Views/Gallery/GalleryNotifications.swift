import Foundation

extension Notification.Name {
    static let canvasElementSpawnRequested = Notification.Name("canvasElementSpawnRequested")
    static let canvasElementRemoveRequested = Notification.Name("canvasElementRemoveRequested")
    static let canvasElementRerollRequested = Notification.Name("canvasElementRerollRequested")
}

enum MetricOverlayKind: Identifiable, Equatable {
    case steps
    case sleep
    case category(EnergyCategory)

    var id: String {
        switch self {
        case .steps: return "steps"
        case .sleep: return "sleep"
        case .category(let c): return c.rawValue
        }
    }
}
