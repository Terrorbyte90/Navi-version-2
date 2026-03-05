import Foundation

final class CostCalculator {
    static let shared = CostCalculator()
    private init() {}

    func calculate(usage: TokenUsage, model: ClaudeModel) -> (usd: Double, sek: Double) {
        let inputPrice = model.inputPricePerMTok / 1_000_000
        let outputPrice = model.outputPricePerMTok / 1_000_000

        // Cache reads are cheaper (10% of normal)
        let cacheReadTokens = Double(usage.cacheReadInputTokens ?? 0)
        let normalInputTokens = Double(usage.inputTokens) - cacheReadTokens
        let outputTokens = Double(usage.outputTokens)

        let usd = (normalInputTokens * inputPrice)
                + (cacheReadTokens * inputPrice * 0.1)
                + (outputTokens * outputPrice)

        let sek = usd * ExchangeRateService.shared.usdToSEK
        return (usd, sek)
    }

    func formatSEK(_ amount: Double) -> String {
        if amount < 0.01 { return "< 0.01 SEK" }
        return String(format: "%.2f SEK", amount)
    }

    func formatUSD(_ amount: Double) -> String {
        if amount < 0.001 { return "< $0.001" }
        return String(format: "$%.4f", amount)
    }

    func costDescription(usage: TokenUsage, model: ClaudeModel) -> String {
        let (usd, sek) = calculate(usage: usage, model: model)
        return "\(formatSEK(sek)) · \(usage.inputTokens)→\(usage.outputTokens) tok"
    }
}

// MARK: - Message builder with context management

final class MessageBuilder {
    static func buildAPIMessages(
        from conversation: Conversation,
        projectContext: String? = nil,
        fileContents: [String: String] = [:]
    ) -> [ChatMessage] {
        var messages = conversation.messages

        // Inject file contents into context if available
        if !fileContents.isEmpty || projectContext != nil {
            var contextText = ""
            if let proj = projectContext {
                contextText += proj + "\n\n"
            }
            for (path, content) in fileContents {
                contextText += "=== \(path) ===\n\(content)\n\n"
            }
            if !contextText.isEmpty {
                // Prepend context to first user message or add system-like message
                if let firstIdx = messages.firstIndex(where: { $0.role == .user }) {
                    var first = messages[firstIdx]
                    var newContent = [MessageContent.text("[PROJEKT KONTEXT]\n\(contextText)\n[SLUT KONTEXT]\n\n")]
                    newContent.append(contentsOf: first.content)
                    first.content = newContent
                    messages[firstIdx] = first
                }
            }
        }

        return messages
    }

    static func agentSystemPrompt(for project: EonProject?) -> String {
        var prompt = """
        Du är EonCode-agenten — en kraftfull AI-kodningsassistent med fullständig tillgång till filsystem och terminalen.

        Tillgängliga verktyg:
        - read_file(path) — läs en fil
        - write_file(path, content) — skriv/skapa fil
        - move_file(from, to) — flytta/döp om fil
        - delete_file(path) — ta bort fil (kräver bekräftelse)
        - create_directory(path) — skapa mapp
        - list_directory(path) — lista kataloginnehåll
        - run_command(cmd) — kör terminalkommando
        - search_files(query) — sök i alla filer
        - get_api_key(service) — hämta API-nyckel från keychain
        - build_project(path) — bygg Xcode-projekt
        - download_file(url, destination) — ladda ned fil
        - zip_files(source, destination) — skapa zip-arkiv

        Regler:
        - Bekräfta alltid destruktiva operationer (rm -rf, sudo, format)
        - Logga varje steg som checkpoint
        - Vid fel: analysera → fixa → försök igen (max 20 iterationer)
        - Svar på svenska
        - Kod utan förklaringar om inget annat begärs
        - Rapportera kostnad efter varje svar
        - Använd caching för systemprompten och projektfiler
        """

        if let project = project {
            prompt += "\n\nAktivt projekt: \(project.name)\nSökväg: \(project.rootPath)"
        }

        return prompt
    }
}
