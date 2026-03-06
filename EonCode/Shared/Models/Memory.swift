import Foundation

struct Memory: Codable, Identifiable {
    let id: UUID
    var fact: String
    var category: MemoryCategory
    let createdAt: Date
    var source: MemorySource

    init(fact: String, category: MemoryCategory, source: MemorySource) {
        self.id = UUID()
        self.fact = fact
        self.category = category
        self.createdAt = Date()
        self.source = source
    }
}

enum MemoryCategory: String, Codable, CaseIterable {
    case personal    = "personal"
    case preference  = "preference"
    case project     = "project"
    case technical   = "technical"
    case other       = "other"

    var icon: String {
        switch self {
        case .personal:   return "person"
        case .preference: return "heart"
        case .project:    return "folder"
        case .technical:  return "wrench"
        case .other:      return "lightbulb"
        }
    }

    var displayName: String {
        switch self {
        case .personal:   return "Personligt"
        case .preference: return "Preferenser"
        case .project:    return "Projekt"
        case .technical:  return "Tekniskt"
        case .other:      return "Övrigt"
        }
    }
}

enum MemorySource: Codable {
    case extracted(conversationId: UUID)
    case manual
}
