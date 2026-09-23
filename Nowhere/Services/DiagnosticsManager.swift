import Foundation
import MetricKit
import os.log

// MARK: - Diagnostics Manager
/// Captures MetricKit crash / hang / CPU-exception / disk-write-exception
/// diagnostics — which the system aggregates and delivers on the *next* launch
/// after an incident — and records them via OSLog and the analytics pipeline,
/// so a crashing or hanging install is visible server-side instead of silent.
///
/// MetricKit is a first-party Apple framework: no third-party SDK is added, so
/// `PrivacyInfo.xcprivacy` is unchanged and the app's "no third-party trackers"
/// posture holds. Diagnostic payloads are delivered at most once per 24h.
final class DiagnosticsManager: NSObject, MXMetricManagerSubscriber {

    static let shared = DiagnosticsManager()
    private override init() { super.init() }

    /// Compact, Codable summary of one diagnostic category within a payload.
    struct DiagnosticSummary: Codable, Equatable {
        let type: String        // "crash" | "hang" | "cpu_exception" | "disk_write_exception"
        let count: Int
        let appVersion: String
        let osVersion: String
        let receivedAt: Date
    }

    /// Register with MetricKit. Call once, early in app launch.
    func start() {
        MXMetricManager.shared.add(self)
        AppLogger.diagnostics.debug("🩺 MetricKit subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let received = Date.now
        for payload in payloads {
            let summaries = Self.summaries(
                crashes: payload.crashDiagnostics?.count ?? 0,
                hangs: payload.hangDiagnostics?.count ?? 0,
                cpuExceptions: payload.cpuExceptionDiagnostics?.count ?? 0,
                diskWriteExceptions: payload.diskWriteExceptionDiagnostics?.count ?? 0,
                appVersion: Self.appVersion,
                osVersion: Self.osVersion,
                receivedAt: received
            )
            record(summaries)
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Performance metric payloads (launch time, memory, etc.) — logged only,
        // not treated as incidents.
        AppLogger.diagnostics.debug("📈 Received \(payloads.count) MetricKit metric payload(s)")
    }

    // MARK: - Pure summarization (unit-tested)

    /// Builds one summary per non-empty diagnostic category. Kept pure and
    /// taking primitive counts because `MXDiagnostic*` payloads cannot be
    /// constructed in unit tests — this is the part worth guarding.
    static func summaries(
        crashes: Int,
        hangs: Int,
        cpuExceptions: Int,
        diskWriteExceptions: Int,
        appVersion: String,
        osVersion: String,
        receivedAt: Date
    ) -> [DiagnosticSummary] {
        var out: [DiagnosticSummary] = []
        func add(_ type: String, _ count: Int) {
            guard count > 0 else { return }
            out.append(DiagnosticSummary(
                type: type, count: count,
                appVersion: appVersion, osVersion: osVersion, receivedAt: receivedAt
            ))
        }
        add("crash", crashes)
        add("hang", hangs)
        add("cpu_exception", cpuExceptions)
        add("disk_write_exception", diskWriteExceptions)
        return out
    }

    // MARK: - Recording

    private func record(_ summaries: [DiagnosticSummary]) {
        for s in summaries {
            AppLogger.diagnostics.error(
                "🩺 MetricKit \(s.type, privacy: .public) x\(s.count) — app \(s.appVersion, privacy: .public), iOS \(s.osVersion, privacy: .public)"
            )
            let event = s
            Task {
                await SupabaseSyncService.shared.trackAnalyticsEvent(
                    name: "app_diagnostic",
                    properties: [
                        "type": event.type,
                        "count": String(event.count),
                        "app_version": event.appVersion,
                        "os_version": event.osVersion
                    ],
                    // One event per (type, delivery) so re-processing a payload
                    // can't double-count within a session.
                    dedupeKey: "diag_\(event.type)_\(Int(event.receivedAt.timeIntervalSince1970))"
                )
            }
        }
    }

    // MARK: - Environment

    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }
}
