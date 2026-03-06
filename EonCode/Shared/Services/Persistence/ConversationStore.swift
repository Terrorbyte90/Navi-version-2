import Foundation

@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var conversations: [UUID: [Conversation]] = [:]  // projectID → conversations

    private let sync = iCloudSyncEngine.shared
    private init() {}

    // MARK: - Load for project

    func loadConversations(for projectID: UUID) async {
        guard let dir = sync.conversationsRoot else { return }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        var loaded: [Conversation] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let conversation = try? decoder.decode(Conversation.self, from: data),
                  conversation.projectID == projectID
            else { continue }
            loaded.append(conversation)
        }

        conversations[projectID] = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Save

    func save(_ conversation: Conversation) async {
        // Update in-memory
        var convs = conversations[conversation.projectID] ?? []
        if let idx = convs.firstIndex(where: { $0.id == conversation.id }) {
            convs[idx] = conversation
        } else {
            convs.insert(conversation, at: 0)
        }
        conversations[conversation.projectID] = convs

        // Save to iCloud
        if let url = sync.urlForConversation(conversation) {
            try? await sync.write(conversation, to: url)
        }
    }

    // MARK: - Delete

    func delete(_ conversation: Conversation) async {
        conversations[conversation.projectID]?.removeAll { $0.id == conversation.id }

        if let url = sync.urlForConversation(conversation) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func conversationsForProject(_ projectID: UUID) -> [Conversation] {
        conversations[projectID] ?? []
    }
}

// MARK: - Settings Store

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var defaultModel: ClaudeModel {
        didSet { save("defaultModel", value: defaultModel.rawValue) }
    }
    @Published var ttsEnabled: Bool {
        didSet { save("ttsEnabled", value: ttsEnabled) }
    }
    @Published var darkMode: Bool {
        didSet { save("darkMode", value: darkMode) }
    }
    @Published var autoSnapshot: Bool {
        didSet { save("autoSnapshot", value: autoSnapshot) }
    }
    @Published var agentConfirmDestructive: Bool {
        didSet { save("agentConfirmDestructive", value: agentConfirmDestructive) }
    }
    @Published var iCloudDefaultFolder: String? {
        didSet { save("iCloudDefaultFolder", value: iCloudDefaultFolder) }
    }
    @Published var macServerURL: String {
        didSet { save("macServerURL", value: macServerURL) }
    }
    @Published var iosAgentMode: AgentMode {
        didSet { save("iosAgentMode", value: iosAgentMode.rawValue) }
    }
    @Published var maxParallelWorkers: Int {
        didSet { save("maxParallelWorkers", value: maxParallelWorkers) }
    }
    @Published var parallelAgentsEnabled: Bool {
        didSet { save("parallelAgentsEnabled", value: parallelAgentsEnabled) }
    }
    @Published var autoGitHubSync: Bool {
        didSet { save("autoGitHubSync", value: autoGitHubSync) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaultModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "defaultModel") ?? "") ?? .haiku
        ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        darkMode = UserDefaults.standard.value(forKey: "darkMode") as? Bool ?? true
        autoSnapshot = UserDefaults.standard.value(forKey: "autoSnapshot") as? Bool ?? true
        agentConfirmDestructive = UserDefaults.standard.value(forKey: "agentConfirmDestructive") as? Bool ?? true
        iCloudDefaultFolder = UserDefaults.standard.string(forKey: "iCloudDefaultFolder")
        macServerURL = UserDefaults.standard.string(forKey: "macServerURL") ?? ""
        iosAgentMode = AgentMode(rawValue: UserDefaults.standard.string(forKey: "iosAgentMode") ?? "") ?? .autonomous
        maxParallelWorkers = UserDefaults.standard.integer(forKey: "maxParallelWorkers").nonZero ?? 4
        parallelAgentsEnabled = UserDefaults.standard.value(forKey: "parallelAgentsEnabled") as? Bool ?? true
        autoGitHubSync = UserDefaults.standard.value(forKey: "autoGitHubSync") as? Bool ?? false
    }

    private func save(_ key: String, value: Any?) {
        defaults.set(value, forKey: key)
    }
}
