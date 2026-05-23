import Foundation

actor ClaudeDirectClient: DirectLLMClient {
    private let connection: LLMConnection
    private let apiKey: String
    private let baseURL: URL

    init(connection: LLMConnection, apiKey: String) {
        self.connection = connection
        self.apiKey = apiKey
        self.baseURL = URL(string: connection.effectiveBaseURL)!
    }

    func stream(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int,
        onEvent: @escaping @MainActor @Sendable (GenerationEvent) async -> Void
    ) async throws -> AsyncThrowingStream<String, Error> {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "stream": true
        ]
        if !tools.isEmpty {
            body["tools"] = tools
        }

        let url = baseURL.appendingPathComponent("v1/messages")
        let request = try DirectLLMHelpers.buildRequest(
            url: url,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ],
            body: body
        )

        let (bytes, response) = try await DirectLLMHelpers.anthropicStreamSession().bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.apiError("Invalid response")
        }
        if httpResponse.statusCode == 401 {
            throw GenerationError.apiError("Invalid API key")
        }
        guard httpResponse.statusCode == 200 else {
            var bodyText = ""
            for try await line in bytes.lines {
                bodyText += line
            }
            throw GenerationError.apiError("HTTP \(httpResponse.statusCode): \(bodyText)")
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let dataContent = String(trimmed.dropFirst(6))
                        if dataContent == "[DONE]" { continue }
                        continuation.yield(dataContent)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
