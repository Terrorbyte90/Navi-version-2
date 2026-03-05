#if os(macOS)
import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: [Download] = []

    private init() {}

    func download(url: String, to destination: URL, onProgress: @escaping (Double) -> Void) async throws {
        let id = UUID()
        let dl = Download(id: id, url: url, destination: destination, progress: 0)
        activeDownloads.append(dl)

        defer { activeDownloads.removeAll { $0.id == id } }

        // Use curl for robust downloads (supports resume, progress)
        let cmd = "curl -L --progress-bar '\(url)' -o '\(destination.path)'"
        _ = await MacTerminalExecutor.stream(cmd) { output in
            // Parse curl progress if needed
            onProgress(0.5)
        }
    }

    struct Download: Identifiable {
        let id: UUID
        let url: String
        let destination: URL
        var progress: Double
    }
}
#endif
