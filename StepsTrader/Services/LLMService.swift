import Foundation

// Lightweight DeepSeek chat wrapper for journal generation
final class LLMService {
    static let shared = LLMService()
    private init() {}

    // DOOM CTRL journal prompts (RU/EN) for control logs
    static let controlLogPromptRU = """
Ты — оператор журнала DOOM CTRL. Пиши коротко и по делу, 4–5 предложений.
Контекст:
- Шаги = заряд батареи.
- Щиты защищают вылазки (crawls) в приложения; уровни I–IV удешевляют вход.
- Crawls = открытия приложений.
- PayGate появляется, когда окно доступа закрыто.

Структура записи (русский):
1) Дата DD.MM.YYYY и “День N миссии”.
2) Батарея: сколько шагов получено, сколько потрачено, сколько осталось.
3) Щиты: список приложений с уровнем щита и числом вылазок.
4) События: показывался ли PayGate, были ли блокировки/неудачные вылазки.
Тон: техно-отчёт, без воды, без эмодзи.
"""

    static let controlLogPromptEN = """
You are the DOOM CTRL control log writer. Be concise, 4–5 sentences.
Context:
- Steps are battery charge.
- Shields protect crawls into apps; levels I–IV make entries cheaper.
- Crawls = app opens.
- PayGate appears when the access window is closed.

Log structure (English):
1) Date in DD.MM.YYYY and “Day N of the mission”.
2) Battery: steps gained, steps spent, charge left.
3) Shields: list apps with shield level and number of crawls.
4) Events: whether PayGate appeared, any blocked or failed crawls.
Tone: techno/ops report, no fluff, no emojis.
"""
    
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
    
    /// Generates a DOOM CTRL control journal entry based on day data.
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
                .init(role: "system", content: "You are the DOOM CTRL control log writer. Follow the structure provided in the user message. Respond in the same language as the user request. Keep it concise, 4–5 sentences, ops/tech tone, no emojis."),
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
