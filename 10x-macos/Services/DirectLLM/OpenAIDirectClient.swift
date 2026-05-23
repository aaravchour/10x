import Foundation

actor OpenAIDirectClient: DirectLLMClient {
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
            "messages": DirectLLMHelpers.openAIMessages(system: system, messages: messages),
            "stream": true,
            "stream_options": ["include_usage": true]
        ]
        if maxTokens > 0 {
            body["max_tokens"] = maxTokens
        }
        if !tools.isEmpty {
            body["tools"] = DirectLLMHelpers.openAITools(from: tools)
            body["tool_choice"] = "auto"
        }

        let url = baseURL.appendingPathComponent("v1/chat/completions")
        let request = try DirectLLMHelpers.buildRequest(
            url: url,
            headers: ["Authorization": "Bearer \(apiKey)"],
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
            for try await line in bytes.lines { bodyText += line }
            throw GenerationError.apiError("HTTP \(httpResponse.statusCode): \(bodyText)")
        }

        return AsyncThrowingStream { continuation in
            Task {
                struct InFlightTool: Sendable {
                    var id: String = ""
                    var name: String = ""
                    var args: String = ""
                    var hasStarted: Bool = false
                }
                var inFlightTools: [Int: InFlightTool] = [:]
                var hasTextBlock = false

                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data: ") else { continue }
                        let dataContent = String(trimmed.dropFirst(6))
                        if dataContent == "[DONE]" { continue }

                        guard let data = dataContent.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first else { continue }

                        let delta = first["delta"] as? [String: Any] ?? [:]

                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for tc in toolCalls {
                                let index = tc["index"] as? Int ?? 0
                                if inFlightTools[index] == nil {
                                    inFlightTools[index] = InFlightTool()
                                }
                                var tool = inFlightTools[index]!
                                if let id = tc["id"] as? String, !id.isEmpty {
                                    tool.id = id
                                }
                                if let fn = tc["function"] as? [String: Any] {
                                    if let name = fn["name"] as? String, !name.isEmpty {
                                        tool.name = name
                                    }
                                    if let args = fn["arguments"] as? String {
                                        if !tool.hasStarted {
                                            tool.hasStarted = true
                                            continuation.yield(DirectLLMHelpers.contentBlockStart(
                                                type: "tool_use",
                                                id: tool.id,
                                                name: tool.name
                                            ))
                                        }
                                        tool.args += args
                                        continuation.yield(DirectLLMHelpers.inputJsonDeltaLine(args))
                                    }
                                }
                                inFlightTools[index] = tool
                            }
                        }

                        if let content = delta["content"] as? String, !content.isEmpty {
                            if !hasTextBlock {
                                hasTextBlock = true
                                continuation.yield(DirectLLMHelpers.contentBlockStart(type: "text"))
                            }
                            continuation.yield(DirectLLMHelpers.textDeltaLine(content))
                        }

                        let finishReason = first["finish_reason"] as? String
                        if finishReason != nil {
                            if hasTextBlock {
                                continuation.yield(DirectLLMHelpers.contentBlockStopLine())
                                hasTextBlock = false
                            }
                            for index in inFlightTools.keys.sorted() {
                                if let tool = inFlightTools[index], tool.hasStarted {
                                    continuation.yield(DirectLLMHelpers.contentBlockStopLine())
                                }
                            }
                            inFlightTools.removeAll()
                        }
                    }
                    if hasTextBlock {
                        continuation.yield(DirectLLMHelpers.contentBlockStopLine())
                    }
                    for index in inFlightTools.keys.sorted() {
                        if let tool = inFlightTools[index], tool.hasStarted {
                            continuation.yield(DirectLLMHelpers.contentBlockStopLine())
                        }
                    }
                    continuation.yield(DirectLLMHelpers.messageStopLine())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
