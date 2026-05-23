import Foundation

enum LLMProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case openai = "OpenAI"
    case claude = "Claude"
    case ollama = "Ollama"
    case openrouter = "OpenRouter"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var defaultBaseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com"
        case .claude:
            return "https://api.anthropic.com"
        case .ollama:
            return "http://localhost:11434"
        case .openrouter:
            return "https://openrouter.ai/api"
        }
    }

    var apiKeyLabel: String {
        switch self {
        case .openai:
            return "OpenAI API Key"
        case .claude:
            return "Claude API Key"
        case .ollama:
            return "API Key (optional)"
        case .openrouter:
            return "OpenRouter API Key"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            return false
        case .openai, .claude, .openrouter:
            return true
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .openai:
            return "gpt-4o"
        case .claude:
            return "claude-sonnet-4-20250514"
        case .ollama:
            return "llama3.2"
        case .openrouter:
            return "anthropic/claude-sonnet-4"
        }
    }

    var setupHint: String {
        switch self {
        case .openai:
            return "Uses OpenAI's chat completions endpoint. Custom OpenAI-compatible gateways also work when the base URL points at the API root."
        case .claude:
            return "Uses Anthropic's Messages API and expects Anthropic-format model IDs."
        case .ollama:
            return "Runs against a local Ollama server. Start Ollama first and pull the model you enter here."
        case .openrouter:
            return "Uses OpenRouter's OpenAI-compatible endpoint. Model IDs usually include a provider prefix."
        }
    }

    var baseURLLabel: String {
        switch self {
        case .ollama:
            return "Ollama Host URL"
        default:
            return "Base URL (optional)"
        }
    }

    var supportsCustomModels: Bool {
        switch self {
        case .openai, .ollama, .openrouter:
            return true
        case .claude:
            return false
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openai:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "o3-mini",
                "o1"
            ]
        case .claude:
            return [
                "claude-sonnet-4-20250514",
                "claude-opus-4-20250514",
                "claude-3-7-sonnet-20250219",
                "claude-3-5-sonnet-20241022"
            ]
        case .ollama:
            return [
                "llama3.2",
                "llama3.1",
                "qwen2.5-coder",
                "mistral",
                "codellama"
            ]
        case .openrouter:
            return [
                "anthropic/claude-sonnet-4",
                "anthropic/claude-opus-4",
                "openai/gpt-4o",
                "deepseek/deepseek-chat",
                "google/gemini-2.5-pro-preview-03-25"
            ]
        }
    }

    var iconName: String {
        switch self {
        case .openai: "network"
        case .claude: "sparkles"
        case .ollama: "desktopcomputer"
        case .openrouter: "arrow.left.arrow.right"
        }
    }
}

struct LLMConnection: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var provider: LLMProvider
    var apiKey: String
    var baseURL: String
    var model: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        provider: LLMProvider = .openai,
        apiKey: String = "",
        baseURL: String = "",
        model: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.isEnabled = isEnabled
    }

    var displayName: String {
        name.isEmpty ? "\(provider.displayName) — \(model)" : name
    }

    var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultBaseURL : trimmed
    }

    var isValid: Bool {
        let hasModel = !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasModel && (!provider.requiresAPIKey || hasKey)
    }
}
