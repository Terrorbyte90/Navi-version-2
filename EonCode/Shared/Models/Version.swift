import Foundation

struct ProjectVersion: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var name: String
    var createdAt: Date
    var branch: String
    var parentVersionID: UUID?
    var filesChanged: [String]
    var diffs: [String: FileDiff]
    var snapshotPath: String?    // Relative path in iCloud
    var isAutoSnapshot: Bool
    var description: String
    var author: String           // Device that created this

    init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String? = nil,
        branch: String = "main",
        parentVersionID: UUID? = nil,
        filesChanged: [String] = [],
        isAutoSnapshot: Bool = true
    ) {
        self.id = id
        self.projectID = projectID
        let ts = ISO8601DateFormatter().string(from: Date())
        self.name = name ?? "snapshot-\(ts)"
        self.createdAt = Date()
        self.branch = branch
        self.parentVersionID = parentVersionID
        self.filesChanged = filesChanged
        self.diffs = [:]
        self.isAutoSnapshot = isAutoSnapshot
        self.description = ""
        self.author = UIDevice.deviceName
    }

    var displayName: String {
        isAutoSnapshot ? "Auto · \(formattedDate)" : name
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM HH:mm"
        return f.string(from: createdAt)
    }

    static func == (lhs: ProjectVersion, rhs: ProjectVersion) -> Bool {
        lhs.id == rhs.id
    }
}

struct FileDiff: Codable, Equatable {
    var path: String
    var oldContent: String?
    var newContent: String?
    var hunks: [DiffHunk]
    var changeType: ChangeType

    enum ChangeType: String, Codable {
        case added, modified, deleted, renamed
    }
}

struct DiffHunk: Codable, Equatable {
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
    var lines: [DiffLine]
}

struct DiffLine: Codable, Equatable {
    var type: DiffLineType
    var content: String

    enum DiffLineType: String, Codable {
        case context, added, removed
    }
}

struct CostRecord: Identifiable, Codable {
    var id: UUID
    var date: Date
    var projectID: UUID?
    var conversationID: UUID?
    var model: ClaudeModel
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var costSEK: Double
    var exchangeRate: Double

    init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        conversationID: UUID? = nil,
        model: ClaudeModel,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        costSEK: Double,
        exchangeRate: Double
    ) {
        self.id = id
        self.date = Date()
        self.projectID = projectID
        self.conversationID = conversationID
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.costSEK = costSEK
        self.exchangeRate = exchangeRate
    }
}

struct APIKeyEntry: Identifiable, Codable {
    var id: UUID
    var service: String
    var displayName: String
    var hint: String       // Last 4 chars for display
    var addedAt: Date
    var lastUsed: Date?

    init(id: UUID = UUID(), service: String, displayName: String, keyValue: String) {
        self.id = id
        self.service = service
        self.displayName = displayName
        self.hint = String(keyValue.suffix(4))
        self.addedAt = Date()
    }
}
