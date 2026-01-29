import Foundation
import os.log

// MARK: - Structured Logging System

/// Centralized logging for the app using OSLog
/// Usage: AppLogger.healthKit.info("Steps fetched: \(steps)")
enum AppLogger {
    // MARK: - Logger Instances
    
    /// General app lifecycle and state
    static let app = Logger(subsystem: subsystem, category: "App")
    
    /// HealthKit operations
    static let healthKit = Logger(subsystem: subsystem, category: "HealthKit")
    
    /// Family Controls and Screen Time
    static let familyControls = Logger(subsystem: subsystem, category: "FamilyControls")
    
    /// Shield management
    static let shield = Logger(subsystem: subsystem, category: "Shield")
    
    /// Network and Supabase operations
    static let network = Logger(subsystem: subsystem, category: "Network")
    
    /// Authentication
    static let auth = Logger(subsystem: subsystem, category: "Auth")
    
    /// PayGate and payments
    static let payment = Logger(subsystem: subsystem, category: "Payment")
    
    /// Energy and budget calculations
    static let energy = Logger(subsystem: subsystem, category: "Energy")
    
    /// UI and navigation
    static let ui = Logger(subsystem: subsystem, category: "UI")
    
    /// Notifications
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    
    /// Debug-only logging (stripped in release)
    static let debug = Logger(subsystem: subsystem, category: "Debug")
    
    // MARK: - Private
    
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.personalproject.StepsTrader"
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log with automatic function/line context
    func trace(_ message: String, function: String = #function, line: Int = #line) {
        self.debug("[\(function):\(line)] \(message)")
    }
    
    /// Log error with optional Error object
    func logError(_ message: String, error: Error? = nil, function: String = #function) {
        if let error = error {
            self.error("[\(function)] \(message): \(error.localizedDescription)")
        } else {
            self.error("[\(function)] \(message)")
        }
    }
}

// MARK: - Debug Print Wrapper

/// Drop-in replacement for print() that uses OSLog in debug and is stripped in release
/// Usage: debugLog("message") or debugLog("message", category: .healthKit)
func debugLog(_ message: String, category: LogCategory = .app, function: String = #function) {
    #if DEBUG
    let logger = category.logger
    logger.debug("[\(function)] \(message)")
    #endif
}

enum LogCategory {
    case app
    case healthKit
    case familyControls
    case shield
    case network
    case auth
    case payment
    case energy
    case ui
    case notifications
    
    var logger: Logger {
        switch self {
        case .app: return AppLogger.app
        case .healthKit: return AppLogger.healthKit
        case .familyControls: return AppLogger.familyControls
        case .shield: return AppLogger.shield
        case .network: return AppLogger.network
        case .auth: return AppLogger.auth
        case .payment: return AppLogger.payment
        case .energy: return AppLogger.energy
        case .ui: return AppLogger.ui
        case .notifications: return AppLogger.notifications
        }
    }
}

// MARK: - Signpost for Performance

/// Performance measurement using os_signpost
enum AppSignpost {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "StepsTrader", category: .pointsOfInterest)
    
    static func begin(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.begin, log: log, name: name, signpostID: id)
    }
    
    static func end(_ name: StaticString, id: OSSignpostID = .exclusive) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
    
    /// Measure a block of code
    static func measure<T>(_ name: StaticString, block: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try block()
    }
    
    /// Measure an async block of code
    static func measureAsync<T>(_ name: StaticString, block: () async throws -> T) async rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        defer { os_signpost(.end, log: log, name: name, signpostID: id) }
        return try await block()
    }
}
