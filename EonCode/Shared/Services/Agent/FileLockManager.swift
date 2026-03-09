import Foundation

/// Prevents multiple agents from editing the same file simultaneously.
/// Each agent claims files before editing; other agents see claimed files as locked.
@MainActor
final class FileLockManager: ObservableObject {
    static let shared = FileLockManager()

    /// Maps file path → agent ID that holds the lock
    @Published private(set) var locks: [String: String] = [:]

    private init() {}

    /// Try to claim a file. Returns true if lock acquired, false if already locked by another agent.
    func claim(filePath: String, agentID: String) -> Bool {
        if let existing = locks[filePath], existing != agentID {
            return false  // locked by someone else
        }
        locks[filePath] = agentID
        return true
    }

    /// Release a specific file lock.
    func release(filePath: String, agentID: String) {
        if locks[filePath] == agentID {
            locks.removeValue(forKey: filePath)
        }
    }

    /// Release all locks held by an agent (call when agent finishes).
    func releaseAll(agentID: String) {
        locks = locks.filter { $0.value != agentID }
    }

    /// Returns true if file is locked by a different agent.
    func isLocked(filePath: String, byOtherThan agentID: String) -> Bool {
        guard let holder = locks[filePath] else { return false }
        return holder != agentID
    }

    /// Returns the agent ID that holds the lock (if any).
    func holder(for filePath: String) -> String? {
        locks[filePath]
    }

    /// Files currently locked by a specific agent.
    func lockedFiles(for agentID: String) -> [String] {
        locks.filter { $0.value == agentID }.map(\.key).sorted()
    }
}
