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
