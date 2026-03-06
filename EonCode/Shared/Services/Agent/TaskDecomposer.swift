import Foundation

// MARK: - TaskDecomposer
// Uses Claude to break a complex instruction into parallelizable waves of tasks.

final class TaskDecomposer {

    static func decompose(
        instruction: String,
        projectContext: String = "",
        model: ClaudeModel = .haiku
    ) async throws -> [TaskWave] {
        let prompt = buildPrompt(instruction: instruction, projectContext: projectContext)

        let (text, _) = try await ClaudeAPIClient.shared.sendMessage(
            messages: [ChatMessage(role: .user, content: [.text(prompt)])],
            model: model,
            systemPrompt: "Du är en uppgiftsplanerare. Returnera alltid giltig JSON och inget annat.",
            maxTokens: 3000
        )

        return parseWaves(from: text)
    }

    // MARK: - Heuristic: is this task complex enough to parallelize?

    static func shouldParallelize(instruction: String) -> Bool {
        let lower = instruction.lowercased()
        let complexKeywords = [
            "bygg en app", "skapa hela", "implementera", "refaktorera hela",
            "build an app", "create a full", "implement", "refactor all",
            "flera filer", "multiple files", "full stack", "komplett", "complete"
        ]
        return complexKeywords.contains { lower.contains($0) }
    }

    // MARK: - Prompt

    private static func buildPrompt(instruction: String, projectContext: String) -> String {
        """
        Bryt ner denna uppgift i parallelliserbara deluppgifter grupperade i vågor.

        Uppgift: \(instruction)
        \(projectContext.isEmpty ? "" : "Projektkontext:\n\(projectContext)")

        Regler:
        - Tasks i samma våg KAN köras parallellt (inga konflikter)
        - Task som beror på resultat från föregående våg läggs i nästa våg
        - Max 8 tasks per våg
        - requires_terminal: true om task behöver bash/xcodebuild/pip/npm
        - Var konkret — varje task ska vara tydligt avgränsad

        Svara ENBART med giltig JSON i detta format:
        {
          "waves": [
            {
              "index": 0,
              "description": "Grundstruktur",
              "tasks": [
                {
                  "id": "t1",
                  "description": "Skapa projektmappar",
                  "instruction": "Skapa mapparna Sources/, Tests/, Resources/",
                  "requires_terminal": false,
                  "depends_on": []
                }
              ]
            }
          ]
        }
        """
    }

    // MARK: - Parse JSON response

    private static func parseWaves(from text: String) -> [TaskWave] {
        // Extract JSON block
        let json: String
        if let start = text.range(of: "{"), let end = text.range(of: "}", options: .backwards) {
            json = String(text[start.lowerBound...end.upperBound])
        } else {
            return fallbackWave(text: text)
        }

        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wavesJSON = root["waves"] as? [[String: Any]]
        else { return fallbackWave(text: text) }

        return wavesJSON.compactMap { waveDict -> TaskWave? in
            guard let index = waveDict["index"] as? Int,
                  let description = waveDict["description"] as? String,
                  let tasksJSON = waveDict["tasks"] as? [[String: Any]]
            else { return nil }

            let tasks: [WorkerTask] = tasksJSON.compactMap { taskDict in
                guard let description = taskDict["description"] as? String,
                      let instruction = taskDict["instruction"] as? String
                else { return nil }

                let requiresTerminal = taskDict["requires_terminal"] as? Bool ?? false
                let dependsOnStrings = taskDict["depends_on"] as? [String] ?? []

                return WorkerTask(
                    description: description,
                    instruction: instruction,
                    requiresTerminal: requiresTerminal,
                    dependsOn: [],  // Simplified: wave ordering handles dependencies
                    waveIndex: index
                )
            }

            return TaskWave(
                index: index,
                description: description,
                tasks: tasks,
                dependsOnWave: waveDict["depends_on_wave"] as? Int
            )
        }
    }

    // If Claude response can't be parsed, run as single sequential task
    private static func fallbackWave(text: String) -> [TaskWave] {
        let task = WorkerTask(
            description: "Exekvera uppgift",
            instruction: text,
            requiresTerminal: false,
            dependsOn: [],
            waveIndex: 0
        )
        return [TaskWave(index: 0, description: "Exekvering", tasks: [task], dependsOnWave: nil)]
    }
}
