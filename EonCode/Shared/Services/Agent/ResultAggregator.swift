import Foundation

// MARK: - ResultAggregator
// Merges results from parallel workers, detects file conflicts,
// and asks Claude to resolve them.

final class ResultAggregator {

    struct AggregatedResult {
        let waveIndex: Int
        let workerResults: [WorkerResult]
        let conflicts: [FileConflict]
        let resolvedFiles: [String: String]  // path → content
        let summary: String
    }

    struct FileConflict {
        let path: String
        let versions: [(workerID: UUID, content: String)]
    }

    // MARK: - Merge worker results

    static func merge(
        results: [WorkerResult],
        waveIndex: Int,
        projectRoot: URL?,
        model: ClaudeModel = .haiku
    ) async -> AggregatedResult {
        // 1. Collect all files written
        var fileVersions: [String: [(UUID, String)]] = [:]

        for result in results {
            for path in result.filesWritten {
                let content = (try? String(contentsOfFile: resolvedPath(path, projectRoot: projectRoot))) ?? ""
                fileVersions[path, default: []].append((result.taskID, content))
            }
        }

        // 2. Find conflicts (same file written by multiple workers)
        var conflicts: [FileConflict] = []
        var resolvedFiles: [String: String] = [:]

        for (path, versions) in fileVersions {
            if versions.count == 1 {
                resolvedFiles[path] = versions[0].1
            } else {
                // Conflict!
                let conflict = FileConflict(
                    path: path,
                    versions: versions.map { ($0.0, $0.1) }
                )
                conflicts.append(conflict)
            }
        }

        // 3. Resolve conflicts via Claude
        if !conflicts.isEmpty {
            let resolved = await resolveConflicts(conflicts, model: model)
            resolvedFiles.merge(resolved) { _, new in new }

            // Write resolved files
            for (path, content) in resolved {
                let url = URL(fileURLWithPath: resolvedPath(path, projectRoot: projectRoot))
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        // 4. Build summary
        let succeeded = results.filter(\.succeeded).count
        let queued = results.filter { !$0.ranLocally }.count
        let summary = """
        Våg \(waveIndex + 1): \(succeeded)/\(results.count) workers lyckades · \
        \(conflicts.count) konflikter lösta · \
        \(queued) tasks via Mac
        """

        return AggregatedResult(
            waveIndex: waveIndex,
            workerResults: results,
            conflicts: conflicts,
            resolvedFiles: resolvedFiles,
            summary: summary
        )
    }

    // MARK: - Claude-assisted conflict resolution

    private static func resolveConflicts(
        _ conflicts: [FileConflict],
        model: ClaudeModel
    ) async -> [String: String] {
        var resolved: [String: String] = [:]

        for conflict in conflicts {
            let prompt = buildConflictPrompt(conflict)

            guard let (text, _) = try? await ClaudeAPIClient.shared.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                model: model,
                systemPrompt: "Du är en kodmerge-assistent. Returnera ENBART den slutgiltiga koden, inget annat.",
                maxTokens: Constants.Agent.maxTokensLarge
            ) else { continue }

            resolved[conflict.path] = text
        }

        return resolved
    }

    private static func buildConflictPrompt(_ conflict: FileConflict) -> String {
        var prompt = "Mergea dessa versioner av \(conflict.path) till ett optimalt resultat:\n\n"
        for (i, (_, content)) in conflict.versions.enumerated() {
            prompt += "--- Version \(i + 1) ---\n\(content)\n\n"
        }
        prompt += "Returnera ENBART den mergade koden."
        return prompt
    }

    private static func resolvedPath(_ path: String, projectRoot: URL?) -> String {
        if path.hasPrefix("/") { return path }
        return (projectRoot?.appendingPathComponent(path).path) ?? path
    }
}
