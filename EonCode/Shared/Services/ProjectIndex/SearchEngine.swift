import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let lineNumber: Int?
    let lineContent: String?
    let matchType: MatchType

    enum MatchType {
        case filename, content
    }
}

@MainActor
final class SearchEngine: ObservableObject {
    static let shared = SearchEngine()

    @Published var results: [SearchResult] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?
    private init() {}

    func search(query: String, in projectID: UUID) async {
        guard !query.isBlank else {
            results = []
            return
        }

        searchTask?.cancel()
        isSearching = true
        results = []

        searchTask = Task {
            let files = ProjectIndexer.shared.allFiles(in: projectID)
            var found: [SearchResult] = []
            let lq = query.lowercased()

            for file in files {
                if Task.isCancelled { break }

                // Filename match
                if file.name.lowercased().contains(lq) {
                    found.append(SearchResult(
                        filePath: file.path,
                        fileName: file.name,
                        lineNumber: nil,
                        lineContent: nil,
                        matchType: .filename
                    ))
                }

                // Content match (text files only)
                guard file.fileType.isTextBased,
                      let content = try? String(contentsOfFile: file.path, encoding: .utf8)
                else { continue }

                let lines = content.components(separatedBy: "\n")
                for (i, line) in lines.enumerated() {
                    if line.lowercased().contains(lq) {
                        found.append(SearchResult(
                            filePath: file.path,
                            fileName: file.name,
                            lineNumber: i + 1,
                            lineContent: line.trimmed.truncated(to: 100),
                            matchType: .content
                        ))
                        if found.filter({ $0.filePath == file.path }).count >= 5 { break }
                    }
                }

                if found.count > 200 { break }
            }

            if !Task.isCancelled {
                results = found
                isSearching = false
            }
        }
    }

    func clear() {
        searchTask?.cancel()
        results = []
        isSearching = false
    }
}
