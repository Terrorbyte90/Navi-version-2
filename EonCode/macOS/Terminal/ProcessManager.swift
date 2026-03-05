#if os(macOS)
import Foundation

@MainActor
final class ProcessManager: ObservableObject {
    static let shared = ProcessManager()

    @Published var runningProcesses: [ManagedProcess] = []

    private init() {}

    func launch(command: String, workingDir: URL? = nil, onOutput: @escaping (String) -> Void) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-l", "-c", command]
        if let dir = workingDir { process.currentDirectoryURL = dir }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:" + (env["PATH"] ?? "")
        process.environment = env

        let managed = ManagedProcess(id: UUID(), command: command, process: process)
        runningProcesses.append(managed)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                Task { @MainActor in onOutput(text) }
            }
        }

        return await withCheckedContinuation { continuation in
            do {
                try process.run()
                process.terminationHandler = { [weak self] p in
                    Task { @MainActor in
                        self?.runningProcesses.removeAll { $0.id == managed.id }
                    }
                    continuation.resume(returning: p.terminationStatus)
                }
            } catch {
                Task { @MainActor in
                    self.runningProcesses.removeAll { $0.id == managed.id }
                }
                continuation.resume(returning: -1)
            }
        }
    }

    func killAll() {
        for p in runningProcesses { p.process.terminate() }
        runningProcesses = []
    }
}

struct ManagedProcess: Identifiable {
    let id: UUID
    let command: String
    let process: Process
    let startedAt = Date()
}
#endif
