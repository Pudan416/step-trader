import Foundation

// MARK: - Network Client
/// Centralized networking with retries, backoff, jitter, and connectivity handling.
final class NetworkClient {
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
    
    enum FailureKind: Equatable {
        case retryableHTTP(Int)
        case nonRetryableHTTP(Int)
        case retryableTransport(URLError.Code)
        case nonRetryableTransport(URLError.Code)
        case invalidResponse
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
    
    func classifyFailure(statusCode: Int?, error: Error?, policy: RetryPolicy = .default) -> FailureKind {
        if let statusCode {
            if policy.retryableStatusCodes.contains(statusCode) {
                return .retryableHTTP(statusCode)
            }
            return .nonRetryableHTTP(statusCode)
        }
        if let urlError = error as? URLError {
            if policy.retryableURLErrorCodes.contains(urlError.code) {
                return .retryableTransport(urlError.code)
            }
            return .nonRetryableTransport(urlError.code)
        }
        return .invalidResponse
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
