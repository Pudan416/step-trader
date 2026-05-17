import Foundation
import os.log

// MARK: - Analytics & Activity Stats
extension SupabaseSyncService {
    
    /// Queue analytics event for KPI tracking.
    /// Uses best-effort delivery to `user_analytics_events` with local queue fallback.
    func trackAnalyticsEvent(name: String, properties: [String: String] = [:], dedupeKey: String? = nil) {
        if let dedupeKey {
            if analyticsDedupeKeys.contains(dedupeKey) { return }
            analyticsDedupeKeys.insert(dedupeKey)
        }
        
        let payload = AnalyticsEventPayload(
            id: UUID().uuidString,
            eventName: name,
            dayKey: AppModel.dayKey(for: Date()),
            properties: properties,
            occurredAt: Date()
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
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s debounce
            guard !Task.isCancelled else { return }
            await flushAnalyticsEvents()
        }
    }
    
    private func flushAnalyticsEvents() async {
        guard !pendingAnalyticsEvents.isEmpty else { return }
        
        guard let auth = await authenticatedContext() else { return }
        let token = auth.token
        let userId = auth.userId
        
        do {
            let cfg = try SupabaseConfig.load()
            let endpoint = cfg.baseURL.appendingPathComponent("rest/v1/user_analytics_events")
            let rows = pendingAnalyticsEvents.map {
                AnalyticsEventInsertRow(
                    userId: userId,
                    eventName: $0.eventName,
                    dayKey: $0.dayKey,
                    properties: $0.properties,
                    eventId: $0.id,
                    occurredAt: iso8601String($0.occurredAt)
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
            
            pendingAnalyticsEvents.removeAll()
            persistAnalyticsQueueToDefaults()
            AppLogger.network.debug("📡 Analytics flushed: \(rows.count) events")
        } catch {
            AppLogger.network.error("📡 Analytics flush error: \(error.localizedDescription)")
        }
    }
    
    private func persistAnalyticsQueueToDefaults() {
        guard let data = try? JSONEncoder().encode(pendingAnalyticsEvents) else { return }
        Task { @MainActor in
            UserDefaults.stepsTrader().set(data, forKey: SharedKeys.analyticsEventsQueue)
        }
    }
    
}
