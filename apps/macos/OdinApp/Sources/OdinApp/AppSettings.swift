import Foundation
import AppKit

enum Provider: String, CaseIterable, Identifiable {
    case openrouter
    case bedrock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openrouter:
            return "OpenRouter"
        case .bedrock:
            return "Bedrock"
        }
    }
}

final class AppSettings: ObservableObject {
    private enum Defaults {
        static let openRouterModel = "google/gemini-2.0-flash-001"
        static let bedrockModel = "us.anthropic.claude-opus-4-7"
        static let legacyBedrockModel = "amazon.nova-lite-v1:0"
    }

    @Published var provider: Provider {
        didSet { save() }
    }
    @Published var model: String {
        didSet { save() }
    }
    @Published var awsRegion: String {
        didSet { save() }
    }
    @Published var pythonPath: String {
        didSet { save() }
    }
    @Published var repoPath: String {
        didSet { save() }
    }
    @Published var maxSteps: Int {
        didSet { save() }
    }
    @Published var maxBatchActions: Int {
        didSet { save() }
    }
    @Published var traceScreenshots: Bool {
        didSet { save() }
    }
    @Published var requireActionApproval: Bool {
        didSet { save() }
    }
    @Published var hotkeyKeyCode: Int {
        didSet { save() }
    }
    @Published var hotkeyModifiers: Int {
        didSet { save() }
    }
    @Published var customEnv: String {
        didSet { save() }
    }
    @Published var recentTasks: [String] = []
    @Published var pinnedTasks: [String] = []

    private let defaults = UserDefaults.standard
    private var cachedAPIKeys: [Provider: String] = [:]

    static let modelAliases: [String: String] = [
        "google/gemini-2.0-flash-001": "Gemini 2.0 Flash",
        "anthropic/claude-opus-4.7": "Claude 4.7 Opus",
        "anthropic/claude-sonnet-4.6": "Claude 4.6 Sonnet",
        "us.anthropic.claude-opus-4-7": "Claude 4.7 Opus",
        "us.anthropic.claude-sonnet-4-6": "Claude 4.6 Sonnet",
        "us.anthropic.claude-haiku-4-5": "Claude 4.5 Haiku",
        "deepseek/deepseek-v4-pro": "DeepSeek v4 Pro",
        "google/gemini-2.0-flash": "Gemini 2.0 Flash",
        "anthropic/claude-3-5-sonnet": "Claude 3.5 Sonnet",
        "anthropic/claude-3-5-sonnet-20241022": "Claude 3.5 Sonnet"
    ]

    var modelLabel: String {
        modelAlias
    }

    var modelAlias: String {
        alias(for: effectiveModel)
    }

