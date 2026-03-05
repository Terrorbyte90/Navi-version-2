import Foundation

// Platform-agnostic tool executor
// macOS: full execution; iOS: queues commands for Mac
final class ToolExecutor {

    // MARK: - Execute tool

    func execute(name: String, params: [String: String], projectRoot: URL?) async -> String {
        switch name {
        case "read_file":
            return await readFile(path: params["path"] ?? "", projectRoot: projectRoot)
        case "write_file":
            return await writeFile(path: params["path"] ?? "", content: params["content"] ?? "", projectRoot: projectRoot)
        case "move_file":
            return await moveFile(from: params["from"] ?? "", to: params["to"] ?? "", projectRoot: projectRoot)
        case "delete_file":
            return await deleteFile(path: params["path"] ?? "", projectRoot: projectRoot)
        case "create_directory":
            return await createDirectory(path: params["path"] ?? "", projectRoot: projectRoot)
        case "list_directory":
            return await listDirectory(path: params["path"] ?? "", projectRoot: projectRoot)
        case "run_command":
            return await runCommand(cmd: params["cmd"] ?? "")
        case "search_files":
            return await searchFiles(query: params["query"] ?? "", projectRoot: projectRoot)
        case "get_api_key":
            return getAPIKey(service: params["service"] ?? "")
        case "build_project":
            return await buildProject(path: params["path"] ?? "")
        case "download_file":
            return await downloadFile(url: params["url"] ?? "", destination: params["destination"] ?? "", projectRoot: projectRoot)
        case "zip_files":
            return await zipFiles(source: params["source"] ?? "", destination: params["destination"] ?? "", projectRoot: projectRoot)
        default:
            return "Okänt verktyg: \(name)"
        }
    }

    // MARK: - File operations (cross-platform)

    private func resolvedPath(_ path: String, projectRoot: URL?) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return (projectRoot ?? URL(fileURLWithPath: NSTemporaryDirectory())).appendingPathComponent(path)
    }

    func readFile(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return content
        } catch {
            return "FEL: Kunde inte läsa \(path): \(error.localizedDescription)"
        }
    }

    func writeFile(path: String, content: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return "Fil sparad: \(path)"
        } catch {
            return "FEL: Kunde inte skriva \(path): \(error.localizedDescription)"
        }
    }

    func moveFile(from: String, to: String, projectRoot: URL?) async -> String {
        let fromURL = resolvedPath(from, projectRoot: projectRoot)
        let toURL = resolvedPath(to, projectRoot: projectRoot)
        do {
            try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: fromURL, to: toURL)
            return "Flyttad: \(from) → \(to)"
        } catch {
            return "FEL: Kunde inte flytta: \(error.localizedDescription)"
        }
    }

    func deleteFile(path: String, projectRoot: URL?) async -> String {
        #if os(macOS)
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            try FileManager.default.removeItem(at: url)
            return "Borttagen: \(path)"
        } catch {
            return "FEL: Kunde inte ta bort: \(error.localizedDescription)"
        }
        #else
        return "iOS: Filborttagning köad för Mac"
        #endif
    }

    func createDirectory(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return "Mapp skapad: \(path)"
        } catch {
            return "FEL: Kunde inte skapa mapp: \(error.localizedDescription)"
        }
    }

    func listDirectory(path: String, projectRoot: URL?) async -> String {
        let url = resolvedPath(path, projectRoot: projectRoot)
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let lines = items.map { item -> String in
                let isDir = item.isDirectory
                let size = isDir ? "" : " (\(item.fileSize.formattedFileSize))"
                return "\(isDir ? "📁" : "📄") \(item.lastPathComponent)\(size)"
            }.sorted()
            return lines.joined(separator: "\n")
        } catch {
            return "FEL: Kunde inte lista katalog: \(error.localizedDescription)"
        }
    }

    func searchFiles(query: String, projectRoot: URL?) async -> String {
        guard let root = projectRoot else { return "Inget projekt valt" }
        var results: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let lq = query.lowercased()
        while let url = enumerator?.nextObject() as? URL {
            if url.isDirectory { continue }
            if url.lastPathComponent.lowercased().contains(lq) {
                results.append(url.path)
                continue
            }
            // Content search (text files only)
            let ext = url.pathExtension.lowercased()
            let textExts = ["swift", "py", "js", "ts", "html", "css", "json", "yaml", "yml", "md", "txt"]
            if textExts.contains(ext),
               let content = try? String(contentsOf: url, encoding: .utf8),
               content.lowercased().contains(lq) {
                results.append("\(url.path) (innehåll)")
            }
        }

        if results.isEmpty { return "Inga träffar för '\(query)'" }
        return results.prefix(50).joined(separator: "\n")
    }

    func getAPIKey(service: String) -> String {
        KeychainManager.shared.getKey(for: service) ?? "Ingen nyckel hittad för '\(service)'"
    }

    // MARK: - Platform-specific: run_command

    func runCommand(cmd: String) async -> String {
        #if os(macOS)
        return await MacTerminalExecutor.run(cmd)
        #else
        // On iOS: queue for Mac
        let instruction = Instruction(instruction: "run_command: \(cmd)")
        await InstructionQueue.shared.enqueue(instruction)
        return "Köad för macOS: \(cmd)"
        #endif
    }

    // MARK: - Build project

    func buildProject(path: String) async -> String {
        #if os(macOS)
        return await MacTerminalExecutor.run("cd '\(path)' && xcodebuild build 2>&1 | tail -50")
        #else
        return "Byggkommando köat för macOS"
        #endif
    }

    // MARK: - Download

    func downloadFile(url: String, destination: String, projectRoot: URL?) async -> String {
        #if os(macOS)
        let dest = resolvedPath(destination, projectRoot: projectRoot).path
        return await MacTerminalExecutor.run("curl -L '\(url)' -o '\(dest)'")
        #else
        return "Nedladdning köad för macOS"
        #endif
    }

    // MARK: - Zip

    func zipFiles(source: String, destination: String, projectRoot: URL?) async -> String {
        #if os(macOS)
        let src = resolvedPath(source, projectRoot: projectRoot).path
        let dst = resolvedPath(destination, projectRoot: projectRoot).path
        return await MacTerminalExecutor.run("zip -r '\(dst)' '\(src)'")
        #else
        return "Zip köad för macOS"
        #endif
    }
}
