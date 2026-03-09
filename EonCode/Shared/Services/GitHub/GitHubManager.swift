import Foundation
import Combine

// MARK: - Models

struct GitHubRepo: Identifiable, Codable, Equatable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let defaultBranch: String
    let htmlURL: String
    let cloneURL: String
    let sshURL: String
    let language: String?
    let stargazersCount: Int
    let updatedAt: Date
    var currentBranch: String  // mutable — user can change

    enum CodingKeys: String, CodingKey {
        case id, name, description, language
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case sshURL = "ssh_url"
        case stargazersCount = "stargazers_count"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        fullName = try c.decode(String.self, forKey: .fullName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isPrivate = try c.decode(Bool.self, forKey: .isPrivate)
        defaultBranch = try c.decode(String.self, forKey: .defaultBranch)
        htmlURL = try c.decode(String.self, forKey: .htmlURL)
        cloneURL = try c.decode(String.self, forKey: .cloneURL)
        sshURL = try c.decode(String.self, forKey: .sshURL)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        stargazersCount = try c.decode(Int.self, forKey: .stargazersCount)
        let dateStr = try c.decode(String.self, forKey: .updatedAt)
        updatedAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        currentBranch = defaultBranch
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(fullName, forKey: .fullName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(isPrivate, forKey: .isPrivate)
        try c.encode(defaultBranch, forKey: .defaultBranch)
        try c.encode(htmlURL, forKey: .htmlURL)
        try c.encode(cloneURL, forKey: .cloneURL)
        try c.encode(sshURL, forKey: .sshURL)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encode(stargazersCount, forKey: .stargazersCount)
        try c.encode(ISO8601DateFormatter().string(from: updatedAt), forKey: .updatedAt)
    }
}

struct GitHubBranch: Identifiable, Codable {
    var id: String { name }
    let name: String
    let protected: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case protected
    }
}

struct GitHubUser: Codable {
    let login: String
    let name: String?
    let avatarURL: String
    let publicRepos: Int
    let totalPrivateRepos: Int?

    enum CodingKeys: String, CodingKey {
        case login, name
        case avatarURL = "avatar_url"
        case publicRepos = "public_repos"
        case totalPrivateRepos = "total_private_repos"
    }
}

struct GitHubCommit: Identifiable, Codable {
    var id: String { sha }
    let sha: String
    let commit: CommitDetail
    let htmlURL: String

    struct CommitDetail: Codable {
        let message: String
        let author: CommitAuthor
    }
    struct CommitAuthor: Codable {
        let name: String
        let date: String
    }

    enum CodingKeys: String, CodingKey {
        case sha, commit
        case htmlURL = "html_url"
    }
}

