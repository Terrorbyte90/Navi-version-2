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

        // iOS: start auto-discovery of Mac HTTP server + Bonjour browsing
        #if os(iOS)
        Task {
            LocalNetworkClient.shared.startAutoDiscovery()
            PeerSyncEngine.shared.startBrowsing()
        }
        #endif
    }

    // MARK: - Broadcast our status

    func startBroadcasting() {
        broadcastTask?.cancel()
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
        watchTask?.cancel()
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

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let myID = UIDevice.deviceID

        // Look for a remote device file (not ours)
        var foundRemote = false
        for file in jsonFiles {
            guard let status = try? await sync.read(DeviceStatus.self, from: file),
                  status.deviceID != myID
            else { continue }

            remoteStatus = status
            let isRecent = Date().timeIntervalSince(status.lastUpdate) < 30
            if status.isMac && isRecent {
                remoteMacIsOnline = true
                foundRemote = true
            }
        }

        // Only mark offline if we explicitly found no recent Mac file
        if !foundRemote {
            // Don't immediately flip to offline — give grace period.
            // Only flip if we haven't seen Mac in 60s.
            if let remote = remoteStatus, remote.isMac,
               let last = Optional(remote.lastUpdate) {
                remoteMacIsOnline = Date().timeIntervalSince(last) < 60
            } else {
                remoteMacIsOnline = false
            }
        }
    }

    func stopAll() {
        broadcastTask?.cancel()
        watchTask?.cancel()
        broadcastTask = nil
        watchTask = nil
        #if os(iOS)
        LocalNetworkClient.shared.stopAutoDiscovery()
        PeerSyncEngine.shared.stopBrowsing()
        #endif
    }
}
