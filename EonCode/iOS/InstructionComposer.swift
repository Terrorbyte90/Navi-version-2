#if os(iOS)
import Foundation
import SwiftUI

@MainActor
final class InstructionComposer: ObservableObject {
    static let shared = InstructionComposer()

    @Published var pendingInstructions: [Instruction] = []
    @Published var isSending = false

    private init() {
        Task { await loadPending() }
    }

    // MARK: - Compose & queue

    func queue(
        instruction: String,
        projectID: UUID? = nil,
        conversationID: UUID? = nil
    ) async {
        let instr = Instruction(
            instruction: instruction,
            projectID: projectID,
            conversationID: conversationID
        )

        pendingInstructions.append(instr)
        await sendToMac(instr)
    }

    private func sendToMac(_ instruction: Instruction) async {
        isSending = true
        defer { isSending = false }

        // 1. iCloud (always — guaranteed delivery even if Mac is offline)
        await InstructionQueue.shared.enqueue(instruction)

        // 2. Bonjour peer connection (lowest latency when on same Wi-Fi)
        if let conn = PeerSyncEngine.shared.connections.first {
            let packet = SyncPacket(
                type: "instruction",
                metadata: [:],
                data: try? instruction.encoded()
            )
            PeerSyncEngine.shared.sendSyncPacket(packet, to: conn)
        }

        // 3. Local HTTP (fast when Mac is reachable, auto-discovers if needed)
        if SettingsStore.shared.macServerURL.isEmpty {
            // Try to discover Mac before giving up
            await LocalNetworkClient.shared.discoverMac()
        }
        try? await LocalNetworkClient.shared.postInstruction(instruction)
    }

    // MARK: - Load pending from iCloud

    func loadPending() async {
        pendingInstructions = await InstructionQueue.shared.pendingInstructions()
    }

    // MARK: - Selective queueing (only terminal-requiring actions)

    /// Queues only the actions that require Mac (terminal/build). Returns true if anything was queued.
    @discardableResult
    func queueMacActions(
        from steps: [(description: String, action: AgentAction)],
        projectID: UUID? = nil
    ) async -> Int {
        let macSteps = steps.filter { !$0.action.canRunOnIOS }
        for step in macSteps {
            let label = step.action.queueLabel
            await queue(
                instruction: "[\(step.description)] \(label)",
                projectID: projectID
            )
        }
        return macSteps.count
    }

    /// Queue a single AgentAction if it requires Mac; skip if it can run locally.
    @discardableResult
    func queueIfNeeded(
        _ action: AgentAction,
        description: String,
        projectID: UUID? = nil
    ) async -> Bool {
        guard action.requiresMac else { return false }
        await queue(
            instruction: "[\(description)] \(action.queueLabel)",
            projectID: projectID
        )
        return true
    }

    // MARK: - Quick actions

    func buildProject(_ path: String, projectID: UUID? = nil) async {
        await queue(instruction: "Bygg projektet på: \(path)", projectID: projectID)
    }

    func runTests(_ path: String, projectID: UUID? = nil) async {
        await queue(instruction: "Kör tester för projektet på: \(path)", projectID: projectID)
    }

    func deploy(_ instruction: String, projectID: UUID? = nil) async {
        await queue(instruction: instruction, projectID: projectID)
    }
}

#endif
