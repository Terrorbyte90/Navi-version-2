#if os(macOS)
import Foundation
import Combine

// Background daemon that processes instruction queue when app is running
@MainActor
final class BackgroundDaemon: ObservableObject {
    static let shared = BackgroundDaemon()

    @Published var isActive = false
    @Published var processedCount = 0
    @Published var lastActivity: Date?

    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard !isActive else { return }
        isActive = true
        InstructionQueue.shared.startProcessingLoop()
        LocalNetworkServer.shared.start()
        PeerSyncEngine.shared.startAdvertising()
        DeviceStatusBroadcaster.shared.startBroadcasting()
        startPolling()
    }

    func stop() {
        isActive = false
        pollingTask?.cancel()
        InstructionQueue.shared.stopProcessingLoop()
        LocalNetworkServer.shared.stop()
        PeerSyncEngine.shared.stopAdvertising()
        DeviceStatusBroadcaster.shared.stopAll()
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled && isActive {
                await tick()
                try? await Task.sleep(seconds: 5.0)
            }
        }
    }

    private func tick() async {
        // Broadcast status
        await DeviceStatusBroadcaster.shared.broadcast()
        lastActivity = Date()
    }
}
#endif
