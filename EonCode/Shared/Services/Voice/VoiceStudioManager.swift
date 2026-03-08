import Foundation
import AVFoundation

// MARK: - VoiceClip model

struct VoiceClip: Identifiable, Codable {
    let id: UUID
    var clipType: ClipType
    var text: String
    var voiceName: String
    var voiceID: String
    var createdAt: Date
    var iCloudPath: String?      // relative path under naviRoot

    enum ClipType: String, Codable { case tts, sfx }

    init(clipType: ClipType, text: String, voiceName: String, voiceID: String) {
        self.id = UUID()
        self.clipType = clipType
        self.text = text
        self.voiceName = voiceName
        self.voiceID = voiceID
        self.createdAt = Date()
    }

    var displayTitle: String {
        let prefix = text.prefix(60)
        return prefix.isEmpty ? "Klipp" : String(prefix)
    }

    var typeIcon: String {
        switch clipType {
        case .tts: return "waveform"
        case .sfx: return "speaker.wave.3.fill"
        }
    }

    var typeLabel: String {
        switch clipType {
        case .tts: return "Röst"
        case .sfx: return "Ljud"
        }
    }
}

// MARK: - VoiceStudioManager

@MainActor
final class VoiceStudioManager: ObservableObject {
    static let shared = VoiceStudioManager()

    @Published var clips: [VoiceClip] = []
    @Published var isGenerating = false
    @Published var playingClipID: UUID?
    @Published var errorMessage: String?

    private let client = ElevenLabsClient.shared
    private let icloud = iCloudSyncEngine.shared
    private let historyFilename = "voice-history.json"

    private init() {
        Task { await loadHistory() }
    }

    // MARK: - Generate TTS

    func generateTTS(
        text: String,
        voiceID: String,
        voiceName: String,
        stability: Double,
        similarityBoost: Double,
        style: Double
    ) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let data = try await client.generateTTS(
                text: text,
                voiceID: voiceID,
                stability: stability,
                similarityBoost: similarityBoost,
                style: style
            )

            var clip = VoiceClip(clipType: .tts, text: text, voiceName: voiceName, voiceID: voiceID)
            let path = try await saveToICloud(data: data, clip: clip)
            clip.iCloudPath = path
            clips.insert(clip, at: 0)
            await saveHistory()

            // Auto-play
            await playData(data, clipID: clip.id)
        } catch ElevenLabsError.noAPIKey {
            errorMessage = "Ange ElevenLabs API-nyckel i Inställningar."
        } catch {
            errorMessage = "Generering misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Generate Sound Effect

    func generateSFX(text: String, duration: Double, influence: Double) async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let data = try await client.generateSoundEffect(
                text: text,
                duration: duration,
                promptInfluence: influence
            )

            var clip = VoiceClip(clipType: .sfx, text: text, voiceName: "ElevenLabs SFX", voiceID: "sfx")
            let path = try await saveToICloud(data: data, clip: clip)
            clip.iCloudPath = path
            clips.insert(clip, at: 0)
            await saveHistory()

            await playData(data, clipID: clip.id)
        } catch ElevenLabsError.noAPIKey {
            errorMessage = "Ange ElevenLabs API-nyckel i Inställningar."
        } catch {
            errorMessage = "Generering misslyckades: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback

    func play(_ clip: VoiceClip) async {
        guard let root = icloud.naviRoot,
              let path = clip.iCloudPath else { return }
        let url = root.appendingPathComponent(path)
        guard let data = try? await icloud.readData(from: url) else { return }
        await playData(data, clipID: clip.id)
    }

    func stop() {
        client.stop()
        playingClipID = nil
    }

    // MARK: - Delete

    func delete(_ clip: VoiceClip) async {
        clips.removeAll { $0.id == clip.id }
        if let root = icloud.naviRoot, let path = clip.iCloudPath {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }
        await saveHistory()
    }

    // MARK: - Audio URL for clip

    func audioURL(for clip: VoiceClip) -> URL? {
        guard let root = icloud.naviRoot, let path = clip.iCloudPath else { return nil }
        let url = root.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Private helpers

    private func playData(_ data: Data, clipID: UUID) async {
        playingClipID = clipID
        await client.playData(data)
        playingClipID = nil
    }

    private func saveToICloud(data: Data, clip: VoiceClip) async throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let month = formatter.string(from: Date())

        let folder: String
        switch clip.clipType {
        case .tts: folder = "Voice/TTS/\(month)"
        case .sfx: folder = "Voice/SFX/\(month)"
        }

        let filename = "\(clip.id.uuidString).mp3"
        let relativePath = "\(folder)/\(filename)"

        guard let root = icloud.naviRoot else { return relativePath }
        let dirURL = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fileURL = root.appendingPathComponent(relativePath)
        let coordinator = NSFileCoordinator()
        var writeError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: nil) { url in
            do { try data.write(to: url, options: .atomic) }
            catch { writeError = error }
        }
        if let err = writeError { throw err }

        return relativePath
    }

    // MARK: - Persistence

    private func loadHistory() async {
        guard let root = icloud.naviRoot else { return }
        let url = root.appendingPathComponent(historyFilename)
        guard let data = try? await icloud.readData(from: url),
              let loaded = try? JSONDecoder().decode([VoiceClip].self, from: data)
        else { return }
        clips = loaded
    }

    private func saveHistory() async {
        guard let root = icloud.naviRoot,
              let data = try? JSONEncoder().encode(clips)
        else { return }
        let url = root.appendingPathComponent(historyFilename)
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: nil) { u in
            try? data.write(to: u, options: .atomic)
        }
    }
}
