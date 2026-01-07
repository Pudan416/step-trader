import Foundation

// Lightweight DeepSeek chat wrapper for journal generation
final class LLMService {
    static let shared = LLMService()
    private init() {}
    
    private enum LLMError: Error {
        case missingAPIKey
        case badResponse
        case decodingFailed
    }
    
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        
        struct Message: Encodable {
            let role: String
            let content: String
        }
    }
    
    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
    
    /// Generates a cosmic pilot journal entry based on day data.
    func generateCosmicJournal(prompt: String) async throws -> String {
        guard let apiKey = Self.loadAPIKey(), !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)
        
        guard let url = URL(string: "https://api.deepseek.com/v1/chat/completions") else {
            throw LLMError.badResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body = ChatRequest(
            model: "deepseek-chat",
            messages: [
                .init(role: "system", content: "You are a witty space ship pilot writing a daily journal of your travels across universes. The steps are fuel, the app opens are jumping into black holes and wormholes. To get out of these holes, you use special modules attached to each app. Start with the current date in the format DD.MM.YYYY. Next write the number of the day you spend in this flight. In the text, mention which modules were used that day and how much fuel was spent on them. Mention just names of apps, not URD schemes. If unlimited access was used, mention that too. Be curious, calm, and modest like a scientist. Write a brief diary-style text in Russian that is warm and imaginative. It should be 4-5 sentences long."),
                .init(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if let http = response as? HTTPURLResponse {
                let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "n/a"
                print("❌ LLM bad response: status=\(http.statusCode) body=\(bodyPreview)")
            }
            throw LLMError.badResponse
        }
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            print("❌ LLM decoding failed")
            throw LLMError.decodingFailed
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Reads API key from UserDefaults (stepsTrader group) or Info.plist key DEEPSEEK_API_KEY.
    private static func loadAPIKey() -> String? {
        let defaultsKey = UserDefaults.stepsTrader().string(forKey: "deepseek_api_key")
        let plistKey = Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_API_KEY") as? String
        return defaultsKey?.isEmpty == false ? defaultsKey : (plistKey?.isEmpty == false ? plistKey : nil)
    }
}
