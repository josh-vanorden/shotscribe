import Foundation

/// Titles through an OpenAI-compatible chat endpoint — OpenAI, OpenRouter,
/// Gemini's compatible surface, LM Studio, Ollama's `/v1`, a team gateway.
/// One request shape covers them all: `POST {base}/chat/completions`. The key
/// comes from the Keychain and is optional, since a local server has none.
/// This is the only network code in ShotScribe, and it runs only when an
/// endpoint is the chosen titler.
public struct EndpointTitler: Titler {
    public enum Error: LocalizedError {
        case http(Int, String), badReply
        public var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "The endpoint answered \(code): \(body)"
            case .badReply:                 return "The endpoint’s reply had no message in it."
            }
        }
    }

    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public var timeout: TimeInterval

    public init(baseURL: URL, model: String, apiKey: String?, timeout: TimeInterval = 30) {
        self.baseURL = baseURL; self.model = model; self.apiKey = apiKey; self.timeout = timeout
    }

    public func title(forOCRText text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return "Screenshot" }
        return LabelCleaner.clean(try await complete(system: TitlerPrompt.system, text: trimmed))
    }

    public func labelling(forOCRText text: String, vocabulary: [String]) async throws -> Labelling {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= TitlerPrompt.minOCRChars else { return Labelling(title: "Screenshot") }
        guard !vocabulary.isEmpty else { return Labelling(title: try await title(forOCRText: trimmed)) }
        let raw = try await complete(system: TitlerPrompt.system(taggedFrom: vocabulary), text: trimmed)
        return ClaudeTitler.parseLabelling(raw, vocabulary: vocabulary)
    }

    public static func request(baseURL: URL, model: String, apiKey: String?, system: String, user: String,
                               timeout: TimeInterval = 30) -> URLRequest {
        var url = baseURL
        if !url.path.hasSuffix("/chat/completions") { url = url.appendingPathComponent("chat/completions") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "max_tokens": 60,
            "temperature": 0,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// `choices[0].message.content`, the one field every compatible server fills.
    public static func parse(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Error.badReply }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ephemeral on purpose: the request and reply are derived from screen
    /// text, so no cookie the server sets and no cached response may outlive
    /// the process on disk. TLS checking and proxies stay the system defaults.
    private static let session = URLSession(configuration: .ephemeral)

    private func complete(system: String, text: String) async throws -> String {
        let req = Self.request(baseURL: baseURL, model: model, apiKey: apiKey, system: system,
                               user: "OCR text:\n\(text)\n\nLabel:", timeout: timeout)
        let (data, response) = try await Self.session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw Error.http(http.statusCode, String(body.prefix(160)))
        }
        return try Self.parse(data)
    }
}