struct GitHubPullRequest: Identifiable, Codable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: String          // "open", "closed"
    let htmlURL: String
    let createdAt: String
    let updatedAt: String
    let user: PRUser
    let head: PRRef
    let base: PRRef
    let merged: Bool?
    let draft: Bool?

    struct PRUser: Codable {
        let login: String
        let avatarURL: String?
        enum CodingKeys: String, CodingKey {
            case login
            case avatarURL = "avatar_url"
        }
    }
    struct PRRef: Codable {
        let ref: String
        let label: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, head, base, merged, draft
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum GitHubAuthState {
    case notAuthorized
    case authorized(user: GitHubUser)
    case loading
    case error(String)
}

// MARK: - GitHubManager

@MainActor
final class GitHubManager: ObservableObject {
    static let shared = GitHubManager()

    @Published var authState: GitHubAuthState = .notAuthorized
    @Published var repos: [GitHubRepo] = []
    @Published var isLoadingRepos = false
    @Published var repoError: String?
    @Published var branchCache: [String: [GitHubBranch]] = [:]  // fullName → branches
    @Published var commitCache: [String: [GitHubCommit]] = [:]  // "fullName/branch" → commits
    @Published var clonedRepos: [String: String] = [:]          // fullName → localPath
    @Published var syncStatus: [String: String] = [:]           // fullName → status message
    @Published var prCache: [String: [GitHubPullRequest]] = [:] // fullName → PRs

    private let baseURL = "https://api.github.com"
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Load cached repos from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "github_repos_cache"),
           let cached = try? JSONDecoder().decode([GitHubRepo].self, from: data) {
            repos = cached
        }
        if let paths = UserDefaults.standard.dictionary(forKey: "github_cloned_repos") as? [String: String] {
            clonedRepos = paths
        }
        // Auto-verify token on init
        Task { await verifyToken() }
    }

    // MARK: - Token management (iCloud Keychain synced)

    var token: String? {
        get { KeychainSync.getSync(key: Constants.Keychain.githubKey) }
    }

    func saveToken(_ token: String) throws {
        try KeychainSync.saveSync(key: Constants.Keychain.githubKey, value: token)
    }

    func deleteToken() {
        KeychainSync.deleteSync(key: Constants.Keychain.githubKey)
        authState = .notAuthorized
        repos = []
    }

    // MARK: - Auth verification

    func verifyToken() async {
        guard let token, !token.isEmpty else {
            authState = .notAuthorized
            return
        }
        authState = .loading
        do {
            let user = try await fetchUser(token: token)
            authState = .authorized(user: user)
            await fetchRepos()
        } catch {
            authState = .error(error.localizedDescription)
        }
    }

    private func fetchUser(token: String) async throws -> GitHubUser {
        let req = try makeRequest(path: "/user", token: token)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    // MARK: - Fetch repos (all pages)

    func fetchRepos() async {
        guard let token else { return }
        isLoadingRepos = true
        repoError = nil
        do {
            var all: [GitHubRepo] = []
            var page = 1
            while true {
                let req = try makeRequest(path: "/user/repos?per_page=100&page=\(page)&sort=updated&affiliation=owner,collaborator,organization_member", token: token)
                let (data, resp) = try await URLSession.shared.data(for: req)
                try checkResponse(resp, data: data)
                let decoder = JSONDecoder()
                let batch = try decoder.decode([GitHubRepo].self, from: data)
                if batch.isEmpty { break }
                all.append(contentsOf: batch)
                page += 1
                if batch.count < 100 { break }
            }
            // Preserve user-selected branches
            repos = all.map { repo in
                var r = repo
                if let existing = repos.first(where: { $0.id == repo.id }) {
                    r.currentBranch = existing.currentBranch
                }
                return r
            }
            // Cache
            if let data = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(data, forKey: "github_repos_cache")
            }
        } catch {
            repoError = error.localizedDescription
        }
        isLoadingRepos = false
    }

    // MARK: - Branches

    func fetchBranches(for repo: GitHubRepo, forceRefresh: Bool = false) async -> [GitHubBranch] {
        if !forceRefresh, let cached = branchCache[repo.fullName] { return cached }
        guard let token else { return [] }
        do {
            var all: [GitHubBranch] = []
            var page = 1
            while true {
                let req = try makeRequest(path: "/repos/\(repo.fullName)/branches?per_page=100&page=\(page)", token: token)
                let (data, resp) = try await URLSession.shared.data(for: req)
                try checkResponse(resp, data: data)
                let batch = try JSONDecoder().decode([GitHubBranch].self, from: data)
                all.append(contentsOf: batch)
                if batch.count < 100 { break }
                page += 1
            }
            branchCache[repo.fullName] = all
            return all
        } catch { return [] }
    }

    func setBranch(_ branch: String, for repoID: Int) {
        if let idx = repos.firstIndex(where: { $0.id == repoID }) {
            repos[idx].currentBranch = branch
            if let data = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(data, forKey: "github_repos_cache")
            }
        }
    }

    // MARK: - Recent commits

    func fetchCommits(for repo: GitHubRepo, branch: String? = nil, forceRefresh: Bool = false) async -> [GitHubCommit] {
        let b = branch ?? repo.currentBranch
        let cacheKey = "\(repo.fullName)/\(b)"
        if !forceRefresh, let cached = commitCache[cacheKey] { return cached }
        guard let token else { return [] }
        do {
            let req = try makeRequest(path: "/repos/\(repo.fullName)/commits?sha=\(b)&per_page=20", token: token)
            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let commits = try JSONDecoder().decode([GitHubCommit].self, from: data)
            commitCache[cacheKey] = commits
            return commits
        } catch { return [] }
    }

    // MARK: - Pull Requests

    func fetchPullRequests(for repo: GitHubRepo, state: String = "open", forceRefresh: Bool = false) async -> [GitHubPullRequest] {
        if !forceRefresh, let cached = prCache[repo.fullName] { return cached }
        guard let token else { return [] }
        do {
            let req = try makeRequest(path: "/repos/\(repo.fullName)/pulls?state=\(state)&per_page=30&sort=updated&direction=desc", token: token)
            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let prs = try JSONDecoder().decode([GitHubPullRequest].self, from: data)
            prCache[repo.fullName] = prs
            return prs
        } catch { return [] }
    }

    func createPullRequest(
        repo: GitHubRepo,
        title: String,
        body: String,
        head: String,
        base: String
    ) async throws -> GitHubPullRequest {
        guard let token else { throw GitHubError.unauthorized }

        var req = try makeRequest(path: "/repos/\(repo.fullName)/pulls", token: token)
        req.httpMethod = "POST"
        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "head": head,
            "base": base
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        let pr = try JSONDecoder().decode(GitHubPullRequest.self, from: data)
        // Invalidate cache
        prCache[repo.fullName] = nil
        return pr
    }

    func mergePullRequest(repo: GitHubRepo, number: Int) async throws {
        guard let token else { throw GitHubError.unauthorized }

        var req = try makeRequest(path: "/repos/\(repo.fullName)/pulls/\(number)/merge", token: token)
        req.httpMethod = "PUT"
        let payload: [String: Any] = ["merge_method": "squash"]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        // Invalidate caches
        prCache[repo.fullName] = nil
        commitCache = commitCache.filter { !$0.key.hasPrefix(repo.fullName) }
    }

    // MARK: - Clone / open repo locally

    func cloneOrOpen(repo: GitHubRepo) async -> String? {
        if let localPath = clonedRepos[repo.fullName],
           FileManager.default.fileExists(atPath: localPath) {
            // Already cloned — switch to correct branch
            await switchBranch(to: repo.currentBranch, at: localPath)
            return localPath
        }

        // Clone fresh
        let dest = localRepoPath(for: repo)
        syncStatus[repo.fullName] = "Klonar…"
        let result = await runGit(["clone", "--branch", repo.currentBranch, repo.cloneURL, dest])
        if result.success {
            clonedRepos[repo.fullName] = dest
            UserDefaults.standard.set(clonedRepos, forKey: "github_cloned_repos")
            syncStatus[repo.fullName] = "Klonad ✓"
            return dest
        } else {
            syncStatus[repo.fullName] = "Kloning misslyckades: \(result.output)"
            return nil
        }
    }

    // MARK: - Branch switch

    func switchBranch(to branch: String, at path: String) async {
        let fetch = await runGit(["-C", path, "fetch", "--all"])
        let checkout = await runGit(["-C", path, "checkout", branch])
        if !checkout.success {
            // Branch doesn't exist locally — track remote
            let _ = await runGit(["-C", path, "checkout", "-b", branch, "origin/\(branch)"])
        }
        let pull = await runGit(["-C", path, "pull", "--rebase"])
        _ = fetch; _ = pull
    }

    // MARK: - Pull

    func pull(repo: GitHubRepo) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        syncStatus[repo.fullName] = "Hämtar…"
        await ensureAuthRemote(repo: repo, at: localPath)
        let result = await runGit(["-C", localPath, "pull", "--rebase", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = result.success ? "Uppdaterad ✓" : "Pull misslyckades: \(result.output)"
        // Refresh commit cache after pull
        if result.success {
            commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
        }
    }

    // MARK: - Push

    func push(repo: GitHubRepo, message: String? = nil) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        syncStatus[repo.fullName] = "Pushar…"

        // Ensure remote URL has token embedded for auth
        await ensureAuthRemote(repo: repo, at: localPath)

        // Stage all changes
        let _ = await runGit(["-C", localPath, "add", "-A"])

        // Commit if there are staged changes
        let status = await runGit(["-C", localPath, "status", "--porcelain"])
        if !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let msg = message ?? "Navi auto-commit \(Date().formatted())"
            let _ = await runGit(["-C", localPath, "commit", "-m", msg])
        }

        // Push
        let push = await runGit(["-C", localPath, "push", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = push.success ? "Pushad ✓" : "Push misslyckades: \(push.output)"

        // Refresh commit cache after push
        if push.success {
            commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
        }
    }

    /// Ensure the remote origin URL contains auth credentials
    private func ensureAuthRemote(repo: GitHubRepo, at localPath: String) async {
        guard let tok = token else { return }
        let authURL = repo.cloneURL.replacingOccurrences(
            of: "https://github.com/",
            with: "https://x-access-token:\(tok)@github.com/"
        )
        let _ = await runGit(["-C", localPath, "remote", "set-url", "origin", authURL])
    }

    // MARK: - Auto sync (pull on open, push on save)

    func autoPull(repo: GitHubRepo) async {
        guard clonedRepos[repo.fullName] != nil else { return }
        await pull(repo: repo)
    }

    func autoCommitAndPush(repo: GitHubRepo, changedFiles: [String]) async {
        guard let localPath = clonedRepos[repo.fullName] else { return }
        await ensureAuthRemote(repo: repo, at: localPath)
        // Stage all or specific files
        if changedFiles.isEmpty {
            let _ = await runGit(["-C", localPath, "add", "-A"])
        } else {
            for file in changedFiles {
                let _ = await runGit(["-C", localPath, "add", file])
            }
        }
        let statusResult = await runGit(["-C", localPath, "status", "--porcelain"])
        guard !statusResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let msg = changedFiles.isEmpty
            ? "Navi: agent-ändringar \(Date().formatted(.dateTime.hour().minute()))"
            : "Navi: uppdaterar \(changedFiles.prefix(3).joined(separator: ", "))"
        let _ = await runGit(["-C", localPath, "commit", "-m", msg])
        let pushResult = await runGit(["-C", localPath, "push", "origin", repo.currentBranch])
        syncStatus[repo.fullName] = pushResult.success ? "Auto-pushad ✓" : "Push misslyckades: \(pushResult.output)"
        // Invalidate commit cache so UI refreshes
        commitCache["\(repo.fullName)/\(repo.currentBranch)"] = nil
    }

    // MARK: - Auto-create repo for new project

    /// Creates a new GitHub repo for a project (if no repo is linked) and pushes initial content.
    func ensureRepoExists(for project: NaviProject) async -> GitHubRepo? {
        // Already linked
        if let fullName = project.githubRepoFullName,
           let existing = repos.first(where: { $0.fullName == fullName }) {
            return existing
        }

        guard let token, !token.isEmpty else { return nil }

        // Create repo via API
        let repoName = project.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let body: [String: Any] = [
            "name": repoName,
            "description": project.description.isEmpty ? "Skapad av Navi" : project.description,
            "private": true,
            "auto_init": true
        ]

        do {
            var req = try makeRequest(path: "/user/repos", token: token)
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, resp) = try await URLSession.shared.data(for: req)
            try checkResponse(resp, data: data)
            let newRepo = try JSONDecoder().decode(GitHubRepo.self, from: data)

            // Add to local list
            repos.insert(newRepo, at: 0)
            if let encoded = try? JSONEncoder().encode(repos) {
                UserDefaults.standard.set(encoded, forKey: "github_repos_cache")
            }

            // Clone it locally
            _ = await cloneOrOpen(repo: newRepo)

            return newRepo
        } catch {
            return nil
        }
    }

    /// Creates a feature branch for the current agent task and switches to it.
    func createFeatureBranch(name: String, in repo: GitHubRepo) async -> Bool {
        let safeName = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(50)
        return await createBranch(name: "feature/\(safeName)", from: repo.defaultBranch, in: repo)
    }

    /// Full auto-sync: pull latest, then push any local changes.
    func fullSync(repo: GitHubRepo) async {
        await pull(repo: repo)
        await autoCommitAndPush(repo: repo, changedFiles: [])
    }

    // MARK: - Create branch

    func createBranch(name: String, from base: String, in repo: GitHubRepo) async -> Bool {
        guard let localPath = clonedRepos[repo.fullName] else { return false }
        let _ = await runGit(["-C", localPath, "fetch", "--all"])
        let result = await runGit(["-C", localPath, "checkout", "-b", name, "origin/\(base)"])
        if result.success {
            let _ = await runGit(["-C", localPath, "push", "-u", "origin", name])
            branchCache[repo.fullName] = nil  // invalidate cache
        }
        return result.success
    }

    // MARK: - Git status for a repo

    func gitStatus(repo: GitHubRepo) async -> String {
        guard let localPath = clonedRepos[repo.fullName] else { return "Ej klonad" }
        let result = await runGit(["-C", localPath, "status", "--short"])
        return result.output.isEmpty ? "Rent" : result.output
    }

    // MARK: - Open repo as NaviProject

    func openAsProject(repo: GitHubRepo) async -> NaviProject? {
        guard let localPath = await cloneOrOpen(repo: repo) else { return nil }

        // Check if this repo is already linked to an existing project
        if let existing = ProjectStore.shared.projects.first(where: { $0.githubRepoFullName == repo.fullName }) {
            var updated = existing
            updated.rootPath = localPath
            updated.githubBranch = repo.currentBranch
            await ProjectStore.shared.save(updated)
            ProjectStore.shared.activeProject = updated
            NotificationCenter.default.post(name: .didOpenGitHubProject, object: nil)
            return updated
        }

        var project = NaviProject(name: repo.name, rootPath: localPath)
        project.githubRepoFullName = repo.fullName
        project.githubBranch = repo.currentBranch
        await ProjectStore.shared.save(project)
        ProjectStore.shared.activeProject = project
        // Notify UI to switch to project tab
        NotificationCenter.default.post(name: .didOpenGitHubProject, object: nil)
        return project
    }

    // MARK: - Helpers

    private func localRepoPath(for repo: GitHubRepo) -> String {
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Navi/GitHub")
        #else
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Navi/GitHub")
        #endif
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(repo.fullName.replacingOccurrences(of: "/", with: "_")).path
    }

    private func makeRequest(path: String, token: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 15
        return req
    }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            authState = .notAuthorized
            throw GitHubError.unauthorized
        }
        if http.statusCode == 403 {
            throw GitHubError.forbidden
        }
        if http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode(GitHubAPIError.self, from: data))?.message ?? "HTTP \(http.statusCode)"
            throw GitHubError.apiError(msg)
        }
    }

    // MARK: - Run git command

    struct GitResult {
        let success: Bool
        let output: String
    }

    func runGit(_ args: [String]) async -> GitResult {
        #if os(macOS)
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")

                // Rewrite clone URLs to embed token for HTTPS auth
                var adjustedArgs = args
                if let tok = self.token {
                    adjustedArgs = args.map { arg in
                        if arg.hasPrefix("https://github.com/") {
                            return arg.replacingOccurrences(
                                of: "https://github.com/",
                                with: "https://x-access-token:\(tok)@github.com/"
                            )
                        }
                        return arg
                    }
                }
                proc.arguments = adjustedArgs

                // Environment for git
                var env = ProcessInfo.processInfo.environment
                env["GIT_TERMINAL_PROMPT"] = "0"
                if let tok = self.token {
                    // Credential helper that provides token
                    env["GIT_ASKPASS"] = "/usr/bin/true"
                    env["GIT_USERNAME"] = "x-access-token"
                    env["GIT_PASSWORD"] = tok
                }
                proc.environment = env

                let pipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let combined = [out, err].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: GitResult(success: proc.terminationStatus == 0, output: combined))
                } catch {
                    cont.resume(returning: GitResult(success: false, output: error.localizedDescription))
                }
            }
        }
        #else
        // iOS: use GitHub REST API — no Mac required
        return await runGitViaAPI(args)
        #endif
    }

    // MARK: - iOS: GitHub API-based git client

    /// Staged files per local repo path, waiting to be committed & pushed.
    private struct PendingCommit {
        var repoFullName: String
        var branch: String
        var stagedFiles: [String: Data?]   // relative path → content (nil = deleted)
        var pendingMessage: String?
    }
    private var pendingCommits: [String: PendingCommit] = [:]

    /// Lightweight git metadata stored next to cloned files.
    private struct GitMeta: Codable {
        var repoFullName: String
        var branch: String
        var commitSHA: String
    }

    private func gitMetaPath(at repoPath: String) -> String { repoPath + "/.navi-git" }

    private func saveGitMeta(at repoPath: String, repoFullName: String, branch: String, sha: String) {
        let meta = GitMeta(repoFullName: repoFullName, branch: branch, commitSHA: sha)
        if let data = try? JSONEncoder().encode(meta) {
            FileManager.default.createFile(atPath: gitMetaPath(at: repoPath), contents: data)
        }
    }

    private func loadGitMeta(at repoPath: String) -> GitMeta? {
        guard let data = FileManager.default.contents(atPath: gitMetaPath(at: repoPath)) else { return nil }
        return try? JSONDecoder().decode(GitMeta.self, from: data)
    }

    private func extractRepoFullName(from url: String) -> String? {
        // Handles: https://github.com/owner/repo(.git)
        //          https://x-access-token:...@github.com/owner/repo
        let cleaned = url.replacingOccurrences(of: ".git", with: "")
        let parts = cleaned.components(separatedBy: "github.com/")
        guard let last = parts.last, last.contains("/") else { return nil }
        return last
    }

    private func runGitViaAPI(_ args: [String]) async -> GitResult {
        var remaining = args
        var workDir: String?

        if remaining.first == "-C", remaining.count >= 2 {
            workDir = remaining[1]
            remaining = Array(remaining.dropFirst(2))
        }

        guard let subcommand = remaining.first else {
            return GitResult(success: false, output: "Inget git-subkommando")
        }
        let cmdArgs = Array(remaining.dropFirst())

        switch subcommand {
        case "clone":   return await apiClone(args: cmdArgs)
        case "fetch":   return GitResult(success: true, output: "")
        case "checkout": return await apiCheckout(args: cmdArgs, at: workDir)
        case "pull":    return await apiPull(at: workDir, args: cmdArgs)
        case "add":     return apiAdd(args: cmdArgs, at: workDir)
        case "commit":  return apiCommit(args: cmdArgs, at: workDir)
        case "push":    return await apiPush(at: workDir, args: cmdArgs)
        case "status":  return await apiStatus(at: workDir)
        case "log":     return await apiLog(at: workDir)
        case "remote":  return GitResult(success: true, output: "")  // auth via token
        default:
            return GitResult(success: false, output: "iOS git: '\(subcommand)' ej implementerat")
        }
    }

    // MARK: Clone

    private func apiClone(args: [String]) async -> GitResult {
        var branch: String?
        var repoURL: String?
        var dest: String?
        var i = 0
        while i < args.count {
            if args[i] == "--branch", i + 1 < args.count { branch = args[i + 1]; i += 2; continue }
            if repoURL == nil { repoURL = args[i] } else if dest == nil { dest = args[i] }
            i += 1
        }
        guard let url = repoURL, let destPath = dest else {
            return GitResult(success: false, output: "clone: URL och destination krävs")
        }
        guard let fullName = extractRepoFullName(from: url) else {
            return GitResult(success: false, output: "clone: kan inte parsa repo från \(url)")
        }
        guard let token else { return GitResult(success: false, output: "GitHub token saknas") }

        let targetBranch = branch ?? repos.first(where: { $0.fullName == fullName })?.defaultBranch ?? "main"

        do {
            try FileManager.default.createDirectory(atPath: destPath, withIntermediateDirectories: true)

            // Get HEAD SHA for the branch
            struct RefObj: Codable { struct Obj: Codable { let sha: String }; let object: Obj }
            let refReq = try makeRequest(path: "/repos/\(fullName)/git/refs/heads/\(targetBranch)", token: token)
            let (refData, refResp) = try await URLSession.shared.data(for: refReq)
            try checkResponse(refResp, data: refData)
            let headSHA = try JSONDecoder().decode(RefObj.self, from: refData).object.sha

            // Get tree SHA from commit
            struct CommitObj: Codable { struct Tree: Codable { let sha: String }; let tree: Tree }
            let commitReq = try makeRequest(path: "/repos/\(fullName)/git/commits/\(headSHA)", token: token)
            let (commitData, commitResp) = try await URLSession.shared.data(for: commitReq)
            try checkResponse(commitResp, data: commitData)
            let treeSHA = try JSONDecoder().decode(CommitObj.self, from: commitData).tree.sha

            // Get recursive tree
            struct TreeItem: Codable { let path: String; let type: String; let sha: String?; let size: Int? }
            struct TreeResp: Codable { let tree: [TreeItem] }
            let treeReq = try makeRequest(path: "/repos/\(fullName)/git/trees/\(treeSHA)?recursive=1", token: token)
            let (treeData, treeResp) = try await URLSession.shared.data(for: treeReq)
            try checkResponse(treeResp, data: treeData)
            let items = try JSONDecoder().decode(TreeResp.self, from: treeData).tree

            let fm = FileManager.default
            // Create directories
            for item in items where item.type == "tree" {
                try? fm.createDirectory(atPath: destPath + "/" + item.path, withIntermediateDirectories: true)
            }

            // Download blobs (skip files > 1 MB to keep it fast)
            for item in items where item.type == "blob" {
                if let size = item.size, size > 1_000_000 { continue }
                let filePath = destPath + "/" + item.path
                let dirURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
                try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)

                struct ContentResp: Codable { let content: String?; let encoding: String? }
                let cReq = try makeRequest(path: "/repos/\(fullName)/contents/\(item.path)?ref=\(targetBranch)", token: token)
                let (cData, cResp) = try await URLSession.shared.data(for: cReq)
                guard (cResp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else { continue }
                if let cr = try? JSONDecoder().decode(ContentResp.self, from: cData),
                   let encoded = cr.content, cr.encoding == "base64" {
                    let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
                    if let fileData = Data(base64Encoded: cleaned) {
                        fm.createFile(atPath: filePath, contents: fileData)
                    }
                }
            }

            saveGitMeta(at: destPath, repoFullName: fullName, branch: targetBranch, sha: headSHA)
            return GitResult(success: true, output: "Klonat \(fullName) (\(targetBranch)) ✓")
        } catch {
            return GitResult(success: false, output: "clone misslyckades: \(error.localizedDescription)")
        }
    }

    // MARK: Pull

    private func apiPull(at workDir: String?, args: [String]) async -> GitResult {
        guard let path = workDir, let meta = loadGitMeta(at: path) else {
            return GitResult(success: false, output: "pull: ingen git-metadata, klonat ej?")
        }
        let branch = args.last(where: { !$0.hasPrefix("-") && $0 != "origin" }) ?? meta.branch
        // Re-use clone logic to refresh all files
        let result = await apiClone(args: ["--branch", branch,
                                           "https://github.com/\(meta.repoFullName)", path])
        return GitResult(success: result.success,
                         output: result.success ? "Uppdaterad (\(branch)) ✓" : result.output)
    }

    // MARK: Checkout

    private func apiCheckout(args: [String], at workDir: String?) async -> GitResult {
        guard let path = workDir, let meta = loadGitMeta(at: path) else {
            return GitResult(success: false, output: "checkout: ingen git-metadata")
        }
        guard let token else { return GitResult(success: false, output: "GitHub token saknas") }

        let isNew = args.contains("-b")
        let branches = args.filter { !$0.hasPrefix("-") && !$0.hasPrefix("origin/") }
        guard let target = branches.first else {
            return GitResult(success: false, output: "checkout: branch saknas")
        }

        if isNew {
            let base = args.first(where: { $0.hasPrefix("origin/") })
                .map { String($0.dropFirst("origin/".count)) } ?? meta.branch
            do {
                struct RefObj: Codable { struct Obj: Codable { let sha: String }; let object: Obj }
                let refReq = try makeRequest(path: "/repos/\(meta.repoFullName)/git/refs/heads/\(base)", token: token)
                let (refData, refResp) = try await URLSession.shared.data(for: refReq)
                try checkResponse(refResp, data: refData)
                let sha = try JSONDecoder().decode(RefObj.self, from: refData).object.sha

                var createReq = try makeRequest(path: "/repos/\(meta.repoFullName)/git/refs", token: token)
                createReq.httpMethod = "POST"
                createReq.httpBody = try JSONSerialization.data(withJSONObject: ["ref": "refs/heads/\(target)", "sha": sha])
                createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let (_, createResp) = try await URLSession.shared.data(for: createReq)
                try checkResponse(createResp, data: Data())

                saveGitMeta(at: path, repoFullName: meta.repoFullName, branch: target, sha: sha)
                return GitResult(success: true, output: "Branch '\(target)' skapad ✓")
            } catch {
                return GitResult(success: false, output: "checkout -b misslyckades: \(error.localizedDescription)")
            }
        } else {
            return await apiPull(at: path, args: ["origin", target])
        }
    }

    // MARK: Add (stage)

    private func apiAdd(args: [String], at workDir: String?) -> GitResult {
        guard let path = workDir, let meta = loadGitMeta(at: path) else {
            return GitResult(success: false, output: "add: ingen git-metadata")
        }
        if pendingCommits[path] == nil {
            pendingCommits[path] = PendingCommit(repoFullName: meta.repoFullName,
                                                  branch: meta.branch,
                                                  stagedFiles: [:])
        }
        let fm = FileManager.default
        let addAll = args.contains("-A") || args.contains(".")
        if addAll {
            guard let enumerator = fm.enumerator(atPath: path) else {
                return GitResult(success: false, output: "Kan inte läsa katalog")
            }
            while let file = enumerator.nextObject() as? String {
                guard !file.hasPrefix(".") else { continue }
                let fullPath = path + "/" + file
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    pendingCommits[path]?.stagedFiles[file] = fm.contents(atPath: fullPath)
                }
            }
        } else {
            for arg in args {
                let absPath = arg.hasPrefix("/") ? arg : path + "/" + arg
                let relPath = arg.hasPrefix("/") ? String(arg.dropFirst(path.count + 1)) : arg
                pendingCommits[path]?.stagedFiles[relPath] = fm.contents(atPath: absPath)
            }
        }
        let count = pendingCommits[path]?.stagedFiles.count ?? 0
        return GitResult(success: true, output: "\(count) fil(er) stagade")
    }

    // MARK: Commit (record message, actual push happens at push time)

    private func apiCommit(args: [String], at workDir: String?) -> GitResult {
        guard let path = workDir else { return GitResult(success: false, output: "commit: sökväg saknas") }
        guard pendingCommits[path] != nil else {
            return GitResult(success: false, output: "Inga stagade ändringar")
        }
        var message = "Navi auto-commit \(Date().formatted(.dateTime.hour().minute()))"
        if let mIdx = args.firstIndex(of: "-m"), mIdx + 1 < args.count {
            message = args[mIdx + 1]
        }
        pendingCommits[path]?.pendingMessage = message
        return GitResult(success: true, output: "[staged] \(message)")
    }

    // MARK: Push via GitHub Git Data API

    private func apiPush(at workDir: String?, args: [String]) async -> GitResult {
        guard let path = workDir, var pending = pendingCommits[path] else {
            return GitResult(success: false, output: "push: inga stagade ändringar att pusha")
        }
        guard let token else { return GitResult(success: false, output: "GitHub token saknas") }

        let branch = pending.branch
        let fullName = pending.repoFullName
        let message = pending.pendingMessage ?? "Navi auto-commit \(Date().formatted(.dateTime.hour().minute()))"

        do {
            // 1. Current HEAD SHA
            struct RefObj: Codable { struct Obj: Codable { let sha: String }; let object: Obj }
            let refReq = try makeRequest(path: "/repos/\(fullName)/git/refs/heads/\(branch)", token: token)
            let (refData, refResp) = try await URLSession.shared.data(for: refReq)
            try checkResponse(refResp, data: refData)
            let parentSHA = try JSONDecoder().decode(RefObj.self, from: refData).object.sha

            // 2. Parent tree SHA
            struct CommitObj: Codable { struct Tree: Codable { let sha: String }; let tree: Tree }
            let commitReq = try makeRequest(path: "/repos/\(fullName)/git/commits/\(parentSHA)", token: token)
            let (commitData, commitResp) = try await URLSession.shared.data(for: commitReq)
            try checkResponse(commitResp, data: commitData)
            let baseTreeSHA = try JSONDecoder().decode(CommitObj.self, from: commitData).tree.sha

            // 3. Create blobs for staged files
            struct BlobResp: Codable { let sha: String }
            var treeEntries: [[String: Any]] = []

            for (filePath, fileData) in pending.stagedFiles {
                if let data = fileData {
                    var blobReq = try makeRequest(path: "/repos/\(fullName)/git/blobs", token: token)
                    blobReq.httpMethod = "POST"
                    blobReq.httpBody = try JSONSerialization.data(withJSONObject: [
                        "content": data.base64EncodedString(), "encoding": "base64"
                    ])
                    blobReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    let (blobData, blobResp) = try await URLSession.shared.data(for: blobReq)
                    try checkResponse(blobResp, data: blobData)
                    let blobSHA = try JSONDecoder().decode(BlobResp.self, from: blobData).sha
                    treeEntries.append(["path": filePath, "mode": "100644", "type": "blob", "sha": blobSHA])
                } else {
                    // Deletion: sha: null removes the file from the tree
                    treeEntries.append(["path": filePath, "mode": "100644", "type": "blob", "sha": NSNull()])
                }
            }

            // 4. New tree
            struct TreeResp: Codable { let sha: String }
            var treeReq = try makeRequest(path: "/repos/\(fullName)/git/trees", token: token)
            treeReq.httpMethod = "POST"
            treeReq.httpBody = try JSONSerialization.data(withJSONObject: ["base_tree": baseTreeSHA, "tree": treeEntries])
            treeReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (treeData, treeResp) = try await URLSession.shared.data(for: treeReq)
            try checkResponse(treeResp, data: treeData)
            let newTreeSHA = try JSONDecoder().decode(TreeResp.self, from: treeData).sha

            // 5. Create commit
            struct NewCommitResp: Codable { let sha: String }
            var newCommitReq = try makeRequest(path: "/repos/\(fullName)/git/commits", token: token)
            newCommitReq.httpMethod = "POST"
            newCommitReq.httpBody = try JSONSerialization.data(withJSONObject: [
                "message": message, "tree": newTreeSHA, "parents": [parentSHA]
            ])
            newCommitReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (ncData, ncResp) = try await URLSession.shared.data(for: newCommitReq)
            try checkResponse(ncResp, data: ncData)
            let newSHA = try JSONDecoder().decode(NewCommitResp.self, from: ncData).sha

            // 6. Update branch ref
            var updateReq = try makeRequest(path: "/repos/\(fullName)/git/refs/heads/\(branch)", token: token)
            updateReq.httpMethod = "PATCH"
            updateReq.httpBody = try JSONSerialization.data(withJSONObject: ["sha": newSHA])
            updateReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, updateResp) = try await URLSession.shared.data(for: updateReq)
            try checkResponse(updateResp, data: Data())

            pendingCommits[path] = nil
            saveGitMeta(at: path, repoFullName: fullName, branch: branch, sha: newSHA)
            commitCache["\(fullName)/\(branch)"] = nil
            return GitResult(success: true, output: "Pushad \(newSHA.prefix(7)) → \(branch) ✓")
        } catch {
            return GitResult(success: false, output: "push misslyckades: \(error.localizedDescription)")
        }
    }

    // MARK: Status

    private func apiStatus(at workDir: String?) async -> GitResult {
        guard let path = workDir else { return GitResult(success: true, output: "") }
        if let pending = pendingCommits[path], !pending.stagedFiles.isEmpty {
            let lines = pending.stagedFiles.keys.sorted().map { "M  \($0)" }.joined(separator: "\n")
            return GitResult(success: true, output: lines)
        }
        return GitResult(success: true, output: "")
    }

    // MARK: Log

    private func apiLog(at workDir: String?) async -> GitResult {
        guard let path = workDir, let meta = loadGitMeta(at: path) else {
            return GitResult(success: true, output: "Inga commits (ej klonat)")
        }
        guard let repo = repos.first(where: { $0.fullName == meta.repoFullName }) else {
            return GitResult(success: true, output: "Repo \(meta.repoFullName) hittades inte i lokal cache")
        }
        let commits = await fetchCommits(for: repo, branch: meta.branch)
        if commits.isEmpty { return GitResult(success: true, output: "Inga commits hittades") }
        let log = commits.map { c in
            let firstLine = c.commit.message.components(separatedBy: "\n").first ?? c.commit.message
            return "\(c.sha.prefix(7)) \(c.commit.author.date.prefix(10)) \(c.commit.author.name): \(firstLine)"
        }.joined(separator: "\n")
        return GitResult(success: true, output: log)
    }
}

// MARK: - Error types

enum GitHubError: LocalizedError {
    case unauthorized
    case forbidden
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Ogiltig GitHub-token. Kontrollera din token i Inställningar."
        case .forbidden: return "Åtkomst nekad. Kontrollera token-behörigheter."
        case .apiError(let msg): return "GitHub API-fel: \(msg)"
        }
    }
}

private struct GitHubAPIError: Codable {
    let message: String
}

extension Notification.Name {
    static let didOpenGitHubProject = Notification.Name("didOpenGitHubProject")
}
