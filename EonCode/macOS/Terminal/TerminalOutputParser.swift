#if os(macOS)
import Foundation

struct TerminalOutputParser {
    // Remove ANSI escape codes
    static func clean(_ output: String) -> String {
        let ansiPattern = "\u{001B}\\[[0-9;]*[mABCDEFGHJKLMSTf]"
        return output.replacingOccurrences(of: ansiPattern, with: "", options: .regularExpression)
    }

    // Extract error lines (stderr patterns)
    static func extractErrors(_ output: String) -> [String] {
        let lines = output.components(separatedBy: "\n")
        return lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("error:") || lower.contains("fatal:") || lower.contains("failed")
        }
    }

    // Detect if output indicates success
    static func isSuccess(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("build succeeded") ||
               lower.contains("tests passed") ||
               lower.contains("** build succeeded **")
    }

    // Extract file paths from build output
    static func extractFilePaths(_ output: String) -> [String] {
        let pattern = "(/[^:\\s]+\\.swift)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: output) else { return nil }
            return String(output[range])
        }
    }
}
#endif
