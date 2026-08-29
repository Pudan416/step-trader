#if DEBUG || INTERNAL_BUILD
import SwiftUI

enum ExperimentalLabRoute: String, CaseIterable {
    case dayObjects

    static var current: ExperimentalLabRoute? {
        if let name = UserDefaults.standard.string(forKey: "uiLab"),
           let route = ExperimentalLabRoute(rawValue: name),
           route.isEnabled {
            return route
        }

        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-uiLab"),
              index + 1 < arguments.count,
              let route = ExperimentalLabRoute(rawValue: arguments[index + 1]),
              route.isEnabled else {
            return nil
        }
        return route
    }

    private var isEnabled: Bool {
        ExperimentalFeatures.dayObjectsLab
    }

    @ViewBuilder
    var view: some View {
        DayObjectsLabView()
    }
}
#endif
