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

        // Try iCloud first
        await InstructionQueue.shared.enqueue(instruction)

        // Try Bonjour if connected peer
        if let conn = PeerSyncEngine.shared.connections.first {
            let packet = SyncPacket(
                type: "instruction",
                metadata: [:],
                data: try? instruction.encoded()
            )
            PeerSyncEngine.shared.sendSyncPacket(packet, to: conn)
        }

        // Try local HTTP as fallback
        if !SettingsStore.shared.macServerURL.isEmpty,
           let macURL = URL(string: SettingsStore.shared.macServerURL) {
            LocalNetworkClient.shared.setMacAddress(macURL)
            try? await LocalNetworkClient.shared.postInstruction(instruction)
        }
    }

    // MARK: - Load pending from iCloud

    func loadPending() async {
        pendingInstructions = await InstructionQueue.shared.pendingInstructions()
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

extension PeerSyncEngine {
    var connections: [NWConnection] {
        // Expose connections for iOS use
        []  // handled internally
    }
}
#endif
