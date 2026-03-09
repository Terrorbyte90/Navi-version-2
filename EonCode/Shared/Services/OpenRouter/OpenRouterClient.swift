import Foundation

// MARK: - OpenRouter API Client (OpenAI-compatible)

@MainActor
final class OpenRouterClient: ObservableObject {
    static let shared = OpenRouterClient()

    private let session = URLSession.shared

    private init() {}

    // MARK: - Auth

    private var apiKey: String? {
        KeychainManager.shared.openRouterAPIKey
    }

    private func authHeaders() throws -> [String: String] {
        guard let key = apiKey, !key.isEmpty else {
            throw OpenRouterError.noAPIKey
        }
        return [
            "Authorization": "Bearer \(key)",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://navi.app",
            "X-Title": "Navi"
        ]
    }

    // MARK: - Chat Completion (streaming, emits StreamEvent for ChatManager compat)

    func streamChatCompletion(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        let headers = try authHeaders()

        var apiMessages: [[String: Any]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            apiMessages.append(["role": "system", "content": sys])
        }
        for msg in messages {
            let role = msg.role == .user ? "user" : "assistant"
            let text = msg.content.compactMap { block -> String? in
                if case .text(let t) = block { return t }
                return nil
            }.joined()
            apiMessages.append(["role": role, "content": text])
        }

        let body: [String: Any] = [
            "model": model.rawValue,
            "messages": apiMessages,
            "max_tokens": maxTokens,
            "stream": true
        ]

        var request = URLRequest(url: URL(string: Constants.API.openRouterBaseURL)!)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        onEvent(.messageStart(id: UUID().uuidString, model: model.rawValue))

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResp = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard httpResp.statusCode == 200 else {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            throw OpenRouterError.apiError(httpResp.statusCode, errorBody)
        }

        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            guard data != "[DONE]" else { break }

            guard
                let jsonData = data.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            // Usage (may appear in last chunk)
            if let usage = json["usage"] as? [String: Any] {
                inputTokens = usage["prompt_tokens"] as? Int ?? 0
                outputTokens = usage["completion_tokens"] as? Int ?? 0
            }

            guard let choices = json["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                onEvent(.contentBlockDelta(index: 0, delta: .text(content)))
            }

            if let finishReason = choice["finish_reason"] as? String, finishReason == "stop" {
                break
            }
        }

        let usage = TokenUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationInputTokens: nil,
            cacheReadInputTokens: nil
        )
        onEvent(.messageDelta(stopReason: "end_turn", usage: usage))
        onEvent(.messageStop)
    }
}

enum OpenRouterError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Ingen OpenRouter API-nyckel hittad. Gå till Inställningar för att lägga till."
        case .invalidResponse:
            return "Ogiltigt svar från OpenRouter"
        case .apiError(let code, let msg):
            return "OpenRouter API-fel \(code): \(msg)"
        }
    }
}
