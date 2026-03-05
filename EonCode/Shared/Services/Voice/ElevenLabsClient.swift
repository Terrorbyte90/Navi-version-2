import Foundation
import AVFoundation

@MainActor
final class ElevenLabsClient: ObservableObject {
    static let shared = ElevenLabsClient()

    @Published var isSpeaking = false
    @Published var isEnabled = false

    private let player = AudioPlayer()
    private let voiceID = "21m00Tcm4TlvDq8ikWAM" // Rachel (default)

    private var apiKey: String? { KeychainManager.shared.elevenLabsAPIKey }

    private init() {}

    func speak(_ text: String) async {
        guard isEnabled, let key = apiKey, !key.isEmpty else { return }
        guard !text.isBlank else { return }

        isSpeaking = true
        defer { isSpeaking = false }

        do {
            let data = try await fetchAudio(text: text, apiKey: key)
            await player.play(data: data)
        } catch {
            // Silently fail — TTS is optional
        }
    }

    func stop() {
        player.stop()
        isSpeaking = false
    }

    private func fetchAudio(text: String, apiKey: String) async throws -> Data {
        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ElevenLabsError.requestFailed
        }
        return data
    }
}

enum ElevenLabsError: Error {
    case requestFailed
}

@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func play(data: Data) async {
        await withCheckedContinuation { [weak self] continuation in
            self?.continuation = continuation
            do {
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.play()
                self?.audioPlayer = player
            } catch {
                continuation.resume()
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
