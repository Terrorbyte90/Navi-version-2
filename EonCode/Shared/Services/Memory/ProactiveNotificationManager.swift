import Foundation
import UserNotifications

// MARK: - ProactiveNotificationManager
// Scans user memories with Haiku (max once per 4 h) and schedules a proactive
// local notification when something actionable or time-sensitive is found.
// Cost-effective: single Haiku call, rate-limited, only fires when ≥3 memories exist.

@MainActor
final class ProactiveNotificationManager: ObservableObject {
    static let shared = ProactiveNotificationManager()

    /// Minimum seconds between proactive AI checks (4 hours)
    private let checkInterval: TimeInterval = 4 * 3600

    private let lastCheckKey = "proactiveNotifLastCheck"
    private let api = ClaudeAPIClient.shared

    private init() {}

    // MARK: - Request permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Check and notify

    /// Call from app-foreground transitions. Rate-limited to once per 4 h.
    func checkAndNotify() async {
        // Rate-limit guard
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        guard now - last >= checkInterval else { return }

        // Need at least 3 memories for meaningful context
        let memories = MemoryManager.shared.memories
        guard memories.count >= 3 else { return }

        // Need Anthropic key
        guard KeychainManager.shared.anthropicAPIKey?.isEmpty == false else { return }

        // Sample up to 20 most recent memories
        let facts = memories.suffix(20).map { "- \($0.fact)" }.joined(separator: "\n")
        let today = Date().formatted(date: .abbreviated, time: .omitted)

        let prompt = """
        Baserat på dessa kända fakta om användaren, föreslå EN enda kort och konkret notis som vore genuint hjälpsam just nu (datum: \(today)).

        Krav:
        - Bara om något tydligt och relevant finns (deadline, pågående projekt, mål)
        - title: max 8 ord, body: max 18 ord, på svenska
        - Om inget relevant finns, returnera {"title": null}

        Kända fakta:
        \(facts)

        Returnera BARA JSON: {"title": "...", "body": "..."} eller {"title": null}
        """

        do {
            let (response, _) = try await api.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                model: .haiku,
                systemPrompt: "Returnera BARA giltig JSON. Inga förklaringar.",
                maxTokens: 80
            )
            if let notif = parseNotifJSON(response), let title = notif.title, !title.isEmpty {
                scheduleLocalNotification(title: title, body: notif.body ?? "")
                UserDefaults.standard.set(now, forKey: lastCheckKey)
                NaviLog.info("ProactiveNotif: schemalagt \"\\(title)\"")
            }
        } catch {
            // Silent fail — proactive notifications are best-effort
        }
    }

    // MARK: - Schedule

    private func scheduleLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Deliver 3 seconds after trigger (effectively immediate foreground → background)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(
            identifier: "proactive-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - JSON parse

    private struct NotifPayload: Decodable {
        let title: String?
        let body: String?
    }

    private func parseNotifJSON(_ text: String) -> NotifPayload? {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}") else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NotifPayload.self, from: data)
    }
}
