import Foundation

// MARK: - BrowserAction

enum BrowserAction {
    case navigate(url: String)
    case click(selector: String)
    case type(selector: String, text: String)
    case scroll(direction: String)
    case screenshot
    case waitForLoad
    case askUser(question: String)
    case goalComplete(summary: String)
    case goalFailed(reason: String)

    var logDescription: String {
        switch self {
        case .navigate(let url):         return "🌐 Navigerar till \(url)"
        case .click(let sel):            return "👆 Klickar på \(sel)"
        case .type(let sel, let text):   return "⌨️ Skriver '\(text.prefix(40))' i \(sel)"
        case .scroll(let dir):           return "📜 Scrollar \(dir)"
        case .screenshot:                return "📸 Tar skärmbild (vision-läge)"
        case .waitForLoad:               return "⏳ Väntar på att sidan laddas…"
        case .askUser(let q):            return "❓ Frågar användaren: \(q)"
        case .goalComplete(let sum):     return "✅ Klart! \(sum)"
        case .goalFailed(let r):         return "❌ Misslyckades: \(r)"
        }
    }
}

// MARK: - BrowserActionDecider

struct BrowserActionDecider {

    static let systemPrompt = """
    Du är en autonom webbläsaragent. Du surfar på webben för att uppnå användarens mål.

    Du får sidans innehåll som strukturerad text (titel, synlig text, länkar, input-fält, knappar).

    Svara ALLTID med exakt ett JSON-objekt och inget annat:

    {"action": "navigate", "url": "https://..."}
    {"action": "click", "selector": "CSS-selector eller länkindex [N]"}
    {"action": "type", "selector": "CSS-selector", "text": "text att skriva"}
    {"action": "scroll", "direction": "down"}
    {"action": "scroll", "direction": "up"}
    {"action": "screenshot"}
    {"action": "wait"}
    {"action": "ask_user", "question": "Fråga till användaren"}
    {"action": "goal_complete", "summary": "Sammanfattning av resultatet"}
    {"action": "goal_failed", "reason": "Varför det misslyckades"}

    Regler:
    - Tänk steg för steg — välj den mest logiska nästa actionen.
    - Om sidan har cookie-consent, klicka bort den direkt.
    - Om du ser CAPTCHA, använd ask_user.
    - Om sidan kräver inloggning och du inte har credentials, använd ask_user.
    - Prova text-extraktion först — använd 'screenshot' bara när text inte räcker.
    - Ge aldrig upp direkt. Försök minst 3 alternativa strategier innan goal_failed.
    - Klicka på rätt element med CSS-selector. Länkindex [N] fungerar med navigate.
    - Max 50 steg per uppgift.
    """

    static func decide(
        goal: String,
        pageContent: PageContent,
        history: [BrowserLogEntry],
        apiClient: ClaudeAPIClient
    ) async throws -> BrowserAction {
        let historyText = history.suffix(20)
            .map { $0.displayText }
            .joined(separator: "\n")

        let userMessage = """
        Mål: \(goal)

        Historik (senaste stegen):
        \(historyText.isEmpty ? "(inga steg ännu)" : historyText)

        Aktuell sida:
        \(pageContent.summary)

        Vad ska nästa steg vara?
        """

        let messages = [ChatMessage(role: .user, content: [.text(userMessage)])]
        let (response, _) = try await apiClient.sendMessage(
            messages: messages,
            model: .haiku,
            systemPrompt: systemPrompt,
            maxTokens: 256
        )

        return parseAction(from: response)
    }

    // MARK: - Parse JSON response

    static func parseAction(from text: String) -> BrowserAction {
        // Extract JSON object from response
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards) else {
            return .waitForLoad
        }
        let jsonStr = String(text[start.lowerBound...end.upperBound])
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            return .waitForLoad
        }

        switch action {
        case "navigate":
            return .navigate(url: (obj["url"] as? String) ?? "")
        case "click":
            return .click(selector: (obj["selector"] as? String) ?? "")
        case "type":
            return .type(
                selector: (obj["selector"] as? String) ?? "",
                text: (obj["text"] as? String) ?? ""
            )
        case "scroll":
            return .scroll(direction: (obj["direction"] as? String) ?? "down")
        case "screenshot":
            return .screenshot
        case "wait":
            return .waitForLoad
        case "ask_user":
            return .askUser(question: (obj["question"] as? String) ?? "Behöver din hjälp")
        case "goal_complete":
            return .goalComplete(summary: (obj["summary"] as? String) ?? "Uppgiften är klar")
        case "goal_failed":
            return .goalFailed(reason: (obj["reason"] as? String) ?? "Okänd anledning")
        default:
            return .waitForLoad
        }
    }
}
