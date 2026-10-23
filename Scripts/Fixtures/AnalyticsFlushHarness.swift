import Foundation

/*__PAYLOAD__*/
/*__ROW__*/

// Fixed public fixtures: no live auth, preferences, network or personal data.
struct SupabaseConfig {
    let baseURL = URL(string: "https://fixture.invalid")!
    let anonKey = "fixture-public-key"
    static func load() throws -> Self { Self() }
}
enum AnalyticsEventStage {
    static func forName(_ name: String) -> String { "product" }
}
enum AppLogger {
    static let network = Logger()
    struct Logger {
        func error(_ message: String) {}
        func debug(_ message: String) {}
    }
}
final class NetworkClient {
    enum RetryPolicy { case none }
    var existingEventIDs: Set<String> = ["already-sent"]
    var forcedStatus: Int?
    var throwsTransportError = false
    var requests: [URLRequest] = []

    func data(for request: URLRequest, policy: RetryPolicy) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if throwsTransportError { throw URLError(.networkConnectionLost) }
        let rows = try JSONDecoder().decode([AnalyticsEventInsertRow].self, from: request.httpBody!)
        precondition(rows.allSatisfy { $0.userId == "owner-a" }, "Foreign account event was uploaded")
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "authorization") == "Bearer fixture-token")
        precondition(request.value(forHTTPHeaderField: "prefer") == "return=minimal,resolution=ignore-duplicates")
        precondition(request.url!.path == "/rest/v1/user_analytics_events")
        let target = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "on_conflict" }?.value
        // PostgREST defaults to the generated numeric PK without on_conflict.
        let hasDuplicate = rows.contains { existingEventIDs.contains($0.eventId) }
        let status = forcedStatus ?? (hasDuplicate && target != "user_id,event_id" ? 409 : 201)
        if status < 400 { existingEventIDs.formUnion(rows.map(\.eventId)) }
        return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

actor SupabaseSyncService {
    let network = NetworkClient()
    var pendingAnalyticsEvents: [AnalyticsEventPayload] = []
    var persistenceWrites = 0
    func authenticatedContext() async -> (token: String, userId: String)? { ("fixture-token", "owner-a") }
    func iso8601String(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    func persistAnalyticsQueueToDefaults() { persistenceWrites += 1 }
    /*__FLUSH__*/

    func test(_ mode: String) async throws {
        func event(_ id: String, _ owner: String = "owner-a") -> AnalyticsEventPayload {
            .init(id: id, userId: owner, identityType: "anonymous", eventName: "fixture_event",
                  dayKey: "fixture-day", properties: [:], occurredAt: .distantPast,
                  eventStage: nil, schemaVersion: nil, appVersion: nil, appBuild: nil,
                  osVersion: nil, deviceModel: nil, sessionId: nil)
        }
        pendingAnalyticsEvents = [event("already-sent")]
        switch mode {
        case "mixed": pendingAnalyticsEvents.append(event("new-event"))
        case "ownership": pendingAnalyticsEvents.append(event("already-sent", "owner-b"))
        case "409", "403": network.forcedStatus = Int(mode)
        case "transport": network.throwsTransportError = true
        default: break
        }
        let original = pendingAnalyticsEvents
        await flushAnalyticsEvents()
        precondition(network.requests.count == 1)
        if ["409", "403", "transport"].contains(mode) {
            precondition(pendingAnalyticsEvents == original, "Failed upload lost durable events")
            precondition(persistenceWrites == 0)
        } else if mode == "ownership" {
            precondition(pendingAnalyticsEvents == [event("already-sent", "owner-b")])
        } else {
            precondition(pendingAnalyticsEvents.isEmpty, "Duplicate blocks successful queue drain")
            precondition(persistenceWrites == 1)
            if mode == "mixed" { precondition(network.existingEventIDs.contains("new-event")) }
            // A second pass with the same original payload is another replay.
            pendingAnalyticsEvents = original
            await flushAnalyticsEvents()
            precondition(pendingAnalyticsEvents.isEmpty)
        }
    }
}

@main struct Runner {
    static func main() async throws {
        try await SupabaseSyncService().test(CommandLine.arguments[1])
    }
}
