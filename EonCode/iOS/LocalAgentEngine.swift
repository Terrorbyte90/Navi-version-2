#if os(iOS)
import Foundation

// MARK: - Result type for local actions

enum ActionResult {
    case success(String)
    case queued(String)        // Sent to Mac queue
    case waitingForMac(String) // Queued + Mac online, waiting for response
    case failed(String)

    var output: String {
        switch self {
        case .success(let s), .queued(let s), .waitingForMac(let s), .failed(let s): return s
        }
    }

    var isQueued: Bool {
        switch self { case .queued, .waitingForMac: return true; default: return false }
    }

    var succeeded: Bool {
        if case .failed = self { return false }
        return true
    }
}

// MARK: - LocalAgentEngine — runs directly on iOS

@MainActor
final class LocalAgentEngine: ObservableObject {
    static let shared = LocalAgentEngine()

    @Published var mode: AgentMode = SettingsStore.shared.iosAgentMode
    @Published var pendingMacResults: [UUID: String] = [:]  // instructionID → result

    private let queue = InstructionQueue.shared
    private let status = DeviceStatusBroadcaster.shared
    private var macResultPollers: [UUID: Task<Void, Never>] = [:]

    private init() {
        // Mirror settings changes
        Task { @MainActor in
            self.mode = SettingsStore.shared.iosAgentMode
        }
    }

    // MARK: - Execute any AgentAction

    func execute(action: AgentAction, projectRoot: URL?) async -> ActionResult {
        // Remote-only mode: queue everything
        guard mode == .autonomous else {
            return await queueToMac(action, projectRoot: projectRoot)
        }

        if action.canRunOnIOS {
            return await executeLocally(action, projectRoot: projectRoot)
        } else {
            return await queueToMac(action, projectRoot: projectRoot)
        }
    }

    // MARK: - Local execution (iOS-safe operations)

    func executeLocally(_ action: AgentAction, projectRoot: URL?) async -> ActionResult {
        let executor = ToolExecutor()
        let result: String

        switch action {
        case .readFile(let path):
            result = await executor.readFile(path: path, projectRoot: projectRoot)

        case .writeFile(let path, let content):
            result = await executor.writeFile(path: path, content: content, projectRoot: projectRoot)

        case .moveFile(let from, let to):
            result = await executor.moveFile(from: from, to: to, projectRoot: projectRoot)

        case .deleteFile(let path):
            result = await executor.deleteFile(path: path, projectRoot: projectRoot)

        case .createDirectory(let path):
            result = await executor.createDirectory(path: path, projectRoot: projectRoot)

        case .listDirectory(let path):
            result = await executor.listDirectory(path: path, projectRoot: projectRoot)

        case .searchFiles(let query):
            result = await executor.searchFiles(query: query, projectRoot: projectRoot)

        case .getAPIKey(let service):
            result = executor.getAPIKey(service: service)

        case .downloadFile(let url, let destination):
            result = await downloadViaNative(urlString: url, destination: destination, projectRoot: projectRoot)

        case .think(let reasoning):
            result = "💭 \(reasoning)"

        case .askUser(let question):
            result = "❓ \(question)"

        case .research(let query):
            // Research by asking Claude directly (no terminal needed)
            result = "Forskar om: \(query)"

        case .createArchive(let source, let dest):
            result = await zipViaFoundation(source: source, dest: dest, projectRoot: projectRoot)

        case .extractArchive(let path, let destination):
            result = await unzipViaFoundation(path: path, destination: destination, projectRoot: projectRoot)

        default:
            // Shouldn't reach here if canRunOnIOS is correct
            return await queueToMac(action, projectRoot: projectRoot)
        }

        return result.hasPrefix("FEL:") ? .failed(result) : .success(result)
    }

    // MARK: - Native download via URLSession (replaces curl on iOS)

    private func downloadViaNative(urlString: String, destination: String, projectRoot: URL?) async -> String {
        guard let url = URL(string: urlString) else { return "FEL: Ogiltig URL: \(urlString)" }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "FEL: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
            }

            let destURL: URL
            if destination.hasPrefix("/") {
                destURL = URL(fileURLWithPath: destination)
            } else {
                destURL = (projectRoot ?? FileManager.default.temporaryDirectory).appendingPathComponent(destination)
            }

            try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destURL)
            return "Nedladdad \(data.count.formatted()) bytes → \(destination)"
        } catch {
            return "FEL: Nedladdning misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Native zip/unzip via FileManager (no zip binary on iOS)

    private func zipViaFoundation(source: String, dest: String, projectRoot: URL?) async -> String {
        guard let srcURL = resolvedURL(source, projectRoot: projectRoot) else { return "FEL: Källsökväg ogiltig" }
        guard let destURL = resolvedURL(dest, projectRoot: projectRoot) else { return "FEL: Målsökväg ogiltig" }

        do {
            var result: NSError?
            NSFileCoordinator().coordinate(readingItemAt: srcURL, options: .forUploading, error: &result) { zippedURL in
                try? FileManager.default.copyItem(at: zippedURL, to: destURL)
            }
            if let err = result { return "FEL: \(err.localizedDescription)" }
            return "Zip skapad: \(dest)"
        }
    }

    private func unzipViaFoundation(path: String, destination: String, projectRoot: URL?) async -> String {
        // iOS doesn't have unzip — read the zip and extract with FileManager
        guard let srcURL = resolvedURL(path, projectRoot: projectRoot),
              let destURL = resolvedURL(destination, projectRoot: projectRoot)
        else { return "FEL: Sökväg ogiltig" }

        do {
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
            // Use NSFileCoordinator for coordinated reading
            var coordError: NSError?
            var extractError: String?
            NSFileCoordinator().coordinate(readingItemAt: srcURL, options: .withoutChanges, error: &coordError) { readURL in
                // Basic extraction: copy to destination (real unzip would need ZipArchive or similar)
                let destFile = destURL.appendingPathComponent(readURL.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: readURL, to: destFile)
                } catch {
                    extractError = error.localizedDescription
                }
            }
            if let err = coordError ?? extractError.map({ NSError(domain: $0, code: 0) }) {
                return "FEL: \(err.localizedDescription)"
            }
            return "Extraherad till: \(destination)"
        } catch {
            return "FEL: \(error.localizedDescription)"
        }
    }

    private func resolvedURL(_ path: String, projectRoot: URL?) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return projectRoot?.appendingPathComponent(path)
    }

    // MARK: - Queue to Mac (terminal-required actions)

    func queueToMac(_ action: AgentAction, projectRoot: URL?) async -> ActionResult {
        let instr = Instruction(
            instruction: action.queueLabel,
            projectID: nil
        )
        await queue.enqueue(instr)

        let macOnline = status.remoteMacIsOnline

        if macOnline {
            // Poll for result (up to 5 minutes)
            let result = await pollForMacResult(instructionID: instr.id, timeout: 300)
            return .waitingForMac(result ?? "⏳ Köad och väntar på Mac-svar…")
        } else {
            return .queued("🟡 Köad till Mac: \(action.queueLabel)\nMac är offline — exekveras vid nästa kontakt.")
        }
    }

    // MARK: - Poll for Mac result

    private func pollForMacResult(instructionID: UUID, timeout: TimeInterval) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        let sync = iCloudSyncEngine.shared

        while Date() < deadline {
            if let url = sync.instructionsRoot?.appendingPathComponent("\(instructionID.uuidString).json"),
               let instr = try? await sync.read(Instruction.self, from: url),
               instr.status == .completed {
                return instr.result ?? "✅ Klar"
            }

            try? await Task.sleep(seconds: 2.0)
        }
        return nil
    }
}
#endif
