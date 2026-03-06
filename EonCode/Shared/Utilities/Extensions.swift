import Foundation
import SwiftUI

// MARK: - String
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }

    func truncated(to length: Int, suffix: String = "…") -> String {
        count > length ? String(prefix(length)) + suffix : self
    }

    var lines: [String] { components(separatedBy: "\n") }

    var lineCount: Int { lines.count }

    func ranges(of substring: String, options: CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = startIndex
        while let range = range(of: substring, options: options, range: start..<endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}

// MARK: - URL
extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    var modificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
    }

    func appending(components: [String]) -> URL {
        components.reduce(self) { $0.appendingPathComponent($1) }
    }
}

// MARK: - Date
extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }

    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    static func from(iso8601 string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Data
extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}

extension Encodable {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func encodedString() throws -> String {
        String(data: try encoded(), encoding: .utf8) ?? ""
    }
}

// MARK: - View Modifiers
extension View {
    func glassBackground(radius: CGFloat = 16, opacity: Double = 0.15) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    func cardStyle() -> some View {
        self
            .padding()
            .glassBackground()
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Color
extension Color {
    static var codeBackground: Color { Color(red: 0.12, green: 0.12, blue: 0.15) }
    static var chatBackground: Color { Color(red: 0.08, green: 0.08, blue: 0.12) }
    static var sidebarBackground: Color { Color(red: 0.10, green: 0.10, blue: 0.13) }
    static var accentEon: Color { Color(red: 0.3, green: 0.6, blue: 1.0) }
    static var assistantBubble: Color { Color(red: 0.15, green: 0.15, blue: 0.20) }
    static var userBubble: Color { Color(red: 0.2, green: 0.4, blue: 0.8) }
}

// MARK: - Int64
extension Int64 {
    var formattedFileSize: String {
        let bytes = Double(self)
        if bytes < 1024 { return "\(self) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", bytes / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", bytes / (1024 * 1024)) }
        return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
    }
}

// MARK: - Task
extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Int
extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
