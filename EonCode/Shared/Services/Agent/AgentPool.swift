import Foundation
import Combine

@MainActor
final class AgentPool: ObservableObject {
    static let shared = AgentPool()

    @Published var agents: [UUID: ProjectAgent] = [:]

    private init() {}

    func agent(for project: EonProject) -> ProjectAgent {
        if let existing = agents[project.id] {
            return existing
        }
        let agent = ProjectAgent(project: project)
        agents[project.id] = agent
        return agent
    }

    func stopAll() {
        for agent in agents.values {
            agent.stop()
        }
    }

    var activeCount: Int {
        agents.values.filter { $0.isRunning }.count
    }
}

@MainActor
final class ProjectAgent: ObservableObject, Identifiable {
    let id: UUID
    let project: EonProject

    @Published var isRunning = false
    @Published var currentStatus = ""
    @Published var conversation: Conversation
    @Published var streamingText = ""
    @Published var lastCostSEK: Double = 0
    @Published var sessionCostSEK: Double = 0

    private let engine = AgentEngine()
    private var task: Task<Void, Never>?

    init(project: EonProject) {
        self.id = project.id
        self.project = project
        self.conversation = Conversation(projectID: project.id, model: project.activeModel)
        engine.setProject(project)
    }

    func sendMessage(
        _ text: String,
        images: [Data] = [],
        isAgentMode: Bool = false
    ) {
        guard !isRunning else { return }

        task = Task {
            isRunning = true
            streamingText = ""
            defer { isRunning = false }

            if isAgentMode {
                let agentTask = AgentTask(projectID: project.id, instruction: text)
                await engine.run(
                    task: agentTask,
                    conversation: &conversation,
                    onUpdate: { [weak self] update in
                        self?.streamingText = update
                    }
                )
            } else {
                await engine.sendChat(
                    userText: text,
                    images: images,
                    conversation: &conversation,
                    onToken: { [weak self] token in
                        self?.streamingText += token
                    },
                    onComplete: { [weak self] usage in
                        guard let self = self else { return }
                        let (_, sek) = CostCalculator.shared.calculate(usage: usage, model: self.conversation.model)
                        self.lastCostSEK = sek
                        self.sessionCostSEK += sek
                        self.streamingText = ""
                    },
                    onError: { [weak self] error in
                        self?.currentStatus = error.localizedDescription
                        self?.streamingText = ""
                    }
                )
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }
}
