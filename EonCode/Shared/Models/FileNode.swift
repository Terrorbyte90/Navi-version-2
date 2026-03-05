import Foundation

final class FileNode: Identifiable, ObservableObject, Hashable {
    let id: UUID
    var name: String
    var path: String              // Full path
    var relativePath: String      // Relative to project root
    var isDirectory: Bool
    var size: Int64
    var modifiedAt: Date
    var fileType: FileType
    @Published var children: [FileNode]?
    @Published var isExpanded: Bool
    weak var parent: FileNode?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        relativePath: String,
        isDirectory: Bool,
        size: Int64 = 0,
        modifiedAt: Date = Date(),
        children: [FileNode]? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
        self.fileType = FileType(filename: name)
        self.children = children
        self.isExpanded = false
    }

    var isLeaf: Bool { !isDirectory }

    var icon: String {
        if isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return fileType.icon
    }

    var depth: Int {
        var count = 0
        var current = parent
        while current != nil {
            count += 1
            current = current?.parent
        }
        return count
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum FileType: String, Codable {
    case swift, python, javascript, typescript, html, css, json, yaml, markdown
    case plainText, image, binary, directory, unknown

    init(filename: String) {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": self = .swift
        case "py": self = .python
        case "js", "jsx", "mjs": self = .javascript
        case "ts", "tsx": self = .typescript
        case "html", "htm": self = .html
        case "css", "scss", "sass": self = .css
        case "json": self = .json
        case "yaml", "yml": self = .yaml
        case "md", "markdown": self = .markdown
        case "txt": self = .plainText
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic": self = .image
        default: self = .unknown
        }
    }

    var icon: String {
        switch self {
        case .swift: return "swift"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .javascript, .typescript: return "j.square"
        case .html: return "globe"
        case .css: return "paintbrush"
        case .json: return "curlybraces"
        case .yaml: return "doc.text"
        case .markdown: return "doc.richtext"
        case .plainText: return "doc.text"
        case .image: return "photo"
        case .directory: return "folder"
        default: return "doc"
        }
    }

    var syntaxLanguage: String {
        switch self {
        case .swift: return "swift"
        case .python: return "python"
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .html: return "html"
        case .css: return "css"
        case .json: return "json"
        case .yaml: return "yaml"
        case .markdown: return "markdown"
        default: return "plaintext"
        }
    }

    var isTextBased: Bool {
        switch self {
        case .binary, .image, .directory: return false
        default: return true
        }
    }
}
