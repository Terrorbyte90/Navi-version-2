#if os(iOS)
import Foundation

// MARK: - HybridTaskRunner
// Runs a task with a mix of local iOS execution and Mac-queued steps.
// Local steps run immediately; terminal steps are queued (and optionally awaited).

@MainActor
final class HybridTaskRunner: ObservableObject {

    @Published var stepsCompleted = 0
    @Published var stepsQueued = 0
    @Published var stepsTotal = 0
    @Published var stepResults: [StepRunResult] = []
    @Published var isRunning = false
    @Published var summary: String = ""

    private let localEngine = LocalAgentEngine.shared
    private let status = DeviceStatusBroadcaster.shared

    struct StepRunResult: Identifiable {
        let id = UUID()
        let stepIndex: Int
        let description: String
        let output: String
        let ranLocally: Bool
        let queued: Bool
        let succeeded: Bool
    }

    // MARK: - Run task

    func run(
        steps: [(description: String, action: AgentAction)],
        projectRoot: URL?,
        onStepUpdate: @escaping (StepRunResult) -> Void
    ) async -> HybridResult {
        isRunning = true
        stepsTotal = steps.count
        stepsCompleted = 0
        stepsQueued = 0
        stepResults = []
        defer { isRunning = false }

        let mode = SettingsStore.shared.iosAgentMode
        var results: [StepRunResult] = []
        var pendingMacSteps: [(Int, String, AgentAction)] = []

        for (i, step) in steps.enumerated() {
            let canLocal = step.action.canRunOnIOS && mode == .autonomous

            if canLocal {
                // Execute directly
                let result = await localEngine.executeLocally(step.action, projectRoot: projectRoot)
                let stepResult = StepRunResult(
                    stepIndex: i,
                    description: step.description,
                    output: result.output,
                    ranLocally: true,
                    queued: false,
                    succeeded: result.succeeded
                )
                results.append(stepResult)
                stepResults.append(stepResult)
                stepsCompleted += 1
                onStepUpdate(stepResult)

            } else {
                // Needs Mac
                if status.remoteMacIsOnline {
                    // Queue and wait
                    let queueResult = await localEngine.queueToMac(step.action, projectRoot: projectRoot)
                    let stepResult = StepRunResult(
                        stepIndex: i,
                        description: step.description,
                        output: queueResult.output,
                        ranLocally: false,
                        queued: true,
                        succeeded: queueResult.succeeded
                    )
                    results.append(stepResult)
                    stepResults.append(stepResult)
                    stepsQueued += 1
                    onStepUpdate(stepResult)

                } else {
                    // Mac offline — queue remaining and stop waiting
                    pendingMacSteps.append((i, step.description, step.action))
                    for remaining in steps[(i+1)...] {
                        if !remaining.action.canRunOnIOS {
                            pendingMacSteps.append((steps.firstIndex(where: { $0.description == remaining.description }) ?? i+1,
                                                   remaining.description, remaining.action))
                        }
                    }

                    // Queue all pending to iCloud
                    for (_, desc, action) in pendingMacSteps {
                        let instr = Instruction(instruction: "\(desc): \(action.queueLabel)")
                        await InstructionQueue.shared.enqueue(instr)
                        stepsQueued += 1
                    }

                    summary = "\(results.count)/\(steps.count) steg klara lokalt. \(pendingMacSteps.count) köade till Mac (offline)."
                    return HybridResult(
                        stepResults: results,
                        status: .partiallyComplete,
                        localCount: results.filter(\.ranLocally).count,
                        queuedCount: pendingMacSteps.count,
                        summary: summary
                    )
                }
            }
        }

        let localCount = results.filter(\.ranLocally).count
        let queuedCount = results.filter(\.queued).count
        summary = "\(localCount) steg lokalt · \(queuedCount) via Mac"

        return HybridResult(
            stepResults: results,
            status: .complete,
            localCount: localCount,
            queuedCount: queuedCount,
            summary: summary
        )
    }
}

struct HybridResult {
    let stepResults: [HybridTaskRunner.StepRunResult]
    let status: HybridStatus
    let localCount: Int
    let queuedCount: Int
    let summary: String

    enum HybridStatus { case complete, partiallyComplete, failed }

    var succeeded: Bool { status != .failed }
}
#endif
