import Foundation

// MARK: - Network Client
/// Centralized networking with retries, backoff, jitter, and connectivity handling.
final class NetworkClient: Sendable {
    static let shared = NetworkClient()
    
    struct RetryPolicy: Equatable {
        let maxRetries: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let jitterFraction: Double
        let retryableStatusCodes: Set<Int>
        let retryableURLErrorCodes: Set<URLError.Code>
        
        static let none = RetryPolicy(
            maxRetries: 0,
            baseDelay: 0,
            maxDelay: 0,
            jitterFraction: 0,
            retryableStatusCodes: [],
            retryableURLErrorCodes: []
        )
        
        static let `default` = RetryPolicy(
            maxRetries: 3,
            baseDelay: 0.5,
            maxDelay: 8.0,
            jitterFraction: 0.2,
            retryableStatusCodes: [408, 429, 500, 502, 503, 504],
            retryableURLErrorCodes: [
                .timedOut,
                .cannotConnectToHost,
                .networkConnectionLost,
                .dnsLookupFailed,
                .notConnectedToInternet,
                .internationalRoamingOff,
                .dataNotAllowed
            ]
        )
    }
    
    enum NetworkError: Error {
        case invalidResponse
        case transport(URLError)
        case other(Error)
    }
    
    private let session: URLSession
    
    init(session: URLSession = NetworkClient.makeDefaultSession()) {
        self.session = session
    }
    
    static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }
    
    func data(
        for request: URLRequest,
        policy: RetryPolicy = .default
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                if shouldRetry(statusCode: http.statusCode, policy: policy), attempt < policy.maxRetries {
                    let delay = backoffDelay(attempt: attempt, policy: policy)
                    attempt += 1
                    try await sleep(seconds: delay)
                    continue
                }
                
                return (data, http)
            } catch {
                if let urlError = error as? URLError {
                    if shouldRetry(urlError: urlError, policy: policy), attempt < policy.maxRetries {
                        let delay = backoffDelay(attempt: attempt, policy: policy)
                        attempt += 1
                        try await sleep(seconds: delay)
                        continue
                    }
                    throw NetworkError.transport(urlError)
                }
                
                if error is CancellationError { throw error }
                throw NetworkError.other(error)
            }
        }
    }
    
    func data(
        from url: URL,
        policy: RetryPolicy = .default
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await data(for: request, policy: policy)
    }
    
    // MARK: - Helpers
    private func shouldRetry(statusCode: Int, policy: RetryPolicy) -> Bool {
        policy.retryableStatusCodes.contains(statusCode)
    }
    
    private func shouldRetry(urlError: URLError, policy: RetryPolicy) -> Bool {
        policy.retryableURLErrorCodes.contains(urlError.code)
    }
    
    private func backoffDelay(attempt: Int, policy: RetryPolicy) -> TimeInterval {
        let base = policy.baseDelay * pow(2.0, Double(attempt))
        let capped = min(policy.maxDelay, base)
        let jitter = capped * policy.jitterFraction
        let randomized = capped + Double.random(in: -jitter...jitter)
        return max(0, randomized)
    }
    
    private func sleep(seconds: TimeInterval) async throws {
        let ns = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: ns)
    }
}

// MARK: - Shared Supabase Config

struct SupabaseConfig {
    let baseURL: URL
    let anonKey: String

    enum ConfigError: Error { case misconfigured }

    static func load() throws -> SupabaseConfig {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        guard let urlString, let anonKey, let url = URL(string: urlString), !anonKey.isEmpty else {
            AppLogger.network.error("SupabaseConfig: url=\(urlString ?? "nil"), anonKey=\(anonKey != nil ? "set" : "nil")")
            throw ConfigError.misconfigured
        }
        return SupabaseConfig(baseURL: url, anonKey: anonKey)
    }
}
