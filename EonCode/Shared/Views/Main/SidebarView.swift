import SwiftUI

struct SidebarView: View {
    @Binding var selectedProject: EonProject?
    @Binding var showNewProject: Bool
    @Binding var section: AppSection
    @StateObject private var store = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @StateObject private var chatManager = ChatManager.shared
    @State private var searchText = ""

    var filteredProjects: [EonProject] {
        if searchText.isEmpty { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section switcher (macOS only)
            #if os(macOS)
            sectionSwitcher
            Divider().opacity(0.15)
            #endif

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField(section == .pureChat ? "Sök chattar…" : "Sök projekt…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider().opacity(0.15)

            // Content based on section
            if section == .pureChat {
                chatList
            } else {
                projectList
            }

            Divider().opacity(0.15)

            bottomBar
        }
        .background(Color.sidebarBackground)
    }

    // MARK: - macOS section switcher

    #if os(macOS)
    var sectionSwitcher: some View {
        HStack(spacing: 4) {
            SectionButton(title: "Projekt", icon: "folder", target: .project, section: $section)
            SectionButton(title: "Chatt", icon: "bubble.left.and.bubble.right", target: .pureChat, section: $section)
            SectionButton(title: "Webb", icon: "globe", target: .browser, section: $section)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
    #endif

    // MARK: - Project list

    var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let favorites = filteredProjects.filter { $0.isFavorite }
                if !favorites.isEmpty {
                    SidebarSectionHeader(title: "Favoriter")
                    ForEach(favorites) { project in
                        ProjectRow(project: project, selectedProject: $selectedProject)
                            .onTapGesture { section = .project }
                    }
                }

                let nonFavorites = filteredProjects.filter { !$0.isFavorite }
                if !nonFavorites.isEmpty {
                    SidebarSectionHeader(title: favorites.isEmpty ? "Projekt" : "Alla projekt")
                    ForEach(nonFavorites) { project in
                        ProjectRow(project: project, selectedProject: $selectedProject)
                            .onTapGesture { section = .project }
                    }
                }

                if filteredProjects.isEmpty {
                    Text(searchText.isEmpty ? "Inga projekt" : "Inga träffar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Chat list

    var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let chats = searchText.isEmpty
                    ? chatManager.conversations
                    : chatManager.conversations.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

                SidebarSectionHeader(title: "Chattar")
                ForEach(chats) { conv in
                    ChatConversationRow(
                        conversation: conv,
                        isSelected: chatManager.activeConversation?.id == conv.id,
                        onSelect: { chatManager.activeConversation = conv }
                    )
                }

                if chats.isEmpty {
                    Text(searchText.isEmpty ? "Inga chattar" : "Inga träffar")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 20)
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            if agentPool.activeCount > 0 && section == .project {
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentEon)
                        .symbolEffect(.rotate, options: .repeating)
                    Text("\(agentPool.activeCount) agent(er) aktiv")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentEon.opacity(0.08))
            }

            if section == .pureChat {
                Button {
                    _ = chatManager.newConversation()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentEon)
                        Text("Ny chatt")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else if section == .project {
                Button {
                    showNewProject = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentEon)
                        Text("Nytt projekt")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Section button (macOS)

struct SectionButton: View {
    let title: String
    let icon: String
    let target: AppSection
    @Binding var section: AppSection

    var isSelected: Bool { section == target }

    var body: some View {
        Button { section = target } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentEon.opacity(0.2) : Color.clear)
            )
            .foregroundColor(isSelected ? .accentEon : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat conversation row

struct ChatConversationRow: View {
    let conversation: ChatConversation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentEon : .secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    Text("\(conversation.messages.count) meddelanden")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Spacer()

                if conversation.totalCostSEK > 0 {
                    Text(CostCalculator.shared.formatSEK(conversation.totalCostSEK))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentEon.opacity(0.25) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Öppna", action: onSelect)
            Divider()
            Button("Radera", role: .destructive) {
                Task { await ChatManager.shared.delete(conversation) }
            }
        }
    }
}

struct SidebarSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

struct ProjectRow: View {
    let project: EonProject
    @Binding var selectedProject: EonProject?
    @StateObject private var agentPool = AgentPool.shared

    private var isSelected: Bool { selectedProject?.id == project.id }
    private var agent: ProjectAgent? { agentPool.agents[project.id] }
    private var isRunning: Bool { agent?.isRunning ?? false }

    var body: some View {
        Button {
            selectedProject = project
        } label: {
            HStack(spacing: 8) {
                // Color dot + running indicator
                ZStack {
                    Circle()
                        .fill(project.color.color.opacity(0.8))
                        .frame(width: 10, height: 10)
                    if isRunning {
                        Circle()
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: 14, height: 14)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)

                    if isRunning, let status = agent?.currentStatus, !status.isEmpty {
                        Text(status.prefix(30))
                            .font(.system(size: 10))
                            .foregroundColor(.green.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text(project.modifiedAt.relativeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }

                Spacer()

                if isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentEon.opacity(0.25) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu {
            Button("Öppna") { selectedProject = project }
            Button(project.isFavorite ? "Ta bort favorit" : "Markera som favorit") {
                var updated = project
                updated.isFavorite.toggle()
                Task { await ProjectStore.shared.save(updated) }
            }
            Divider()
            Button("Ta bort", role: .destructive) {
                Task { await ProjectStore.shared.delete(project) }
            }
        }
    }
}
