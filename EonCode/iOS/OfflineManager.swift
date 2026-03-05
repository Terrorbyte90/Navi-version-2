#if os(iOS)
import Foundation
import Network

@MainActor
final class OfflineManager: ObservableObject {
    static let shared = OfflineManager()

    @Published var isOnline = true
    @Published var iCloudAvailable = false
    @Published var macReachable = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.eoncode.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)

        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        Task { await checkMacReachability() }
    }

    func checkMacReachability() async {
        guard !SettingsStore.shared.macServerURL.isEmpty else { return }
        if let url = URL(string: SettingsStore.shared.macServerURL) {
            LocalNetworkClient.shared.setMacAddress(url)
            macReachable = (try? await LocalNetworkClient.shared.fetchStatus()) != nil
        }
    }

    var syncMethod: SyncMethod {
        if macReachable { return .localHTTP }
        if iCloudAvailable { return .iCloud }
        return .offline
    }

    enum SyncMethod {
        case iCloud, localHTTP, bonjour, offline

        var description: String {
            switch self {
            case .iCloud: return "iCloud"
            case .localHTTP: return "Lokalt nätverk"
            case .bonjour: return "Bonjour"
            case .offline: return "Offline"
            }
        }
    }
}
#endif
