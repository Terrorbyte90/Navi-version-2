import Foundation
import Combine

// MARK: - Agent tools definition

let agentTools: [ClaudeTool] = [
    ClaudeTool(name: "read_file", description: "Läs innehållet i en fil",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Filsökväg")], required: ["path"])),
    ClaudeTool(name: "write_file", description: "Skriv/skapa en fil med innehåll",
               inputSchema: ToolInputSchema(properties: [
                   "path": ToolProperty(type: "string", description: "Filsökväg"),
                   "content": ToolProperty(type: "string", description: "Filinnehåll")
               ], required: ["path", "content"])),
    ClaudeTool(name: "move_file", description: "Flytta eller döp om en fil/mapp",
               inputSchema: ToolInputSchema(properties: [
                   "from": ToolProperty(type: "string", description: "Källsökväg"),
                   "to": ToolProperty(type: "string", description: "Målsökväg")
               ], required: ["from", "to"])),
    ClaudeTool(name: "delete_file", description: "Ta bort en fil eller mapp",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Sökväg att ta bort")], required: ["path"])),
    ClaudeTool(name: "create_directory", description: "Skapa en mapp",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Mappsökväg")], required: ["path"])),
    ClaudeTool(name: "list_directory", description: "Lista innehållet i en katalog",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Katalogsökväg")], required: ["path"])),
    ClaudeTool(name: "run_command", description: "Kör ett terminalkommando (macOS)",
               inputSchema: ToolInputSchema(properties: ["cmd": ToolProperty(type: "string", description: "Kommandot att köra")], required: ["cmd"])),
    ClaudeTool(name: "search_files", description: "Sök i alla filer i projektet",
               inputSchema: ToolInputSchema(properties: ["query": ToolProperty(type: "string", description: "Sökterm")], required: ["query"])),
    ClaudeTool(name: "get_api_key", description: "Hämta API-nyckel från keychain",
               inputSchema: ToolInputSchema(properties: ["service": ToolProperty(type: "string", description: "Tjänstens namn")], required: ["service"])),
    ClaudeTool(name: "build_project", description: "Bygg ett Xcode-projekt",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Sökväg till .xcodeproj eller Package.swift")], required: ["path"])),
    ClaudeTool(name: "download_file", description: "Ladda ned en fil",
               inputSchema: ToolInputSchema(properties: [
                   "url": ToolProperty(type: "string", description: "URL att ladda ned"),
                   "destination": ToolProperty(type: "string", description: "Lokal målsökväg")
               ], required: ["url", "destination"])),
    ClaudeTool(name: "zip_files", description: "Skapa en zip-fil",
               inputSchema: ToolInputSchema(properties: [
                   "source": ToolProperty(type: "string", description: "Källsökväg"),
                   "destination": ToolProperty(type: "string", description: "Mål zip-fil")
               ], required: ["source", "destination"]))
]

// MARK: - Agent Engine

@MainActor
final class AgentEngine: ObservableObject {
    static let shared = AgentEngine()

    @Published var currentTask: AgentTask?
    @Published var isRunning = false
    @Published var statusMessage = ""
    @Published var streamingText = ""

    private let claude = ClaudeAPIClient.shared
    private let checkpoint = CheckpointManager.shared
    private var cancellable: AnyCancellable?
    private var currentProject: EonProject?

    // Tool executor — platform-specific
    private let toolExecutor = ToolExecutor()

    func setProject(_ project: EonProject) {
        currentProject = project
    }

    // MARK: - Run agent task

    func run(
        task: AgentTask,
        conversation: inout Conversation,
        onUpdate: @escaping (String) -> Void
    ) async {
        guard !isRunning else { return }
        isRunning = true
        currentTask = task
        defer {
            isRunning = false
            currentTask = nil
        }

        var task = task
        task.status = .running
        task.startedAt = Date()

        statusMessage = "Planerar uppgift..."

        // Build initial messages
        var messages = conversation.messages
        messages.append(ChatMessage(
            role: .user,
            content: [.text(task.instruction)]
        ))

        var iterationCount = 0
        let maxIterations = 50 // Safety limit

        while iterationCount < maxIterations {
            iterationCount += 1
            streamingText = ""

            var fullText = ""
            var toolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []
            var currentToolID = ""
            var currentToolName = ""
            var currentToolJSON = ""
            var blockType = ""
            var stopReason = ""
            var inputTokens = 0
            var outputTokens = 0

            do {
                try await claude.streamMessage(
                    messages: messages,
                    model: currentProject?.activeModel ?? .haiku,
                    systemPrompt: MessageBuilder.agentSystemPrompt(for: currentProject),
                    tools: agentTools,
                    maxTokens: Constants.Agent.maxTokensLarge,
                    usePromptCaching: true,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleStreamEvent(
                                event,
                                fullText: &fullText,
                                toolCalls: &toolCalls,
                                currentToolID: &currentToolID,
                                currentToolName: &currentToolName,
                                currentToolJSON: &currentToolJSON,
                                blockType: &blockType,
                                stopReason: &stopReason,
                                inputTokens: &inputTokens,
                                outputTokens: &outputTokens
                            )
                            self?.streamingText = fullText
                        }
                    }
                )
            } catch {
                onUpdate("❌ Fel: \(error.localizedDescription)")
                task.status = .failed
                task.error = error.localizedDescription
                break
            }

            // Add assistant message
            var assistantContent: [MessageContent] = []
            if !fullText.isEmpty {
                assistantContent.append(.text(fullText))
            }
            for tool in toolCalls {
                assistantContent.append(.toolUse(id: tool.id, name: tool.name, input: tool.input))
            }

            let assistantMsg = ChatMessage(
                role: .assistant,
                content: assistantContent,
                model: currentProject?.activeModel
            )
            messages.append(assistantMsg)

            if !fullText.isEmpty {
                onUpdate(fullText)
            }

            // Save checkpoint
            checkpoint.save(taskID: task.id, step: iterationCount, data: ["messages": messages.count])

            // If no tool calls or stop reason is end_turn, we're done
            if toolCalls.isEmpty || stopReason == "end_turn" {
                task.status = .completed
                task.completedAt = Date()
                break
            }

            // Execute tool calls
            statusMessage = "Exekverar verktyg..."
            var toolResults: [MessageContent] = []

            for toolCall in toolCalls {
                let params = toolCall.input.mapValues { $0.value }
                let result = await toolExecutor.execute(
                    name: toolCall.name,
                    params: params as? [String: String] ?? [:],
                    projectRoot: currentProject?.resolvedURL
                )
                onUpdate("🔧 \(toolCall.name): \(result.prefix(200))")
                toolResults.append(.toolResult(id: toolCall.id, content: result, isError: false))
            }

            let toolResultMsg = ChatMessage(role: .user, content: toolResults)
            messages.append(toolResultMsg)
        }

        // Final update
        streamingText = ""
        if task.status == .completed {
            statusMessage = "Uppgift klar ✓"
        }
    }

    // MARK: - Stream event handler

    private func handleStreamEvent(
        _ event: StreamEvent,
        fullText: inout String,
        toolCalls: inout [(id: String, name: String, input: [String: AnyCodable])],
        currentToolID: inout String,
        currentToolName: inout String,
        currentToolJSON: inout String,
        blockType: inout String,
        stopReason: inout String,
        inputTokens: inout Int,
        outputTokens: inout Int
    ) {
        switch event {
        case .contentBlockStart(_, let type, let id, let name):
            blockType = type
            if type == "tool_use", let id = id, let name = name {
                currentToolID = id
                currentToolName = name
                currentToolJSON = ""
            }
        case .contentBlockDelta(_, let delta):
            switch delta {
            case .text(let t):
                fullText += t
            case .inputJSON(let j):
                currentToolJSON += j
            }
        case .contentBlockStop(_):
            if blockType == "tool_use" && !currentToolID.isEmpty {
                let input = parseToolInput(currentToolJSON)
                toolCalls.append((id: currentToolID, name: currentToolName, input: input))
                currentToolID = ""
                currentToolName = ""
                currentToolJSON = ""
            }
            blockType = ""
        case .messageDelta(let reason, let usage):
            if let reason = reason { stopReason = reason }
            if let usage = usage { outputTokens = usage.outputTokens }
        case .messageStart(_, _):
            break
        case .messageStop:
            break
        case .error(let msg):
            fullText += "\n[Stream Error: \(msg)]"
        case .ping:
            break
        }
    }

    private func parseToolInput(_ json: String) -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict.mapValues { AnyCodable($0) }
    }

    // MARK: - Simple chat (non-agent)

    func sendChat(
        userText: String,
        images: [Data] = [],
        conversation: inout Conversation,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (TokenUsage) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        var content: [MessageContent] = []
        for img in images {
            content.append(.image(img, mimeType: "image/jpeg"))
        }
        content.append(.text(userText))

        let userMsg = ChatMessage(role: .user, content: content)
        conversation.addMessage(userMsg)

        var fullText = ""
        var finalUsage: TokenUsage?
        var inputTokens = 0

        do {
            try await claude.streamMessage(
                messages: conversation.messages,
                model: conversation.model,
                systemPrompt: conversation.systemPrompt ?? MessageBuilder.agentSystemPrompt(for: currentProject),
                onEvent: { event in
                    Task { @MainActor in
                        switch event {
                        case .contentBlockDelta(_, let delta):
                            if case .text(let t) = delta {
                                fullText += t
                                onToken(t)
                            }
                        case .messageDelta(_, let usage):
                            if let u = usage {
                                finalUsage = u
                                outputTokens = u.outputTokens
                            }
                        case .messageStart(_, _):
                            break
                        default: break
                        }
                    }
                }
            )
        } catch {
            onError(error)
            return
        }

        let usage = finalUsage ?? TokenUsage(inputTokens: inputTokens, outputTokens: 0, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
        let (_, costSEK) = CostCalculator.shared.calculate(usage: usage, model: conversation.model)

        var assistantMsg = ChatMessage(role: .assistant, content: [.text(fullText)], model: conversation.model)
        assistantMsg.inputTokens = usage.inputTokens
        assistantMsg.outputTokens = usage.outputTokens
        assistantMsg.costSEK = costSEK
        conversation.addMessage(assistantMsg)
        conversation.updateCost(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, costSEK: costSEK)

        onComplete(usage)
    }
}

// Needed for capturing in closure
private var outputTokens = 0
