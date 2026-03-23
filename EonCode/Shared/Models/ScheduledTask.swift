import Foundation

// MARK: - ScheduledTask

struct ScheduledTask: Codable, Identifiable {
    let id: UUID
    var title: String
    var notificationBody: String
    var scheduledDate: Date
    var isRecurring: Bool
    var recurringInterval: RecurringInterval?
    var notificationIdentifier: String
    var createdAt: Date
    var isCompleted: Bool

    init(
        title: String,
        notificationBody: String,
        scheduledDate: Date,
        isRecurring: Bool = false,
        recurringInterval: RecurringInterval? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notificationBody = notificationBody
        self.scheduledDate = scheduledDate
        self.isRecurring = isRecurring
        self.recurringInterval = recurringInterval
        self.notificationIdentifier = "scheduled-\(UUID().uuidString)"
        self.createdAt = Date()
        self.isCompleted = false
    }
}

enum RecurringInterval: String, Codable, CaseIterable {
    case daily   = "daily"
    case weekly  = "weekly"
    case workday = "workday"   // Mon–Fri

    var displayName: String {
        switch self {
        case .daily:   return "Varje dag"
        case .weekly:  return "Varje vecka"
        case .workday: return "Vardagar"
        }
    }

    var icon: String {
        switch self {
        case .daily:   return "sunrise"
        case .weekly:  return "calendar"
        case .workday: return "briefcase"
        }
    }
}
