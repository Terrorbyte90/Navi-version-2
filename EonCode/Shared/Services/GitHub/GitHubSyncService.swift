import Foundation

/// Background service that keeps all linked GitHub repos in sync.
/// - Fetches latest commits on launch
/// - Runs a 5-minute polling timer
/// - Updates sync status per repo
@MainActor
final class GitHubSyncService: ObservableObject {
    static let shared = GitHubSyncService()

    @Published var syncStatus: [String: RepoSyncStatus] = [:]  // fullName → status

    private var timer: Timer?
    private let interval: TimeInterval = 300  // 5 minutes

    enum RepoSyncStatus {
        case synced         // ✓
        case syncing        // ⟳
        case behind(Int)    // ⚠ N commits behind
        case unknown

        var icon: String {
            switch self {
            case .synced: return "✓"
            case .syncing: return "⟳"
            case .behind: return "⚠"
            case .unknown: return "?"
            }
        }

        var label: String {
            switch self {
            case .synced: return "Synkad"
            case .syncing: return "Synkar…"
            case .behind(let n): return "\(n) bakom"
            case .unknown: return "Okänd"
            }
        }
    }

    private init() {}

    /// Call on app launch. Fetches all repos and starts background timer.
    func start() {
        Task { await syncAll() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.syncAll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Sync all repos that have projects linked to them.
    func syncAll() async {
        let gh = GitHubManager.shared
        guard !gh.repos.isEmpty else {
            // Fetch repos first
            await gh.fetchRepos()
            return
        }
        for repo in gh.repos {
            await syncRepo(repo)
        }
    }

    func syncRepo(_ repo: GitHubRepo) async {
        syncStatus[repo.fullName] = .syncing
        let gh = GitHubManager.shared
        // Refresh commits to detect if behind
        let commits = await gh.fetchCommits(for: repo, forceRefresh: true)
        // Also ensure backup branch exists
        await gh.ensureBackupBranch(for: repo)
        // For linked projects (cloned locally), do a pull
        if let localPath = gh.clonedRepos[repo.fullName] {
            let result = await gh.runGit(["-C", localPath, "pull", "--rebase", "origin", repo.currentBranch])
            if result.success {
                syncStatus[repo.fullName] = .synced
            } else {
                syncStatus[repo.fullName] = .unknown
            }
        } else {
            syncStatus[repo.fullName] = commits.isEmpty ? .unknown : .synced
        }
    }
}
