import SwiftUI

// MARK: - GitHubView
// Main GitHub integration view — shows repos, branches, commit history,
// and lets the user open any repo as an EonCode project.

struct GitHubView: View {
    @StateObject private var gh = GitHubManager.shared
    @State private var searchText = ""
    @State private var selectedRepo: GitHubRepo?
    @State private var showTokenEntry = false
    @State private var showCreateBranch = false

    var body: some View {
        Group {
            switch gh.authState {
            case .notAuthorized:
                authGateView
            case .loading:
                loadingView
            case .error(let msg):
                errorView(msg)
            case .authorized:
                #if os(macOS)
                macLayout
                #else
                iOSLayout
                #endif
            }
        }
        .onAppear {
            Task { await gh.verifyToken() }
        }
        .sheet(isPresented: $showTokenEntry) {
            GitHubTokenSheet()
        }
    }

    // MARK: - Auth gate

    var authGateView: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 52))
                    .foregroundColor(.primary.opacity(0.7))
                Text("GitHub")
                    .font(.system(size: 32, weight: .bold))
                Text("Anslut ditt GitHub-konto för att komma åt alla dina repos, byta branch och koda direkt i EonCode.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button {
                    showTokenEntry = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                        Text("Anslut med GitHub Token")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, 14)
                    .background(Color.accentEon)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)

                Text("Kräver en Personal Access Token med repo, read:org och workflow-behörigheter.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
        .sheet(isPresented: $showTokenEntry) {
            GitHubTokenSheet()
        }
    }

    var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Ansluter till GitHub…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Anslutningsfel")
                .font(.system(size: 18, weight: .semibold))
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                Button("Försök igen") {
                    Task { await gh.verifyToken() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentEon)
                Button("Byt token") { showTokenEntry = true }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }

    // MARK: - macOS layout

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            repoListPanel
                .frame(minWidth: 260, maxWidth: 340)
            if let repo = selectedRepo {
                repoDetailPanel(repo)
            } else {
                repoEmptyDetail
            }
        }
    }

    var repoListPanel: some View {
        VStack(spacing: 0) {
            repoListHeader
            Divider().opacity(0.12)
            repoSearchBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            Divider().opacity(0.08)
            repoList
        }
        .background(Color.sidebarBackground)
    }

    var repoListHeader: some View {
        HStack {
            if case .authorized(let user) = gh.authState {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentEon)
                    Text(user.login)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            Spacer()
            Button {
                Task { await gh.fetchRepos() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Uppdatera repos")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    func repoDetailPanel(_ repo: GitHubRepo) -> some View {
        RepoDetailView(repo: repo)
    }

    var repoEmptyDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.2))
            Text("Välj ett repo")
                .font(.system(size: 15))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
    #endif

    // MARK: - iOS layout

    var iOSLayout: some View {
        NavigationView {
            VStack(spacing: 0) {
                iOSHeader
                Divider().opacity(0.12)
                repoSearchBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                repoList
            }
            .background(Color.chatBackground)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }

    var iOSHeader: some View {
        HStack {
            if case .authorized(let user) = gh.authState {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.accentEon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GitHub")
                            .font(.system(size: 16, weight: .bold))
                        Text(user.login)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                Task { await gh.fetchRepos() }
            } label: {
                Image(systemName: gh.isLoadingRepos ? "arrow.clockwise" : "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(gh.isLoadingRepos ? 360 : 0))
                    .animation(gh.isLoadingRepos ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: gh.isLoadingRepos)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Shared: search bar

    var repoSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
            TextField("Sök repos…", text: $searchText)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07))
        .cornerRadius(7)
    }

    // MARK: - Shared: repo list

    var filteredRepos: [GitHubRepo] {
        if searchText.isEmpty { return gh.repos }
        return gh.repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var repoList: some View {
        Group {
            if gh.isLoadingRepos && gh.repos.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Hämtar repos…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = gh.repoError {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredRepos) { repo in
                            #if os(macOS)
                            RepoRow(repo: repo, isSelected: selectedRepo?.id == repo.id) {
                                selectedRepo = repo
                            }
                            #else
                            NavigationLink(destination: RepoDetailView(repo: repo)) {
                                RepoRow(repo: repo, isSelected: false) {}
                            }
                            .buttonStyle(.plain)
                            #endif
                        }
                        if filteredRepos.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.2))
                                Text(searchText.isEmpty ? "Inga repos" : "Inga träffar")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - Repo row

struct RepoRow: View {
    let repo: GitHubRepo
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentEon : .secondary.opacity(0.6))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(repo.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : .primary)
                            .lineLimit(1)
                        if repo.isPrivate {
                            Text("privat")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 8) {
                        // Branch pill
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text(repo.currentBranch)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary.opacity(0.6))

                        if let lang = repo.language {
                            Text(lang)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                        }

                        Spacer()

                        Text(repo.updatedAt.relativeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentEon.opacity(0.25) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }
}

// MARK: - Repo detail view

struct RepoDetailView: View {
    let repo: GitHubRepo
    @StateObject private var gh = GitHubManager.shared
    @State private var branches: [GitHubBranch] = []
    @State private var commits: [GitHubCommit] = []
    @State private var showBranchPicker = false
    @State private var showCreateBranch = false
    @State private var newBranchName = ""
    @State private var isLoadingBranches = false
    @State private var isLoadingCommits = false
    @State private var isCloning = false
    @State private var selectedTab = 0

    var currentRepo: GitHubRepo {
        gh.repos.first(where: { $0.id == repo.id }) ?? repo
    }

    var localPath: String? { gh.clonedRepos[repo.fullName] }
    var syncStatusMsg: String? { gh.syncStatus[repo.fullName] }

    var body: some View {
        VStack(spacing: 0) {
            repoHeader
            Divider().opacity(0.12)

            // Tab bar
            HStack(spacing: 0) {
                tabPill("Commits", idx: 0)
                tabPill("Filer", idx: 1)
                tabPill("Info", idx: 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.08)

            Group {
                switch selectedTab {
                case 0: commitsTab
                case 1: filesTab
                default: infoTab
                }
            }
        }
        .background(Color.chatBackground)
        .onAppear {
            Task {
                isLoadingBranches = true
                branches = await gh.fetchBranches(for: repo)
                isLoadingBranches = false
                isLoadingCommits = true
                commits = await gh.fetchCommits(for: currentRepo)
                isLoadingCommits = false
            }
        }
        .onChange(of: currentRepo.currentBranch) { _ in
            Task {
                isLoadingCommits = true
                commits = await gh.fetchCommits(for: currentRepo)
                isLoadingCommits = false
            }
        }
        .sheet(isPresented: $showCreateBranch) {
            CreateBranchSheet(repo: currentRepo, baseBranch: currentRepo.currentBranch)
        }
    }

    // MARK: - Header

    var repoHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(repo.name)
                            .font(.system(size: 18, weight: .bold))
                        if repo.isPrivate {
                            Label("Privat", systemImage: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    Text(repo.fullName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Open as project button
                Button {
                    Task {
                        isCloning = true
                        _ = await gh.openAsProject(repo: currentRepo)
                        isCloning = false
                    }
                } label: {
                    if isCloning {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label(localPath != nil ? "Öppna" : "Klona & öppna", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.accentEon)
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCloning)
            }

            // Branch selector + actions
            HStack(spacing: 8) {
                // Branch picker
                Menu {
                    if isLoadingBranches {
                        Text("Laddar…")
                    } else {
                        ForEach(branches) { branch in
                            Button {
                                gh.setBranch(branch.name, for: repo.id)
                                if let path = localPath {
                                    Task { await gh.switchBranch(to: branch.name, at: path) }
                                }
                            } label: {
                                HStack {
                                    Text(branch.name)
                                    if branch.name == currentRepo.currentBranch {
                                        Image(systemName: "checkmark")
                                    }
                                    if branch.protected {
                                        Image(systemName: "lock.fill")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button {
                            showCreateBranch = true
                        } label: {
                            Label("Ny branch…", systemImage: "plus")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 11))
                        Text(currentRepo.currentBranch)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(7)
                }
                .buttonStyle(.plain)

                // Pull
                Button {
                    Task { await gh.pull(repo: currentRepo) }
                } label: {
                    Label("Pull", systemImage: "arrow.down.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Hämta senaste ändringar")

                // Push
                Button {
                    Task { await gh.push(repo: currentRepo) }
                } label: {
                    Label("Push", systemImage: "arrow.up.circle")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .help("Pusha lokala ändringar")

                Spacer()

                // Sync status
                if let status = syncStatusMsg {
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(status.contains("✓") ? .green : .secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Commits tab

    var commitsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if isLoadingCommits {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if commits.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("Inga commits")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    ForEach(commits) { commit in
                        CommitRow(commit: commit)
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Files tab

    var filesTab: some View {
        Group {
            if let path = localPath {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lokal sökväg:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentEon)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        Divider().opacity(0.1)
                        LocalFileList(path: path)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Klona repot för att se filer")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                    Button {
                        Task {
                            isCloning = true
                            _ = await gh.cloneOrOpen(repo: currentRepo)
                            isCloning = false
                        }
                    } label: {
                        Label("Klona", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.accentEon)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCloning)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Info tab

    var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let desc = repo.description, !desc.isEmpty {
                    infoRow("Beskrivning", value: desc)
                }
                infoRow("Standard-branch", value: repo.defaultBranch)
                if let lang = repo.language {
                    infoRow("Språk", value: lang)
                }
                infoRow("Stjärnor", value: "\(repo.stargazersCount)")
                infoRow("Synlighet", value: repo.isPrivate ? "Privat" : "Publik")
                infoRow("Senast uppdaterad", value: repo.updatedAt.relativeString)

                Divider().opacity(0.12)

                Link("Öppna på GitHub", destination: URL(string: repo.htmlURL)!)
                    .font(.system(size: 13))
                    .foregroundColor(.accentEon)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func tabPill(_ title: String, idx: Int) -> some View {
        Button { selectedTab = idx } label: {
            Text(title)
                .font(.system(size: 12, weight: selectedTab == idx ? .semibold : .regular))
                .foregroundColor(selectedTab == idx ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selectedTab == idx ? Color.accentEon.opacity(0.3) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Commit row

struct CommitRow: View {
    let commit: GitHubCommit

    var shortSHA: String { String(commit.sha.prefix(7)) }
    var message: String { commit.commit.message.components(separatedBy: "\n").first ?? commit.commit.message }
    var author: String { commit.commit.author.name }
    var date: String {
        let formatter = ISO8601DateFormatter()
        if let d = formatter.date(from: commit.commit.author.date) {
            return d.relativeString
        }
        return commit.commit.author.date
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(shortSHA)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.accentEon)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(author)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))
                    Text(date)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Local file list (simple)

struct LocalFileList: View {
    let path: String
    @State private var files: [String] = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(files, id: \.self) { file in
                HStack(spacing: 8) {
                    Image(systemName: fileIcon(file))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(file)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }
        }
        .onAppear {
            files = (try? FileManager.default.contentsOfDirectory(atPath: path))?.sorted() ?? []
        }
    }

    private func fileIcon(_ name: String) -> String {
        if name.hasPrefix(".") { return "eye.slash" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts": return "doc.text"
        case "json": return "curlybraces"
        case "md": return "doc.richtext"
        case "": return "folder"
        default: return "doc"
        }
    }
}

// MARK: - Create branch sheet

struct CreateBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared
    let repo: GitHubRepo
    let baseBranch: String

    @State private var branchName = ""
    @State private var isCreating = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(.accentEon)
                Text("Ny branch")
                    .font(.system(size: 18, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Branch-namn")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                GlassTextField(placeholder: "feature/min-funktion", text: $branchName)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Baseras på")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                    Text(baseBranch)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.accentEon)
            }

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }

            HStack {
                Button("Avbryt") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        isCreating = true
                        let ok = await gh.createBranch(name: branchName, from: baseBranch, in: repo)
                        isCreating = false
                        if ok { dismiss() } else { error = "Kunde inte skapa branch." }
                    }
                } label: {
                    if isCreating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Skapa")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(branchName.isBlank ? .secondary : .accentEon)
                .disabled(branchName.isBlank || isCreating)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }
}

// MARK: - GitHub Token Sheet

struct GitHubTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gh = GitHubManager.shared

    @State private var tokenInput = ""
    @State private var isVerifying = false
    @State private var error = ""
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 20))
                    .foregroundColor(.accentEon)
                Text("Anslut GitHub")
                    .font(.system(size: 20, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Personal Access Token")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    GlassTextField(
                        placeholder: "ghp_…",
                        text: $tokenInput,
                        isSecure: !isRevealed
                    )
                    Button { isRevealed.toggle() } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Kräver följande behörigheter:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    ForEach(["repo (full access)", "read:org", "workflow", "delete_repo (valfri)"], id: \.self) { perm in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green.opacity(0.7))
                            Text(perm)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 4)

                Link("Skapa token på GitHub →",
                     destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=EonCode")!)
                    .font(.system(size: 12))
                    .foregroundColor(.accentEon)
            }

            if !error.isEmpty {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }

            if gh.token != nil {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("Token sparad och synkad via iCloud Keychain")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                if gh.token != nil {
                    Button("Ta bort token") {
                        gh.deleteToken()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.7))
                }
                Spacer()
                Button("Avbryt") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                Button {
                    Task { await saveAndVerify() }
                } label: {
                    if isVerifying {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Anslut")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(tokenInput.isBlank ? .secondary : .accentEon)
                .disabled(tokenInput.isBlank || isVerifying)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            tokenInput = gh.token ?? ""
        }
    }

    private func saveAndVerify() async {
        isVerifying = true
        error = ""
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try KeychainManager.shared.saveGitHubToken(trimmed)
            await gh.verifyToken()
            if case .authorized = gh.authState {
                dismiss()
            } else if case .error(let msg) = gh.authState {
                error = msg
            }
        } catch {
            self.error = error.localizedDescription
        }
        isVerifying = false
    }
}
