import Foundation

// Self-healing build loop — wraps XcodeBuildManager for agent use
// This is primarily a macOS feature but the type is shared

struct SelfHealingResult {
    let succeeded: Bool
    let attempts: Int
    let finalOutput: String
    let errors: [String]
}

#if os(macOS)
@MainActor
final class SelfHealingLoop {
    static let shared = SelfHealingLoop()
    private init() {}

    func run(
        projectPath: String,
        projectID: UUID,
        maxAttempts: Int = Constants.Agent.maxBuildAttempts,
        onProgress: @escaping (String) -> Void
    ) async -> SelfHealingResult {
        var attempts = 0
        var lastOutput = ""
        var errors: [String] = []

        while attempts < maxAttempts {
            attempts += 1
            onProgress("🔨 Byggförsök \(attempts)/\(maxAttempts)…")

            let result = await XcodeBuildManager.shared.build(projectPath: projectPath)
            lastOutput = result.output

            if result.succeeded {
                onProgress("✅ Bygget lyckades efter \(attempts) försök")
                return SelfHealingResult(succeeded: true, attempts: attempts, finalOutput: lastOutput, errors: [])
            }

            errors = result.errors.map { $0.description }
            let errorList = errors.joined(separator: "\n")
            onProgress("❌ \(result.errorCount) fel hittade. Försöker fixa…")

            // Ask Claude to fix via agent
            let fixInstruction = """
            Xcode-bygget misslyckades med dessa fel. Fixa dem direkt i filerna:

            \(errorList)

            Projektets sökväg: \(projectPath)
            Analysera felen, läs relevanta filer, och skriv korrekta versioner.
            """

            var conv = Conversation(projectID: projectID, model: .haiku)
            let fixTask = AgentTask(projectID: projectID, instruction: fixInstruction)

            // Provide project context so the agent engine can resolve paths correctly
            if let project = ProjectStore.shared.project(by: projectID) {
                AgentEngine.shared.setProject(project)
            }

            await AgentEngine.shared.run(
                task: fixTask,
                conversation: &conv,
                onUpdate: { update in
                    onProgress("🔧 \(update.prefix(100))")
                }
            )

            // Save checkpoint
            CheckpointManager.shared.save(
                taskID: fixTask.id,
                step: attempts,
                data: ["phase": "self-healing", "errors": errors.count]
            )
        }

        return SelfHealingResult(
            succeeded: false,
            attempts: attempts,
            finalOutput: lastOutput,
            errors: errors
        )
    }
}
#endif
