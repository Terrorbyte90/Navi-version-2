import Foundation

struct Conversation: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var title: String
    var messages: [ChatMessage]
    var createdAt: Date
    var modifiedAt: Date
    var model: ClaudeModel
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalCostSEK: Double
    var systemPrompt: String?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String = "Ny konversation",
        model: ClaudeModel = .haiku,
        systemPrompt: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.model = model
        self.totalInputTokens = 0
        self.totalOutputTokens = 0
        self.totalCostSEK = 0
        self.systemPrompt = systemPrompt
    }

    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        modifiedAt = Date()
        if title == "Ny konversation" && messages.count == 1 {
            // Auto-title from first user message
            let text = message.textContent
            title = String(text.prefix(50))
        }
    }

    mutating func updateCost(inputTokens: Int, outputTokens: Int, costSEK: Double) {
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        totalCostSEK += costSEK
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID
    var role: MessageRole
    var content: [MessageContent]
    var createdAt: Date
    var model: ClaudeModel?
    var inputTokens: Int
    var outputTokens: Int
    var costSEK: Double
    var isStreaming: Bool
    var error: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: [MessageContent],
        model: ClaudeModel? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.model = model
        self.inputTokens = 0
        self.outputTokens = 0
        self.costSEK = 0
        self.isStreaming = false
        self.error = nil
    }

    var textContent: String {
        content.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined()
    }

    var hasImages: Bool {
        content.contains { if case .image = $0 { return true }; return false }
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum MessageContent: Codable, Equatable {
    case text(String)
    case image(Data, mimeType: String)
    case toolUse(id: String, name: String, input: [String: AnyCodable])
    case toolResult(id: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, id, name, input, content, isError
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try container.encode("text", forKey: .type)
            try container.encode(t, forKey: .text)
        case .image(let data, let mime):
            try container.encode("image", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(mime, forKey: .mimeType)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let id, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(content, forKey: .content)
            try container.encode(isError, forKey: .isError)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            let b64 = try container.decode(String.self, forKey: .data)
            let mime = try container.decode(String.self, forKey: .mimeType)
            self = .image(Data(base64Encoded: b64) ?? Data(), mimeType: mime)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode([String: AnyCodable].self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        default:
            let id = try container.decode(String.self, forKey: .id)
            let content = try container.decode(String.self, forKey: .content)
            let isError = try container.decode(Bool.self, forKey: .isError)
            self = .toolResult(id: id, content: content, isError: isError)
        }
    }

    static func == (lhs: MessageContent, rhs: MessageContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)): return a == b
        default: return false
        }
    }
}

// Type-erased Codable for JSON dictionaries
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let string = try? container.decode(String.self) { value = string }
        else if let array = try? container.decode([AnyCodable].self) { value = array.map(\.value) }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict.mapValues(\.value) }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}
