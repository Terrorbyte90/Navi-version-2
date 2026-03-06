import Foundation

// MARK: - WorkerPool
// Manages a configurable pool of parallel WorkerAgents.
// Throttles concurrency to respect API rate limits.

@MainActor
final class WorkerPool: ObservableObject {
    static let shared = WorkerPool()

    @Published var activeWorkers: [WorkerAgent] = []
    @Published var completedCount = 0
    @Published var totalCount = 0

    var maxConcurrent: Int { SettingsStore.shared.maxParallelWorkers }

    // Rate limiting: max API calls per minute (conservative)
    private let callsPerMinute = 20
    private var recentCallTimestamps: [Date] = []

    private init() {}

    // MARK: - Execute a wave of tasks in parallel

    func executeTasks(
        _ tasks: [WorkerTask],
        projectRoot: URL?,
        model: ClaudeModel,
        onWorkerUpdate: @escaping (WorkerAgent) -> Void
    ) async -> [WorkerResult] {
        totalCount += tasks.count
        var results: [WorkerResult] = []

        // Split into concurrent batches respecting maxConcurrent
        let batches = tasks.chunked(into: maxConcurrent)

        for batch in batches {
            let batchResults = await executeBatch(
                batch,
                projectRoot: projectRoot,
                model: model,
                onWorkerUpdate: onWorkerUpdate
            )
            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - Execute one batch in parallel

    private func executeBatch(
        _ tasks: [WorkerTask],
        projectRoot: URL?,
        model: ClaudeModel,
        onWorkerUpdate: @escaping (WorkerAgent) -> Void
    ) async -> [WorkerResult] {
        // Spawn workers
        let workers = tasks.map { WorkerAgent(task: $0, projectRoot: projectRoot, model: model) }
        for w in workers { activeWorkers.append(w) }

        // Run in parallel with TaskGroup
        var results: [WorkerResult] = []

        await withTaskGroup(of: WorkerResult.self) { group in
            for worker in workers {
                await throttleIfNeeded()
                group.addTask { @MainActor in
                    let result = await worker.run()
                    onWorkerUpdate(worker)
                    return result
                }
            }

            for await result in group {
                results.append(result)
                completedCount += 1
                // Remove from active
                activeWorkers.removeAll { $0.id == result.taskID }
            }
        }

        return results
    }

    // MARK: - Rate limiting

    private func throttleIfNeeded() async {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        recentCallTimestamps = recentCallTimestamps.filter { $0 > oneMinuteAgo }

        if recentCallTimestamps.count >= callsPerMinute {
            // Wait until oldest call falls out of window
            if let oldest = recentCallTimestamps.first {
                let waitTime = oldest.addingTimeInterval(60).timeIntervalSince(now) + 0.5
                if waitTime > 0 {
                    try? await Task.sleep(seconds: waitTime)
                }
            }
        }

        recentCallTimestamps.append(Date())
    }

    func reset() {
        activeWorkers = []
        completedCount = 0
        totalCount = 0
    }
}

// MARK: - Array chunking helper

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: max(1, size)).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
