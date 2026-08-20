#if DEBUG
import SwiftUI

/// Debug-only launch shortcut: `-uiLab <name>` opens an experiment bench as the
/// app's root, skipping onboarding, tabs and settings.
///
/// This exists because verifying a shader means looking at it, and walking the
/// settings path with synthetic taps drops or misroutes them often enough that
/// the check costs more than the change being checked. Release builds never
/// compile this file's call site.
enum ExperimentalLabRoute: String, CaseIterable {
    case dayRays
    case atmosphere
    case generativeScene

    static var current: ExperimentalLabRoute? {
        // iOS folds `-key value` launch arguments into the NSArgumentDomain,
        // so the defaults lookup is the reliable read; the argv scan stays as
        // a fallback for launches that pass the flag some other way.
        if let name = UserDefaults.standard.string(forKey: "uiLab"),
           let route = ExperimentalLabRoute(rawValue: name) {
            return route
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiLab"), index + 1 < arguments.count {
            return ExperimentalLabRoute(rawValue: arguments[index + 1])
        }
        return nil
    }

    @ViewBuilder
    var view: some View {
        switch self {
        case .dayRays:         DayRaysLabView()
        case .atmosphere:      CanvasAtmosphereLabView()
        case .generativeScene: GenerativeSceneLabView()
        }
    }
}
#endif
