import Foundation
import Security

struct LLMConnectionTestResult: Sendable {
    let isSuccess: Bool
    let message: String
}

struct LLMModelFetchResult: Sendable {
    let models: [String]
    let message: String?
}

@Observable
@MainActor
final class LLMConnectionService {
    static let shared = LLMConnectionService()
    private nonisolated static let connectionsKey = "tenx.llm.connections"
    private nonisolated static let activeConnectionIDKey = "tenx.llm.activeConnectionID"
    private nonisolated static let keychainService = "app.10x.macos.llm-keys"

    var connections: [LLMConnection] = []
    var activeConnectionID: UUID? {
        didSet {
            if let id = activeConnectionID {
                UserDefaults.standard.set(id.uuidString, forKey: Self.activeConnectionIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeConnectionIDKey)
            }
        }
    }

    var activeConnection: LLMConnection? {
        guard let id = activeConnectionID else { return nil }
        return connections.first { $0.id == id && isUsable($0) }
    }

    var hasActiveDirectConnection: Bool {
        activeConnection != nil
    }

    init() {
        loadConnections()
    }

    // MARK: - CRUD

    func add(_ connection: LLMConnection) {
        var mutable = connection
        if !mutable.apiKey.isEmpty {
            Self.storeAPIKey(mutable.apiKey, for: mutable.id)
            mutable.apiKey = ""
        }
        connections.append(mutable)
        persist()
    }

    func update(_ connection: LLMConnection) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        var mutable = connection
        if !mutable.apiKey.isEmpty {
            Self.storeAPIKey(mutable.apiKey, for: mutable.id)
            mutable.apiKey = ""
        }
        connections[index] = mutable
        persist()
    }

    func delete(_ connection: LLMConnection) {
        connections.removeAll { $0.id == connection.id }
        Self.removeAPIKey(for: connection.id)
        if activeConnectionID == connection.id {
            activeConnectionID = nil
        }
        persist()
    }

    func setActive(_ connection: LLMConnection?) {
        activeConnectionID = connection?.id
    }

    func isUsable(_ connection: LLMConnection) -> Bool {
        guard connection.isEnabled else { return false }
        guard !connection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard URL(string: connection.effectiveBaseURL) != nil else { return false }
        return !connection.provider.requiresAPIKey || hasAPIKey(for: connection)
    }

    func hasAPIKey(for connection: LLMConnection) -> Bool {
        if !connection.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return !Self.apiKey(for: connection.id).isEmpty
    }

    func validationMessage(for connection: LLMConnection) -> String? {
        if !connection.isEnabled {
            return "Connection is disabled."
        }
        if connection.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Choose a model."
        }
        if URL(string: connection.effectiveBaseURL) == nil {
            return "Enter a valid base URL."
        }
        if connection.provider.requiresAPIKey && !hasAPIKey(for: connection) {
            return "Add an API key."
        }
        return nil
    }

    func test(_ connection: LLMConnection) async -> LLMConnectionTestResult {
        if let validation = validationMessage(for: connection) {
            return LLMConnectionTestResult(isSuccess: false, message: validation)
        }

        guard let url = testURL(for: connection) else {
            return LLMConnectionTestResult(isSuccess: false, message: "Enter a valid base URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        switch connection.provider {
        case .openai, .openrouter:
            request.setValue("Bearer \(apiKeyValue(for: connection))", forHTTPHeaderField: "Authorization")
        case .claude:
            request.setValue(apiKeyValue(for: connection), forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .ollama:
            let apiKey = apiKeyValue(for: connection)
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LLMConnectionTestResult(isSuccess: false, message: "Invalid response from provider.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = body?.isEmpty == false ? ": \(body!)" : ""
                return LLMConnectionTestResult(isSuccess: false, message: "HTTP \(http.statusCode)\(suffix)")
            }
            return LLMConnectionTestResult(isSuccess: true, message: "Connection works.")
        } catch {
            return LLMConnectionTestResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func fetchModels(for connection: LLMConnection) async -> LLMModelFetchResult {
        guard connection.provider == .ollama else {
            return LLMModelFetchResult(models: connection.provider.defaultModels, message: nil)
        }

        guard let url = testURL(for: connection) else {
            return LLMModelFetchResult(models: [], message: "Enter a valid Ollama host URL.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let apiKey = apiKeyValue(for: connection)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return LLMModelFetchResult(models: [], message: "Invalid response from Ollama.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return LLMModelFetchResult(models: [], message: "Ollama returned HTTP \(http.statusCode).")
            }
            let models = Self.parseOllamaModels(from: data)
            if models.isEmpty {
                return LLMModelFetchResult(models: [], message: "No local Ollama models found. Pull one with `ollama pull <model>`.")
            }
            return LLMModelFetchResult(models: models, message: nil)
        } catch {
            return LLMModelFetchResult(models: [], message: error.localizedDescription)
        }
    }

    nonisolated static func apiKey(for connectionID: UUID) -> String {
        Self.loadAPIKey(for: connectionID) ?? ""
    }

    // MARK: - Persistence

    private func persist() {
        let sanitized = connections.map { conn -> LLMConnection in
            var mutable = conn
            mutable.apiKey = ""
            return mutable
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: Self.connectionsKey)
        }
    }

    private func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: Self.connectionsKey),
              let decoded = try? JSONDecoder().decode([LLMConnection].self, from: data) else {
            return
        }
        connections = decoded
        if let activeIDString = UserDefaults.standard.string(forKey: Self.activeConnectionIDKey),
           let activeID = UUID(uuidString: activeIDString) {
            activeConnectionID = activeID
        }
    }

    private func testURL(for connection: LLMConnection) -> URL? {
        guard let base = URL(string: connection.effectiveBaseURL) else { return nil }
        switch connection.provider {
        case .openai, .openrouter:
            return base.appendingPathComponent("v1/models")
        case .claude:
            return base.appendingPathComponent("v1/models")
        case .ollama:
            return base.appendingPathComponent("api/tags")
        }
    }

    private func apiKeyValue(for connection: LLMConnection) -> String {
        let inlineKey = connection.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return inlineKey.isEmpty ? Self.apiKey(for: connection.id) : inlineKey
    }

    private nonisolated static func parseOllamaModels(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = json["models"] as? [[String: Any]] else {
            return []
        }

        let names = rawModels.compactMap { model in
            (model["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }

        return Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Keychain

    private nonisolated static func storeAPIKey(_ key: String, for connectionID: UUID) {
        guard !key.isEmpty else {
            Self.removeAPIKey(for: connectionID)
            return
        }
        let account = connectionID.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: key.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = key.data(using: .utf8)!
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private nonisolated static func loadAPIKey(for connectionID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private nonisolated static func removeAPIKey(for connectionID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: connectionID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