    func alias(for modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        if let mapped = Self.modelAliases[trimmed] {
            return mapped
        }
        let lastComponent = trimmed.split(separator: "/").last ?? ""
        let cleaned = lastComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        return cleaned.capitalized
    }

    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        switch provider {
        case .openrouter:
            return Defaults.openRouterModel
        case .bedrock:
            return Defaults.bedrockModel
        }
    }

    init() {
        let defaultRepoPath = Self.defaultRepoPath()
        let providerValue = defaults.string(forKey: "provider") ?? Provider.openrouter.rawValue
        let resolvedProvider = Provider(rawValue: providerValue) ?? .openrouter
        provider = resolvedProvider
        let savedModel = defaults.string(forKey: "model") ?? ""
        if resolvedProvider == .bedrock && savedModel == Defaults.legacyBedrockModel {
            model = ""
            defaults.set("", forKey: "model")
        } else {
            model = savedModel
        }
        awsRegion = defaults.string(forKey: "awsRegion") ?? "us-east-1"
        repoPath = defaults.string(forKey: "repoPath") ?? defaultRepoPath
        pythonPath = defaults.string(forKey: "pythonPath") ?? Self.defaultPythonPath(repoPath: defaultRepoPath)
        maxSteps = max(1, defaults.integer(forKey: "maxSteps", defaultValue: 100))
        maxBatchActions = max(1, defaults.integer(forKey: "maxBatchActions", defaultValue: 5))
        traceScreenshots = defaults.object(forKey: "traceScreenshots") as? Bool ?? false
        requireActionApproval = defaults.object(forKey: "requireActionApproval") as? Bool ?? true
        hotkeyKeyCode = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? 49
        hotkeyModifiers = defaults.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.option.rawValue)
        customEnv = defaults.string(forKey: "customEnv") ?? ""
        recentTasks = defaults.stringArray(forKey: "recentTasks") ?? []
        pinnedTasks = defaults.stringArray(forKey: "pinnedTasks") ?? []
    }

    func addRecentTask(_ task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = recentTasks.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        if list.count > 12 { list = Array(list.prefix(12)) }
        recentTasks = list
        defaults.set(recentTasks, forKey: "recentTasks")
    }

    func togglePinned(_ task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if pinnedTasks.contains(trimmed) {
            pinnedTasks.removeAll { $0 == trimmed }
        } else {
            pinnedTasks.insert(trimmed, at: 0)
            if pinnedTasks.count > 8 {
                pinnedTasks = Array(pinnedTasks.prefix(8))
            }
        }
        defaults.set(pinnedTasks, forKey: "pinnedTasks")
    }

    func isPinned(_ task: String) -> Bool {
        pinnedTasks.contains(task.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func apiKey() -> String {
        if let cached = cachedAPIKeys[provider] {
            return cached
        }
        let key = KeychainStore.shared.read(service: "odin.\(provider.rawValue)", account: "api-key") ?? ""
        cachedAPIKeys[provider] = key
        return key
    }

    func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = "odin.\(provider.rawValue)"
        if trimmed.isEmpty {
            KeychainStore.shared.delete(service: service, account: "api-key")
            cachedAPIKeys[provider] = ""
        } else {
            KeychainStore.shared.write(trimmed, service: service, account: "api-key")
            cachedAPIKeys[provider] = trimmed
        }
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let sourcePath = URL(fileURLWithPath: repoPath).appendingPathComponent("src").path
        if let existing = env["PYTHONPATH"], !existing.isEmpty {
            env["PYTHONPATH"] = "\(sourcePath):\(existing)"
        } else {
            env["PYTHONPATH"] = sourcePath
        }

        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONIOENCODING"] = "utf-8"

        env["ODIN_LLM_PROVIDER"] = provider.rawValue
        env["AWS_REGION"] = awsRegion
        env["AWS_DEFAULT_REGION"] = awsRegion
        env["AWS_REGION_NAME"] = awsRegion

        let key = apiKey()
        if !key.isEmpty {
            if provider == .openrouter {
                env["OPENROUTER_API_KEY"] = key
            } else if provider == .bedrock {
                env["BEDROCK_API_KEY"] = key
            }
        }

        // AWS Bedrock Credentials
        let awsAccessKeyId = self.awsAccessKeyId()
        let awsSecretKey = self.awsSecretAccessKey()
        let awsSessionToken = self.awsSessionToken()

        if !awsAccessKeyId.isEmpty { env["AWS_ACCESS_KEY_ID"] = awsAccessKeyId }
        if !awsSecretKey.isEmpty { env["AWS_SECRET_ACCESS_KEY"] = awsSecretKey }
        if !awsSessionToken.isEmpty { env["AWS_SESSION_TOKEN"] = awsSessionToken }

        // Parse custom environment variables
        let lines = customEnv.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    env[k] = v
                }
            }
        }

        return env
    }

    func awsAccessKeyId() -> String {
        KeychainStore.shared.read(service: "odin.bedrock", account: "aws-access-key-id") ?? ""
    }

    func setAwsAccessKeyId(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.shared.delete(service: "odin.bedrock", account: "aws-access-key-id")
        } else {
            KeychainStore.shared.write(trimmed, service: "odin.bedrock", account: "aws-access-key-id")
        }
    }

    func awsSecretAccessKey() -> String {
        KeychainStore.shared.read(service: "odin.bedrock", account: "aws-secret-access-key") ?? ""
    }

    func setAwsSecretAccessKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.shared.delete(service: "odin.bedrock", account: "aws-secret-access-key")
        } else {
            KeychainStore.shared.write(trimmed, service: "odin.bedrock", account: "aws-secret-access-key")
        }
    }

    func awsSessionToken() -> String {
        KeychainStore.shared.read(service: "odin.bedrock", account: "aws-session-token") ?? ""
    }

    func setAwsSessionToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.shared.delete(service: "odin.bedrock", account: "aws-session-token")
        } else {
            KeychainStore.shared.write(trimmed, service: "odin.bedrock", account: "aws-session-token")
        }
    }

    struct ModelSuggestion: Identifiable {
        var id: String { modelID }
        let modelID: String
        let alias: String
    }

    var suggestedModels: [ModelSuggestion] {
        switch provider {
        case .openrouter:
            return [
                ModelSuggestion(modelID: "google/gemini-2.0-flash-001", alias: "Gemini 2.0 Flash"),
                ModelSuggestion(modelID: "anthropic/claude-opus-4.7", alias: "Claude 4.7 Opus"),
                ModelSuggestion(modelID: "anthropic/claude-sonnet-4.6", alias: "Claude 4.6 Sonnet")
            ]
        case .bedrock:
            return [
                ModelSuggestion(modelID: "us.anthropic.claude-opus-4-7", alias: "Claude 4.7 Opus"),
                ModelSuggestion(modelID: "us.anthropic.claude-sonnet-4-6", alias: "Claude 4.6 Sonnet"),
                ModelSuggestion(modelID: "us.anthropic.claude-haiku-4-5", alias: "Claude 4.5 Haiku")
            ]
        }
    }

    private func save() {
        defaults.set(provider.rawValue, forKey: "provider")
        defaults.set(model, forKey: "model")
        defaults.set(awsRegion, forKey: "awsRegion")
        defaults.set(pythonPath, forKey: "pythonPath")
        defaults.set(repoPath, forKey: "repoPath")
        defaults.set(maxSteps, forKey: "maxSteps")
        defaults.set(maxBatchActions, forKey: "maxBatchActions")
        defaults.set(traceScreenshots, forKey: "traceScreenshots")
        defaults.set(requireActionApproval, forKey: "requireActionApproval")
        defaults.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
        defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers")
        defaults.set(customEnv, forKey: "customEnv")
    }

    private static func defaultRepoPath() -> String {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd,
            cwd.appendingPathComponent("../../..").standardizedFileURL,
            cwd.appendingPathComponent("../../../..").standardizedFileURL
        ]

        for candidate in candidates {
            let odinPath = candidate.appendingPathComponent("src/odin").path
            if FileManager.default.fileExists(atPath: odinPath) {
                return candidate.path
            }
        }

        return cwd.path
    }

    private static func defaultPythonPath(repoPath: String) -> String {
        let venvPython = URL(fileURLWithPath: repoPath)
            .appendingPathComponent(".venv/bin/python3")
            .path
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return venvPython
        }
        return "/usr/bin/python3"
    }
}

private extension UserDefaults {
    func integer(forKey key: String, defaultValue: Int) -> Int {
        object(forKey: key) == nil ? defaultValue : integer(forKey: key)
    }
}
