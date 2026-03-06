import SwiftUI

enum AppSection: String, Hashable { case project, pureChat, browser }

struct ContentView: View {
    @StateObject private var projectStore = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @StateObject private var settings = SettingsStore.shared
    @StateObject private var statusBroadcaster = DeviceStatusBroadcaster.shared

    @State private var showSettings = false
    @State private var showNewProject = false
    @State private var selectedTab: AppTab = .chat
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var macSection: AppSection = .project

    var activeProject: EonProject? { projectStore.activeProject }
    var activeAgent: ProjectAgent? {
        guard let project = activeProject else { return nil }
        return agentPool.agent(for: project)
    }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    var macLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedProject: $projectStore.activeProject,
                showNewProject: $showNewProject,
                section: $macSection
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 350)
        } detail: {
            switch macSection {
            case .pureChat:
                PureChatView()
            case .browser:
                BrowserView()
            case .project:
                if let project = activeProject, let agent = activeAgent {
                    MacMainView(project: project, agent: agent, selectedTab: $selectedTab)
                } else {
                    WelcomeView(showNewProject: $showNewProject)
                }
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                StatusBarView()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Inställningar")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(width: 560, height: 640)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
        }
        .onAppear {
            BackgroundDaemon.shared.start()
        }
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    var iOSLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                if let project = activeProject, let agent = activeAgent {
                    ChatView(agent: agent)
                        .navigationTitle(project.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                NavigationLink {
                                    SidebarView(
                                        selectedProject: $projectStore.activeProject,
                                        showNewProject: $showNewProject
                                    )
                                } label: {
                                    Image(systemName: "sidebar.left")
                                }
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                macStatusBadge
                            }
                        }
                } else {
                    WelcomeView(showNewProject: $showNewProject)
                        .navigationTitle("EonCode")
                }
            }
            .tabItem {
                Label("Chatt", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(AppTab.chat)

            NavigationView {
                if let project = activeProject {
                    FileTreeAndEditorView(project: project)
                        .navigationTitle(project.name)
                } else {
                    WelcomeView(showNewProject: $showNewProject)
                }
            }
            .tabItem {
                Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .tag(AppTab.editor)

            NavigationView {
                MultiProjectDashboard()
                    .navigationTitle("Agenter")
            }
            .tabItem {
                Label("Agenter", systemImage: "gearshape.2")
            }
            .tag(AppTab.agents)
            .badge(agentPool.activeCount > 0 ? "\(agentPool.activeCount)" : nil)

            // Pure chat tab
            NavigationView {
                PureChatView()
                    .navigationTitle("Chatt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                _ = ChatManager.shared.newConversation()
                            } label: {
                                Image(systemName: "square.and.pencil")
                                    .foregroundColor(.accentEon)
                            }
                        }
                    }
            }
            .tabItem {
                Label("Chatt", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(AppTab.pureChat)

            // Browser tab
            NavigationView {
                BrowserView()
                    .navigationTitle("Webb")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Webb", systemImage: "globe")
            }
            .tag(AppTab.browser)

            NavigationView {
                SettingsView()
                    .navigationTitle("Inställningar")
            }
            .tabItem {
                Label("Inställningar", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .sheet(isPresented: $showNewProject) {
            NewProjectView()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            PeerSyncEngine.shared.startBrowsing()
        }
    }

    var macStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusBroadcaster.remoteMacIsOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text("Mac")
                .font(.system(size: 12))
                .foregroundColor(statusBroadcaster.remoteMacIsOnline ? .primary : .secondary)
        }
    }
    #endif
}

// MARK: - Tabs

enum AppTab: Int, Hashable {
    case chat, editor, agents, pureChat, browser, settings
}

// MARK: - macOS Main View

#if os(macOS)
struct MacMainView: View {
    let project: EonProject
    @ObservedObject var agent: ProjectAgent
    @Binding var selectedTab: AppTab

    @State private var selectedNode: FileNode?
    @State private var fileContent = ""
    @State private var showVersions = false
    @State private var splitFraction: CGFloat = 0.45

    var body: some View {
        HSplitView {
            // File tree + editor
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    TabButton(title: "Filer", icon: "folder", tab: .editor, selected: $selectedTab)
                    TabButton(title: "Versioner", icon: "clock.arrow.circlepath", tab: .agents, selected: $selectedTab)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                Divider().opacity(0.2)

                if selectedTab == .editor {
                    // Split: file tree on left, editor on right
                    HSplitView {
                        FileTreeView(project: project, selectedNode: $selectedNode)
                            .frame(minWidth: 180, maxWidth: 280)

                        if let node = selectedNode, !node.isDirectory {
                            CodeEditorView(
                                content: $fileContent,
                                fileType: node.fileType,
                                onSave: { newContent in
                                    try? newContent.write(toFile: node.path, atomically: true, encoding: .utf8)
                                }
                            )
                            .onAppear {
                                fileContent = (try? String(contentsOfFile: node.path)) ?? ""
                            }
                            .onChange(of: selectedNode?.id) { _ in
                                if let n = selectedNode, !n.isDirectory {
                                    fileContent = (try? String(contentsOfFile: n.path)) ?? ""
                                }
                            }
                        } else {
                            VStack {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("Välj en fil att redigera")
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else if selectedTab == .agents {
                    AgentStatusView(agent: agent)
                }
            }
            .frame(minWidth: 400)

            // Chat panel
            VStack(spacing: 0) {
                ChatView(agent: agent)
            }
            .frame(minWidth: 320, maxWidth: 500)
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let tab: AppTab
    @Binding var selected: AppTab

    var isSelected: Bool { selected == tab }

    var body: some View {
        Button {
            selected = tab
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentEon.opacity(0.2) : Color.clear)
            )
            .foregroundColor(isSelected ? .accentEon : .secondary)
        }
        .buttonStyle(.plain)
    }
}
#endif

// MARK: - iOS file tree + editor

#if os(iOS)
struct FileTreeAndEditorView: View {
    let project: EonProject
    @State private var selectedNode: FileNode?
    @State private var fileContent = ""

    var body: some View {
        HSplitOrStack {
            FileTreeView(project: project, selectedNode: $selectedNode)
                .frame(maxWidth: 260)

            if let node = selectedNode, !node.isDirectory {
                CodeEditorView(
                    content: $fileContent,
                    fileType: node.fileType,
                    onSave: { newContent in
                        try? newContent.write(toFile: node.path, atomically: true, encoding: .utf8)
                    }
                )
                .onAppear {
                    fileContent = (try? String(contentsOfFile: node.path)) ?? ""
                }
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Välj en fil")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(selectedNode?.name ?? project.name)
    }
}

// Adaptive layout: split on iPad, stack on iPhone
struct HSplitOrStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            HStack(spacing: 0) { content() }
        } else {
            content()
        }
    }
}
#endif

// MARK: - Welcome View

struct WelcomeView: View {
    @Binding var showNewProject: Bool
    @StateObject private var store = ProjectStore.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundColor(.accentEon)
                Text("EonCode")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("AI-driven kodningsagent")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            if store.projects.isEmpty {
                VStack(spacing: 16) {
                    GlassButton("Skapa nytt projekt", icon: "plus", isPrimary: true) {
                        showNewProject = true
                    }
                    Text("Eller öppna ett befintligt projekt från sidopanelen")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Senaste projekt")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    ForEach(store.projects.prefix(5)) { project in
                        Button {
                            store.activeProject = project
                        } label: {
                            HStack {
                                Circle()
                                    .fill(project.color.color)
                                    .frame(width: 10, height: 10)
                                Text(project.name)
                                    .font(.system(size: 14))
                                Spacer()
                                Text(project.modifiedAt.relativeString)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }

                    GlassButton("Nytt projekt", icon: "plus") {
                        showNewProject = true
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: 400)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
}

// MARK: - New Project View

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ProjectStore.shared

    @State private var name = ""
    @State private var projectType = "swift"
    @State private var useICloud = true
    @State private var isCreating = false

    let projectTypes = ["swift", "python", "node", "generic"]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                GlassTextField(placeholder: "Projektnamn", text: $name)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Projekttyp")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Picker("Typ", selection: $projectType) {
                        ForEach(projectTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Spara i iCloud Drive", isOn: $useICloud)
                    .toggleStyle(.switch)

                Spacer()

                GlassButton("Skapa projekt", icon: "plus", isPrimary: true) {
                    Task { await createProject() }
                }
                .disabled(name.isBlank || isCreating)
            }
            .padding()
            .navigationTitle("Nytt projekt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            #endif
        }
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }

    private func createProject() async {
        isCreating = true
        defer { isCreating = false }

        let baseURL: URL
        if useICloud, let icloudRoot = iCloudSyncEngine.shared.projectsRoot {
            baseURL = icloudRoot
        } else {
            #if os(macOS)
            baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("EonCode/Projects")
            #else
            baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("EonCode/Projects")
            #endif
        }

        let project = await store.create(name: name, at: baseURL.appendingPathComponent(name))

        #if os(macOS)
        if let url = project.resolvedURL {
            try? FileSystemAgent.shared.createNewProject(
                name: name,
                type: FileSystemAgent.ProjectType(rawValue: projectType) ?? .generic,
                at: url.deletingLastPathComponent()
            )
        }
        #endif

        store.activeProject = project
        dismiss()
    }
}
