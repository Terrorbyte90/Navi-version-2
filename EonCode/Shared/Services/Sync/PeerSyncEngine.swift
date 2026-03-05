import Foundation
import Network
import Combine

// MARK: - Bonjour peer-to-peer sync (secondary sync method)

@MainActor
final class PeerSyncEngine: ObservableObject {
    static let shared = PeerSyncEngine()

    @Published var discoveredPeers: [PeerDevice] = []
    @Published var isAdvertising = false
    @Published var isBrowsing = false
    @Published var connectedPeer: PeerDevice?
    @Published var syncStatus: String = ""

    private var browser: NWBrowser?
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let serviceType = Constants.Sync.bonjourServiceType
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Advertise (mac advertises, iOS discovers)

    func startAdvertising() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeerPrivacy = true

        guard let listener = try? NWListener(using: parameters) else { return }
        listener.service = NWListener.Service(name: UIDevice.deviceName, type: serviceType)

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isAdvertising = true
                    self?.syncStatus = "Tillgänglig för iOS-synk"
                case .failed:
                    self?.isAdvertising = false
                default: break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
    }

    // MARK: - Browse (iOS browses for Mac)

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeerPrivacy = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: params)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isBrowsing = true
                case .failed:
                    self?.isBrowsing = false
                    self?.syncStatus = "Bonjour-sökning misslyckades"
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.discoveredPeers = results.compactMap { result -> PeerDevice? in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return PeerDevice(name: name, endpoint: result.endpoint, isMac: true)
                }
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        discoveredPeers = []
    }

    // MARK: - Connect to peer

    func connect(to peer: PeerDevice) {
        let params = NWParameters.tcp
        params.includePeerToPeerPrivacy = true

        let connection = NWConnection(to: peer.endpoint, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.connectedPeer = peer
                    self?.syncStatus = "Ansluten till \(peer.name)"
                case .failed(let error):
                    self?.connectedPeer = nil
                    self?.syncStatus = "Anslutning misslyckades: \(error.localizedDescription)"
                case .cancelled:
                    self?.connectedPeer = nil
                default: break
                }
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        connections.append(connection)
    }

    // MARK: - Send/receive data

    func send(data: Data, to connection: NWConnection) {
        let lengthPrefix = withUnsafeBytes(of: UInt32(data.count).bigEndian) { Data($0) }
        let fullData = lengthPrefix + data

        connection.send(content: fullData, completion: .contentProcessed { error in
            if let error = error {
                Task { @MainActor in
                    self.syncStatus = "Sändningsfel: \(error.localizedDescription)"
                }
            }
        })
    }

    func sendSyncPacket(_ packet: SyncPacket, to connection: NWConnection) {
        guard let data = try? packet.encoded() else { return }
        send(data: data, to: connection)
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connections.append(connection)
        receiveLoop(connection: connection)
    }

    private func receiveLoop(connection: NWConnection) {
        // Read 4-byte length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let data = data, data.count == 4 else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // Read payload
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { payloadData, _, _, _ in
                if let payloadData = payloadData, let packet = try? payloadData.decoded(as: SyncPacket.self) {
                    Task { @MainActor in
                        self?.handleReceivedPacket(packet)
                    }
                }
                if !isComplete {
                    self?.receiveLoop(connection: connection)
                }
            }
        }
    }

    private func handleReceivedPacket(_ packet: SyncPacket) {
        switch packet.type {
        case "file_sync":
            if let path = packet.metadata["path"],
               let content = packet.data.flatMap({ String(data: $0, encoding: .utf8) }) {
                try? content.write(toFile: path, atomically: true, encoding: .utf8)
                syncStatus = "Fil synkad: \((path as NSString).lastPathComponent)"
            }
        case "instruction":
            if let data = packet.data,
               let instruction = try? data.decoded(as: Instruction.self) {
                Task {
                    await InstructionQueue.shared.enqueue(instruction)
                }
            }
        case "status":
            syncStatus = packet.metadata["status"] ?? ""
        default:
            break
        }

        NotificationCenter.default.post(name: .peerSyncDidReceive, object: packet)
    }

    func disconnect() {
        for conn in connections { conn.cancel() }
        connections = []
        connectedPeer = nil
    }
}

// MARK: - Models

struct PeerDevice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let endpoint: NWEndpoint
    let isMac: Bool

    static func == (lhs: PeerDevice, rhs: PeerDevice) -> Bool {
        lhs.name == rhs.name
    }
}

struct SyncPacket: Codable {
    let type: String        // "file_sync", "instruction", "status", "ping"
    let metadata: [String: String]
    let data: Data?
}

extension Notification.Name {
    static let peerSyncDidReceive = Notification.Name("peerSyncDidReceive")
}
