import Foundation
import Combine

struct DeviceStatus: Codable {
    var deviceID: String
    var deviceName: String
    var isMac: Bool
    var isOnline: Bool
    var agentRunning: Bool
    var agentStatus: String
    var currentTask: String
    var currentStep: Int
    var totalSteps: Int
    var lastUpdate: Date
    var appVersion: String

    init() {
        deviceID = UIDevice.deviceID
        deviceName = UIDevice.deviceName
        isMac = UIDevice.isMac
        isOnline = true
        agentRunning = false
        agentStatus = ""
        currentTask = ""
        currentStep = 0
        totalSteps = 0
        lastUpdate = Date()
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

@MainActor
final class DeviceStatusBroadcaster: ObservableObject {
    static let shared = DeviceStatusBroadcaster()

    @Published var localStatus = DeviceStatus()
    @Published var remoteStatus: DeviceStatus?
    @Published var remoteMacIsOnline = false

    private let sync = iCloudSyncEngine.shared
    private var broadcastTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    private var statusURL: URL? {
        sync.deviceStatusRoot?.appendingPathComponent("\(UIDevice.deviceID).json")
    }

    private init() {
        startBroadcasting()
        startWatching()
    }

    // MARK: - Broadcast our status

    func startBroadcasting() {
        broadcastTask = Task {
            while !Task.isCancelled {
                await broadcast()
                try? await Task.sleep(seconds: 5.0)
            }
        }
    }

    func broadcast() async {
        var status = localStatus
        status.agentRunning = AgentEngine.shared.isRunning
        status.agentStatus = AgentEngine.shared.statusMessage
        status.lastUpdate = Date()
        localStatus = status

        guard let url = statusURL else { return }
        try? await sync.write(status, to: url)
    }

    func update(task: String, step: Int, total: Int) {
        localStatus.currentTask = task
        localStatus.currentStep = step
        localStatus.totalSteps = total
        Task { await broadcast() }
    }

    // MARK: - Watch remote status

    func startWatching() {
        watchTask = Task {
            while !Task.isCancelled {
                await fetchRemoteStatus()
                try? await Task.sleep(seconds: 3.0)
            }
        }
    }

    func fetchRemoteStatus() async {
        guard let dir = sync.deviceStatusRoot,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.pathExtension == "json" {
            guard let status = try? await sync.read(DeviceStatus.self, from: file),
                  status.deviceID != UIDevice.deviceID
            else { continue }

            remoteStatus = status
            let isRecent = Date().timeIntervalSince(status.lastUpdate) < 30
            remoteMacIsOnline = isRecent && status.isMac
        }

        // If no remote file found, mac is offline
        if files.filter({ $0.pathExtension == "json" }).count <= 1 {
            remoteMacIsOnline = false
        }
    }

    func stopAll() {
        broadcastTask?.cancel()
        watchTask?.cancel()
    }
}
