import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MediaGenerationManager

@MainActor
final class MediaGenerationManager: ObservableObject {
    static let shared = MediaGenerationManager()

    @Published var generations: [MediaGeneration] = []
    @Published var balance: XAIBalance?
    @Published var isLoadingBalance = false

    private let maxConcurrent = 10
    private let icloud = iCloudSyncEngine.shared
    private let client = XAIClient.shared
    private let historyFilename = "media-history.json"

    private init() {
        Task { await loadHistory() }
    }

    // MARK: - Derived lists

    var activeGenerations: [MediaGeneration] {
        generations.filter { $0.status.isActive }
    }

    var completedGenerations: [MediaGeneration] {
        generations.filter { $0.status == .completed }
    }

    var canGenerate: Bool {
        activeGenerations.count < maxConcurrent
    }

    /// Completed generations grouped by "MMMM yyyy" (newest first).
    var groupedCompletedGenerations: [(String, [MediaGeneration])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "sv_SE")

        let sorted = completedGenerations.sorted { $0.createdAt > $1.createdAt }
        var result: [(String, [MediaGeneration])] = []
        var currentLabel = ""
        var currentGroup: [MediaGeneration] = []

        for gen in sorted {
            let label = formatter.string(from: gen.createdAt)
            if label == currentLabel {
                currentGroup.append(gen)
            } else {
                if !currentGroup.isEmpty {
                    result.append((currentLabel, currentGroup))
                }
                currentLabel = label
                currentGroup = [gen]
            }
        }
        if !currentGroup.isEmpty {
            result.append((currentLabel, currentGroup))
        }
        return result
    }

    // MARK: - Generate Image

    func generateImage(
        prompt: String,
        model: String = "grok-imagine-image",
        size: String = "1024x1024",
        variations: Int = 1
    ) async {
        guard canGenerate else {
            NaviLog.warning("MediaGen: max \(maxConcurrent) samtidiga genereringar nått")
            return
        }

        var gen = MediaGeneration(
            type: .image,
            prompt: prompt,
            model: model,
            parameters: MediaParameters(size: size, variations: variations)
        )
        gen.status = .generating
        generations.insert(gen, at: 0)
        await saveHistory()

        do {
            let results = try await client.generateImage(
                prompt: prompt,
                model: model,
                size: size,
                n: variations
            )

            let folder = dateFolder(for: .image)

            for (i, result) in results.enumerated() {
                let imageData = try await client.downloadImageData(from: result.url)
                let filename = "\(gen.id.uuidString)\(i > 0 ? "-\(i)" : "").png"
                let relativePath = "\(folder)/\(filename)"

                try await saveToICloud(data: imageData, relativePath: relativePath)
                gen.resultFilenames.append(relativePath)

                if i == 0 {
                    gen.thumbnailData = createThumbnail(from: imageData)
                }
            }

            let pricePerImage = model.contains("pro") ? 0.07 : 0.02
            let costUSD = Double(results.count) * pricePerImage
            gen.costUSD = costUSD
            gen.costSEK = costUSD * ExchangeRateService.shared.usdToSEK
            gen.status = .completed
            gen.completedAt = Date()

            updateGeneration(gen)
            CostTracker.shared.recordMediaCost(usd: costUSD, model: gen.model)
        } catch {
            gen.status = .failed
            gen.error = error.localizedDescription
            updateGeneration(gen)
            NaviLog.error("MediaGen: bildgenerering misslyckades", error: error)
        }
    }

    // MARK: - Balance

    func refreshBalance() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        do {
            balance = try await client.fetchBalance()
        } catch {
            NaviLog.warning("MediaGen: kunde inte hämta saldo: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete (removes all variation files)

    func delete(_ generation: MediaGeneration) async {
        generations.removeAll { $0.id == generation.id }

        if let root = icloud.naviRoot {
            for relativePath in generation.resultFilenames {
                let fileURL = root.appendingPathComponent(relativePath)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        await saveHistory()
    }

    // MARK: - URL helpers

    /// All iCloud file URLs for a generation's variations.
    func imageURLs(for generation: MediaGeneration) -> [URL] {
        guard let root = icloud.naviRoot else { return [] }
        return generation.resultFilenames.compactMap { path in
            let url = root.appendingPathComponent(path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// First variation URL (backward compat).
    func imageURL(for generation: MediaGeneration) -> URL? {
        imageURLs(for: generation).first
    }

    // MARK: - Persistence (iCloud Drive)

    func loadHistory() async {
        guard let root = icloud.mediaRoot else { return }
        let historyURL = root.appendingPathComponent(historyFilename)
        do {
            let history: MediaHistory = try await icloud.read(MediaHistory.self, from: historyURL)
            generations = history.generations.sorted { $0.createdAt > $1.createdAt }
        } catch {
            generations = []
        }
    }

    func saveHistory() async {
        guard let root = icloud.mediaRoot else { return }
        let historyURL = root.appendingPathComponent(historyFilename)
        let history = MediaHistory(generations: generations)
        try? await icloud.write(history, to: historyURL)
    }

    // MARK: - Private helpers

    /// Returns the date-organized relative folder path, e.g. "Media/Images/2024-03".
    private func dateFolder(for type: MediaType) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: Date())
        switch type {
        case .image: return "\(Constants.iCloud.mediaImagesFolder)/\(month)"
        case .video: return "\(Constants.iCloud.mediaVideosFolder)/\(month)"
        }
    }

    private func saveToICloud(data: Data, relativePath: String) async throws {
        guard let root = icloud.naviRoot else { throw XAIError.invalidResponse }
        let fileURL = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await icloud.writeData(data, to: fileURL)
    }

    private func createThumbnail(from imageData: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: imageData) else { return nil }
        let size = NSSize(width: 200, height: 200)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        #else
        guard let image = UIImage(data: imageData) else { return nil }
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumbnail?.jpegData(compressionQuality: 0.6)
        #endif
    }

    private func updateGeneration(_ gen: MediaGeneration) {
        if let idx = generations.firstIndex(where: { $0.id == gen.id }) {
            generations[idx] = gen
        }
        Task { await saveHistory() }
    }
}
