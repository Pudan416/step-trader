import Foundation
import os.log
import Darwin

// MARK: - Analytics & Stats
extension SupabaseSyncService {
    
    /// Queue analytics event for KPI tracking.
    /// Uses best-effort delivery to `user_analytics_events` with local queue fallback.
    func trackAnalyticsEvent(name: String, properties: [String: String] = [:], dedupeKey: String? = nil) async {
        #if DEBUG
        guard !CanvasTourAnalyticsGate.shared.isSuppressed else { return }
        #endif

        // Bind the row to the identity at event time. If auth is unavailable,
        // don't create an ownerless event that a later account could inherit.
        guard let identity = await AuthenticationService.shared.analyticsIdentitySnapshot() else {
            AppLogger.network.debug("📡 Analytics event dropped: no authenticated identity")
            return
        }

        if let dedupeKey {
            let scopedKey = "\(identity.userId):\(dedupeKey)"
            if analyticsDedupeKeys.contains(scopedKey) { return }
            analyticsDedupeKeys.insert(scopedKey)
        }
        
        let payload = AnalyticsEventPayload(
            id: UUID().uuidString,
            userId: identity.userId,
            identityType: identity.accountType,
            eventName: name,
            dayKey: AppModel.dayKey(for: Date.now),
            properties: properties,
            occurredAt: Date.now,
            eventStage: AnalyticsEventStage.forName(name),
            schemaVersion: 3,
            appVersion: AnalyticsRuntimeContext.appVersion,
            appBuild: AnalyticsRuntimeContext.appBuild,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: AnalyticsRuntimeContext.deviceModel,
            sessionId: AnalyticsRuntimeContext.sessionID
        )
        
        pendingAnalyticsEvents.append(payload)
        if pendingAnalyticsEvents.count > 250 {
            pendingAnalyticsEvents = Array(pendingAnalyticsEvents.suffix(250))
        }
        persistAnalyticsQueueToDefaults()
        scheduleAnalyticsFlush()
    }
    
    // MARK: - Private Analytics Helpers
    
    private func scheduleAnalyticsFlush() {
        analyticsFlushTask?.cancel()
        analyticsFlushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await flushAnalyticsEvents()
        }
    }

    /// Recheck queued rows after account changes so rows belonging to a
    /// previously active account can flush when that same account returns.
    func analyticsIdentityDidChange() {
        scheduleAnalyticsFlush()
    }
    
    private func flushAnalyticsEvents() async {
        guard !pendingAnalyticsEvents.isEmpty else { return }
        
        guard let auth = await authenticatedContext() else { return }
        let token = auth.token
        let userId = auth.userId

        // Old queue rows have no event-time owner and cannot be assigned safely.
        let ownedEvents = pendingAnalyticsEvents.filter { $0.userId != nil }
        if ownedEvents.count != pendingAnalyticsEvents.count {
            pendingAnalyticsEvents = ownedEvents
            persistAnalyticsQueueToDefaults()
        }
        let eventsForCurrentUser: [(event: AnalyticsEventPayload, userId: String)] = ownedEvents.compactMap { event in
            guard let eventUserId = event.userId, eventUserId == userId else { return nil }
            return (event, eventUserId)
        }
        guard !eventsForCurrentUser.isEmpty else { return }
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_analytics_events")
            let rows = eventsForCurrentUser.map { ownedEvent in
                let event = ownedEvent.event
                return AnalyticsEventInsertRow(
                    userId: ownedEvent.userId,
                    eventName: event.eventName,
                    dayKey: event.dayKey,
                    properties: event.properties,
                    eventId: event.id,
                    occurredAt: iso8601String(event.occurredAt),
                    eventStage: event.eventStage ?? AnalyticsEventStage.forName(event.eventName),
                    schemaVersion: event.schemaVersion ?? 1,
                    appVersion: event.appVersion,
                    appBuild: event.appBuild,
                    osVersion: event.osVersion,
                    deviceModel: event.deviceModel,
                    sessionId: event.sessionId,
                    identityType: event.identityType
                )
            }
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue("return=minimal,resolution=ignore-duplicates", forHTTPHeaderField: "prefer")
            request.httpBody = try JSONEncoder().encode(rows)
            
            let (_, response) = try await network.data(for: request, policy: NetworkClient.RetryPolicy.none)
            guard response.statusCode < 400 else {
                AppLogger.network.error("📡 Analytics flush failed: HTTP \(response.statusCode)")
                return
            }
            
            let sentIDs = Set(eventsForCurrentUser.map { $0.event.id })
            pendingAnalyticsEvents.removeAll { sentIDs.contains($0.id) }
            persistAnalyticsQueueToDefaults()
            AppLogger.network.debug("📡 Analytics flushed: \(rows.count) events")
        } catch {
            AppLogger.network.error("📡 Analytics flush error: \(error.localizedDescription)")
        }
    }
    
    private func persistAnalyticsQueueToDefaults() {
        guard let data = try? JSONEncoder().encode(pendingAnalyticsEvents) else { return }
        Task { @MainActor in
            UserDefaults.nowhere().set(data, forKey: SharedKeys.analyticsEventsQueue)
        }
    }
    
}

private enum AnalyticsEventStage {
    static func forName(_ name: String) -> String {
        if name.hasPrefix("onboarding") { return "onboarding" }
        if name.hasPrefix("coach_mark") || name.hasPrefix("coachmark") { return "guidance" }
        if name == "app_diagnostic" { return "reliability" }
        if name.hasPrefix("sync_") { return "sync" }
        if name.hasPrefix("widget_") { return "adoption" }
        if name.hasPrefix("tab_") { return "navigation" }
        if name.hasPrefix("ticket_") || name.hasPrefix("experience_") { return "access" }
        if name.hasPrefix("canvas_") || name.hasPrefix("happening_") { return "canvas" }
        return "product"
    }
}

private enum AnalyticsRuntimeContext {
    static let sessionID = UUID().uuidString
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    static let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    static let deviceModel: String? = {
        var requiredSize = 0
        guard sysctlbyname("hw.machine", nil, &requiredSize, nil, 0) == 0,
              requiredSize > 0 else { return nil }
        var machine = [CChar](repeating: 0, count: requiredSize)
        guard sysctlbyname("hw.machine", &machine, &requiredSize, nil, 0) == 0 else { return nil }
        return String(cString: machine)
    }()
}
