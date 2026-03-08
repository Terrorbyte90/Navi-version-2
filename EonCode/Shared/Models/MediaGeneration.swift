import Foundation

// MARK: - MediaGeneration

struct MediaGeneration: Codable, Identifiable {
    let id: UUID
    var type: MediaType
    var prompt: String
    var status: GenerationStatus
    var resultFilenames: [String]       // full relative paths from naviRoot, one per variation
    var thumbnailData: Data?
    var costUSD: Double
    var costSEK: Double
    var model: String
    var parameters: MediaParameters
    var createdAt: Date
    var completedAt: Date?
    var error: String?

    init(
        type: MediaType,
        prompt: String,
        model: String = "grok-imagine-image",
        parameters: MediaParameters = MediaParameters()
    ) {
        self.id = UUID()
        self.type = type
        self.prompt = prompt
        self.status = .pending
        self.resultFilenames = []
        self.costUSD = 0
        self.costSEK = 0
        self.model = model
        self.parameters = parameters
        self.createdAt = Date()
    }

    // MARK: - Backward-compatible Codable

    private enum CodingKeys: String, CodingKey {
        case id, type, prompt, status
        case resultFilenames            // new: array of relative paths
        case resultFilename             // legacy: single filename (no folder prefix)
        case thumbnailData, costUSD, costSEK, model, parameters
        case createdAt, completedAt, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self,             forKey: .id)
        type     = try c.decode(MediaType.self,        forKey: .type)
        prompt   = try c.decode(String.self,           forKey: .prompt)
        status   = try c.decode(GenerationStatus.self, forKey: .status)

        // Prefer new array; fall back to legacy single filename
        if let fns = try c.decodeIfPresent([String].self, forKey: .resultFilenames), !fns.isEmpty {
            resultFilenames = fns
        } else if let fn = try c.decodeIfPresent(String.self, forKey: .resultFilename) {
            // Migrate: prepend the base folder so the path is fully qualified
            resultFilenames = [Constants.iCloud.mediaImagesFolder + "/" + fn]
        } else {
            resultFilenames = []
        }

        thumbnailData = try c.decodeIfPresent(Data.self,              forKey: .thumbnailData)
        costUSD       = try c.decodeIfPresent(Double.self,            forKey: .costUSD)       ?? 0
        costSEK       = try c.decodeIfPresent(Double.self,            forKey: .costSEK)       ?? 0
        model         = try c.decodeIfPresent(String.self,            forKey: .model)         ?? "grok-imagine-image"
        parameters    = try c.decodeIfPresent(MediaParameters.self,   forKey: .parameters)    ?? MediaParameters()
        createdAt     = try c.decodeIfPresent(Date.self,              forKey: .createdAt)     ?? Date()
        completedAt   = try c.decodeIfPresent(Date.self,              forKey: .completedAt)
        error         = try c.decodeIfPresent(String.self,            forKey: .error)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,              forKey: .id)
        try c.encode(type,            forKey: .type)
        try c.encode(prompt,          forKey: .prompt)
        try c.encode(status,          forKey: .status)
        try c.encode(resultFilenames, forKey: .resultFilenames)
        try c.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try c.encode(costUSD,         forKey: .costUSD)
        try c.encode(costSEK,         forKey: .costSEK)
        try c.encode(model,           forKey: .model)
        try c.encode(parameters,      forKey: .parameters)
        try c.encode(createdAt,       forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encodeIfPresent(error,  forKey: .error)
    }

    // MARK: - Convenience

    /// First result file (backward compatibility with existing call sites).
    var resultFilename: String? { resultFilenames.first }

    /// Number of stored variation images.
    var variationCount: Int { resultFilenames.count }

    var displayTitle: String { String(prompt.prefix(50)) }

    var durationText: String? {
        guard type == .video, let dur = parameters.duration else { return nil }
        return "\(dur)s"
    }
}

// MARK: - Supporting types

enum MediaType: String, Codable, CaseIterable {
    case image
    case video

    var displayName: String {
        switch self {
        case .image: return "Bild"
        case .video: return "Video"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        }
    }
}

enum GenerationStatus: String, Codable {
    case pending
    case generating
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending:    return "Väntar…"
        case .generating: return "Genererar…"
        case .completed:  return "Klar"
        case .failed:     return "Misslyckades"
        }
    }

    var isActive: Bool { self == .pending || self == .generating }
}

struct MediaParameters: Codable {
    var size: String?
    var aspectRatio: String?
    var duration: Int?
    var resolution: String?
    var variations: Int?

    init(
        size: String? = "1024x1024",
        aspectRatio: String? = nil,
        duration: Int? = nil,
        resolution: String? = nil,
        variations: Int? = 1
    ) {
        self.size = size
        self.aspectRatio = aspectRatio
        self.duration = duration
        self.resolution = resolution
        self.variations = variations
    }
}

// MARK: - Media History (iCloud persistence)

struct MediaHistory: Codable {
    var generations: [MediaGeneration]
}
