import Foundation

// MARK: - iCloud storage for Code projects
// Path: iCloud Drive/Navi/Code/{project-id}.json

@MainActor
final class CodeProjectStore: ObservableObject {
    static let shared = CodeProjectStore()

    private var containerURL: URL? {
        iCloudSyncEngine.shared.codeDirectory
    }

    private init() {}

    // MARK: - Save

    func save(_ project: CodeProject) async throws {
        guard let dir = containerURL else { throw CodeStoreError.iCloudUnavailable }

        let fileURL = dir.appendingPathComponent("\(project.id.uuidString).json")
        let data = try JSONEncoder().encode(project)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordError) { url in
                    blockRan = true
                    do {
                        try data.write(to: url, options: .atomic)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - Load all

    func loadAll() async throws -> [CodeProject] {
        guard let dir = containerURL else { return [] }

        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let files = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil
                ) else {
                    cont.resume(returning: [])
                    return
                }

                let jsonFiles = files.filter { $0.pathExtension == "json" }
                var projects: [CodeProject] = []

                for fileURL in jsonFiles {
                    // Fresh coordinator per file — reusing one instance across multiple calls can deadlock
                    let coordinator = NSFileCoordinator()
                    var coordError: NSError?
                    coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordError) { url in
                        do {
                            let data = try Data(contentsOf: url)
                            let project = try JSONDecoder().decode(CodeProject.self, from: data)
                            projects.append(project)
                        } catch {
                            NaviLog.error("CodeProjectStore: kunde inte läsa \(fileURL.lastPathComponent)", error: error)
                        }
                    }
                }

                cont.resume(returning: projects.sorted { $0.updatedAt > $1.updatedAt })
            }
        }
    }

    // MARK: - Delete

    func delete(id: UUID) async throws {
        guard let dir = containerURL else { return }
        let fileURL = dir.appendingPathComponent("\(id.uuidString).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordError) { url in
                    blockRan = true
                    do {
                        try FileManager.default.removeItem(at: url)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }
}

// MARK: - iCloudSyncEngine extension for Code directory

extension iCloudSyncEngine {
    var codeDirectory: URL? {
        let base: URL
        if let icloud = naviRoot {
            base = icloud
        } else {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            base = docs.appendingPathComponent("Navi")
        }
        let dir = base.appendingPathComponent("Code", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
