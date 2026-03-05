import SwiftUI

struct SidebarView: View {
    @Binding var selectedProject: EonProject?
    @Binding var showNewProject: Bool
    @StateObject private var store = ProjectStore.shared
    @StateObject private var agentPool = AgentPool.shared
    @State private var searchText = ""

    var filteredProjects: [EonProject] {
        if searchText.isEmpty { return store.projects }
        return store.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Sök projekt…", text: $searchText)
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

            // Projects list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Favorites
                    let favorites = filteredProjects.filter { $0.isFavorite }
                    if !favorites.isEmpty {
                        SidebarSectionHeader(title: "Favoriter")
                        ForEach(favorites) { project in
                            ProjectRow(project: project, selectedProject: $selectedProject)
                        }
                    }

                    // All projects
                    let nonFavorites = filteredProjects.filter { !$0.isFavorite }
                    if !nonFavorites.isEmpty {
                        SidebarSectionHeader(title: favorites.isEmpty ? "Projekt" : "Alla projekt")
                        ForEach(nonFavorites) { project in
                            ProjectRow(project: project, selectedProject: $selectedProject)
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

            Divider().opacity(0.15)

            // Active agents status
            if agentPool.activeCount > 0 {
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

            // New project button
            Button {
                showNewProject = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentEon)
                    Text("Nytt projekt")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(Color.sidebarBackground)
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
