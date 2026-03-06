import Foundation
import Combine

@MainActor
final class iCloudSyncEngine: ObservableObject {
    static let shared = iCloudSyncEngine()

    @Published var isAvailable = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private let fm = FileManager.default
    private var metadataQuery: NSMetadataQuery?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - iCloud container root

    var eonCodeRoot: URL? {
        fm.url(forUbiquityContainerIdentifier: Constants.iCloud.containerID)?
            .appendingPathComponent("Documents")
            .appendingPathComponent(Constants.iCloud.rootFolder)
    }

    var projectsRoot: URL? {
        eonCodeRoot?.appendingPathComponent(Constants.iCloud.projectsFolder)
    }

    var instructionsRoot: URL? {
        eonCodeRoot?.appendingPathComponent(Constants.iCloud.instructionsFolder)
    }

    var versionsRoot: URL? {
        eonCodeRoot?.appendingPathComponent(Constants.iCloud.versionsFolder)
    }

    var conversationsRoot: URL? {
        eonCodeRoot?.appendingPathComponent(Constants.iCloud.conversationsFolder)
    }

    var deviceStatusRoot: URL? {
        eonCodeRoot?.appendingPathComponent(Constants.iCloud.deviceStatusFolder)
    }

    private init() {
        checkAvailability()
        Task { await setupDirectories() }
        startMonitoring()
    }

    // MARK: - Setup

    private func checkAvailability() {
        isAvailable = fm.ubiquityIdentityToken != nil
    }

    func setupDirectories() async {
        guard let root = eonCodeRoot else { return }

        let dirs = [
            root,
            root.appendingPathComponent(Constants.iCloud.projectsFolder),
            root.appendingPathComponent(Constants.iCloud.instructionsFolder),
            root.appendingPathComponent(Constants.iCloud.versionsFolder),
            root.appendingPathComponent(Constants.iCloud.conversationsFolder),
            root.appendingPathComponent(Constants.iCloud.deviceStatusFolder),
            root.appendingPathComponent(Constants.iCloud.checkpointsFolder)
        ]

        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Write with coordinator

    func write<T: Encodable>(_ value: T, to url: URL) async throws {
        let data = try value.encoded()
        try await writeData(data, to: url)
    }

    func writeData(_ data: Data, to url: URL) async throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let err = coordError ?? writeError {
            throw err
        }
        // File is already in the iCloud container — NSFileCoordinator write
        // with .forReplacing triggers iCloud upload automatically.
        // No need to call setUbiquitous (which is only for moving local files TO iCloud).
    }

    // MARK: - Read with coordinator

    func read<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await readData(from: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func readData(from url: URL) async throws -> Data {
        // Ensure file is downloaded from iCloud
        try? fm.startDownloadingUbiquitousItem(at: url)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: Result<Data, Error>?

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordError) { readURL in
            do {
                result = .success(try Data(contentsOf: readURL))
            } catch {
                result = .failure(error)
            }
        }

        if let err = coordError { throw err }
        switch result {
        case .success(let data): return data
        case .failure(let error): throw error
        case .none: throw URLError(.cannotOpenFile)
        }
    }

    // MARK: - iCloud metadata monitoring

    func startMonitoring() {
        guard isAvailable else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@",
                                      NSMetadataItemPathKey,
                                      eonCodeRoot?.path ?? "")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        query.start()
        metadataQuery = query
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        lastSyncDate = Date()
        NotificationCenter.default.post(name: .iCloudDidSync, object: nil)
    }

    // MARK: - Convenience helpers

    func urlForProject(_ project: EonProject) -> URL? {
        projectsRoot?.appendingPathComponent(project.id.uuidString)
    }

    func urlForInstruction(_ instruction: Instruction) -> URL? {
        instructionsRoot?.appendingPathComponent(instruction.filename)
    }

    func urlForConversation(_ conversation: Conversation) -> URL? {
        conversationsRoot?.appendingPathComponent("\(conversation.id.uuidString).json")
    }

    // MARK: - User-selected folder (custom iCloud folder)

    var customProjectsFolder: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: "customProjectsFolder") else { return nil }
            return URL(fileURLWithPath: path)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: "customProjectsFolder")
        }
    }

    func saveProject(_ project: EonProject, to url: URL) async throws {
        let projectDir = url.appendingPathComponent(project.id.uuidString)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let metaURL = projectDir.appendingPathComponent("project.json")
        try await write(project, to: metaURL)
    }
}

extension Notification.Name {
    static let iCloudDidSync = Notification.Name("iCloudDidSync")
}
