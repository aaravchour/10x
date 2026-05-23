import Foundation

// MARK: - Protocol

protocol DirectLLMClient: Sendable {
    func stream(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int,
        onEvent: @escaping @MainActor @Sendable (GenerationEvent) async -> Void
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Factory

enum DirectLLMClientFactory {
    static func client(for connection: LLMConnection) -> DirectLLMClient {
        let apiKey = LLMConnectionService.apiKey(for: connection.id)
        switch connection.provider {
        case .claude:
            return ClaudeDirectClient(connection: connection, apiKey: apiKey)
        case .openai:
            return OpenAIDirectClient(connection: connection, apiKey: apiKey)
        case .ollama:
            return OllamaDirectClient(connection: connection, apiKey: apiKey)
        case .openrouter:
            return OpenRouterDirectClient(connection: connection, apiKey: apiKey)
        }
    }
}

// MARK: - Shared Helpers

enum DirectLLMHelpers {
    static func anthropicStreamSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 1800
        return URLSession(configuration: config)
    }

    static func buildRequest(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    static func makeBaseURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw GenerationError.apiError("Invalid base URL: \(string)")
        }
        return url
    }

    static func openAITools(from tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            if (tool["type"] as? String) == "function",
               tool["function"] is [String: Any] {
                return tool
            }

            guard let name = tool["name"] as? String else {
                return nil
            }

            var function: [String: Any] = [
                "name": name,
                "parameters": tool["input_schema"] as? [String: Any] ?? [
                    "type": "object",
                    "properties": [:]
                ]
            ]

            if let description = tool["description"] as? String {
                function["description"] = description
            }

            return [
                "type": "function",
                "function": function
            ]
        }
    }

    static func openAIMessages(system: String, messages: [[String: Any]]) -> [[String: Any]] {
        var converted: [[String: Any]] = [
            ["role": "system", "content": system]
        ]

        for message in messages {
            let role = message["role"] as? String ?? "user"
            guard let content = message["content"] else {
                converted.append(message)
                continue
            }

            if let text = content as? String {
                converted.append(["role": role, "content": text])
                continue
            }

            guard let blocks = content as? [[String: Any]] else {
                converted.append(message)
                continue
            }

            switch role {
            case "assistant":
                let text = textContent(from: blocks)
                let toolCalls = blocks.compactMap(openAIToolCall(from:))
                var assistantMessage: [String: Any] = ["role": "assistant"]
                assistantMessage["content"] = text.isEmpty ? NSNull() : text
                if !toolCalls.isEmpty {
                    assistantMessage["tool_calls"] = toolCalls
                }
                converted.append(assistantMessage)

            case "user":
                let textBlocks = blocks.filter { ($0["type"] as? String) != "tool_result" }
                let text = textContent(from: textBlocks)
                if !text.isEmpty {
                    converted.append(["role": "user", "content": text])
                }

                for block in blocks where (block["type"] as? String) == "tool_result" {
                    converted.append(openAIToolResultMessage(from: block))
                }

            default:
                let text = textContent(from: blocks)
                converted.append(["role": role, "content": text])
            }
        }

        return converted
    }

    private static func openAIToolCall(from block: [String: Any]) -> [String: Any]? {
        guard (block["type"] as? String) == "tool_use",
              let name = block["name"] as? String else {
            return nil
        }

        let id = (block["id"] as? String)?.isEmpty == false ? block["id"] as! String : "call_\(UUID().uuidString)"
        let arguments = jsonString(block["input"] ?? [:])

        return [
            "id": id,
            "type": "function",
            "function": [
                "name": name,
                "arguments": arguments
            ]
        ]
    }

    private static func openAIToolResultMessage(from block: [String: Any]) -> [String: Any] {
        let id = block["tool_use_id"] as? String ?? ""
        return [
            "role": "tool",
            "tool_call_id": id,
            "content": toolResultContent(from: block["content"])
        ]
    }

    private static func textContent(from blocks: [[String: Any]]) -> String {
        blocks.compactMap { block in
            guard (block["type"] as? String) == "text" else { return nil }
            return block["text"] as? String
        }
        .joined(separator: "\n")
    }

    private static func toolResultContent(from content: Any?) -> String {
        if let text = content as? String {
            return text
        }
        if let blocks = content as? [[String: Any]] {
            let text = textContent(from: blocks)
            return text.isEmpty ? jsonString(blocks) : text
        }
        if let content {
            return jsonString(content)
        }
        return ""
    }

    private static func jsonString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    // MARK: - Anthropic-format NDJSON lines

    static func messageStartLine() -> String {
        jsonLine(["type": "message_start"])
    }

    static func contentBlockStart(type: String, id: String? = nil, name: String? = nil) -> String {
        var block: [String: Any] = ["type": type]
        if let id { block["id"] = id }
        if let name { block["name"] = name }
        return jsonLine(["type": "content_block_start", "content_block": block])
    }

    static func textDeltaLine(_ text: String) -> String {
        jsonLine([
            "type": "content_block_delta",
            "delta": ["type": "text_delta", "text": text]
        ])
    }

    static func inputJsonDeltaLine(_ partial: String) -> String {
        jsonLine([
            "type": "content_block_delta",
            "delta": ["type": "input_json_delta", "partial_json": partial]
        ])
    }

    static func contentBlockStopLine() -> String {
        jsonLine(["type": "content_block_stop"])
    }

    static func messageStopLine() -> String {
        jsonLine(["type": "message_stop"])
    }

    static func errorLine(_ message: String) -> String {
        jsonLine(["type": "error", "message": message])
    }

    private static func jsonLine(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
