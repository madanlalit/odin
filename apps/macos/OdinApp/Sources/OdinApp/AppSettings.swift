import Foundation

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
    @Published var recentTasks: [String] = []
    @Published var pinnedTasks: [String] = []

    private let defaults = UserDefaults.standard

    var modelLabel: String {
        effectiveModel
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
        KeychainStore.shared.read(service: "odin.\(provider.rawValue)", account: "api-key") ?? ""
    }

    func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let service = "odin.\(provider.rawValue)"
        if trimmed.isEmpty {
            KeychainStore.shared.delete(service: service, account: "api-key")
        } else {
            KeychainStore.shared.write(trimmed, service: service, account: "api-key")
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
        if provider == .openrouter, !key.isEmpty {
            env["OPENROUTER_API_KEY"] = key
        }

        return env
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
