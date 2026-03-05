import Foundation

@MainActor
final class BranchManager: ObservableObject {
    static let shared = BranchManager()

    @Published var branches: [UUID: [Branch]] = [:]

    private init() {}

    func createBranch(name: String, from parentVersionID: UUID?, projectID: UUID) -> Branch {
        let branch = Branch(name: name, projectID: projectID, parentVersionID: parentVersionID)
        var projectBranches = branches[projectID] ?? []
        projectBranches.append(branch)
        branches[projectID] = projectBranches
        return branch
    }

    func branchesForProject(_ id: UUID) -> [Branch] {
        branches[id] ?? [Branch(name: "main", projectID: id, parentVersionID: nil)]
    }
}

struct Branch: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var projectID: UUID
    var parentVersionID: UUID?
    var createdAt: Date = Date()
    var isDefault: Bool { name == "main" }
}
