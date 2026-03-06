import Foundation

// MARK: - TaskDecomposer
// Uses Claude to break a complex instruction into parallelizable waves of tasks.

final class TaskDecomposer {

    // MARK: - Decompose with Claude

    static func decompose(
        instruction: String,
        projectContext: String = "",
        model: ClaudeModel = .sonnet45
    ) async throws -> [TaskWave] {
        let prompt = buildPrompt(instruction: instruction, projectContext: projectContext)

        let (text, _) = try await ClaudeAPIClient.shared.sendMessage(
            messages: [ChatMessage(role: .user, content: [.text(prompt)])],
            model: model,
            systemPrompt: """
            Du är en expert på att planera och parallellisera kodningsuppgifter.
            Returnera ALLTID giltig JSON och inget annat — inga förklaringar, inga markdown-block.
            """,
            maxTokens: 4096
        )

        let waves = parseWaves(from: text)
        return waves.isEmpty ? fallbackWave(instruction: instruction) : waves
    }

    // MARK: - Heuristic: should this task be parallelized?

    @MainActor
    static func shouldParallelize(instruction: String) -> Bool {
        guard SettingsStore.shared.parallelAgentsEnabled else { return false }

        let lower = instruction.lowercased()

        // Explicit multi-file or multi-component signals
        let parallelSignals = [
            // Swedish
            "bygg en app", "skapa hela", "implementera", "refaktorera hela",
            "skapa ett", "bygg ett", "lägg till", "migrera", "konvertera",
            "flera filer", "alla filer", "hela projektet", "komplett",
            "full stack", "frontend och backend", "api och ui",
            "tester och implementation", "tester för",
            // English
            "build an app", "create a full", "implement", "refactor all",
            "multiple files", "entire project", "complete", "full stack",
            "add tests", "write tests", "migrate", "convert all",
        ]

        // Single-step signals — don't parallelize these
        let sequentialSignals = [
            "fixa", "fix", "ändra", "change", "uppdatera en", "update one",
            "läs", "read", "visa", "show", "förklara", "explain",
            "vad är", "what is", "hur fungerar", "how does"
        ]

        let hasParallelSignal = parallelSignals.contains { lower.contains($0) }
        let hasSequentialSignal = sequentialSignals.contains { lower.contains($0) }

        // Parallelize if: has parallel signal AND no sequential signal AND instruction is substantial
        return hasParallelSignal && !hasSequentialSignal && instruction.count > 50
    }

    // MARK: - Prompt

    private static func buildPrompt(instruction: String, projectContext: String) -> String {
        """
        Bryt ner denna uppgift i parallelliserbara deluppgifter grupperade i sekventiella vågor.

        UPPGIFT: \(instruction)
        \(projectContext.isEmpty ? "" : "\nPROJEKTKONTEXT:\n\(projectContext)\n")

        REGLER FÖR UPPDELNING:
        - Uppgifter i SAMMA våg kan köras parallellt (inga beroenden mellan dem)
        - Uppgifter som beror på resultat från föregående våg läggs i NÄSTA våg
        - Våg 0: Analys/planering (läs befintliga filer, förstå struktur)
        - Våg 1+: Implementation (skriv kod, skapa filer)
        - Sista vågen: Integration (bygg, testa, verifiera)
        - Max 6 uppgifter per våg
        - requires_terminal: true om uppgiften behöver bash/xcodebuild/npm/pip/git
        - Varje instruction ska vara konkret och självständig (worker ser bara sin egen uppgift)

        Svara ENBART med giltig JSON (inga markdown-block, inga förklaringar):
        {
          "waves": [
            {
              "index": 0,
              "description": "Analys och planering",
              "tasks": [
                {
                  "id": "t0_1",
                  "description": "Läs projektstruktur",
                  "instruction": "Lista och läs de viktigaste filerna i projektet för att förstå arkitekturen",
                  "requires_terminal": false,
                  "depends_on": []
                }
              ]
            },
            {
              "index": 1,
              "description": "Implementation",
              "tasks": [
                {
                  "id": "t1_1",
                  "description": "Skapa modell",
                  "instruction": "Skapa filen Models/User.swift med User-struct enligt specifikationen",
                  "requires_terminal": false,
                  "depends_on": ["t0_1"]
                },
                {
                  "id": "t1_2",
                  "description": "Skapa service",
                  "instruction": "Skapa filen Services/UserService.swift med CRUD-operationer",
                  "requires_terminal": false,
                  "depends_on": ["t0_1"]
                }
              ]
            }
          ]
        }
        """
    }

    // MARK: - Parse JSON response

    private static func parseWaves(from text: String) -> [TaskWave] {
        // Strip markdown code blocks if present
        var cleaned = text
        if cleaned.contains("```json") {
            cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        }

        // Extract outermost JSON object
        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}") else {
            return []
        }
        let jsonStr = String(cleaned[startIdx...endIdx])

        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wavesJSON = root["waves"] as? [[String: Any]]
        else { return [] }

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

                return WorkerTask(
                    description: description,
                    instruction: instruction,
                    requiresTerminal: requiresTerminal,
                    dependsOn: [],
                    waveIndex: index
                )
            }

            guard !tasks.isEmpty else { return nil }

            return TaskWave(
                index: index,
                description: description,
                tasks: tasks,
                dependsOnWave: waveDict["depends_on_wave"] as? Int
            )
        }
    }

    // MARK: - Fallback: run as single sequential task

    private static func fallbackWave(instruction: String) -> [TaskWave] {
        let task = WorkerTask(
            description: "Exekvera uppgift",
            instruction: instruction,
            requiresTerminal: false,
            dependsOn: [],
            waveIndex: 0
        )
        return [TaskWave(index: 0, description: "Exekvering", tasks: [task], dependsOnWave: nil)]
    }
}
