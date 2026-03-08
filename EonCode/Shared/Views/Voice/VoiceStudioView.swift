import SwiftUI

// MARK: - Studio tab

private enum StudioTab: String, CaseIterable {
    case tts = "Röst"
    case sfx = "Ljud"

    var icon: String {
        switch self {
        case .tts: return "waveform"
        case .sfx: return "speaker.wave.3.fill"
        }
    }
}

// MARK: - VoiceStudioView

struct VoiceStudioView: View {
    @StateObject private var studio = VoiceStudioManager.shared
    @StateObject private var client = ElevenLabsClient.shared

    @State private var activeTab: StudioTab = .tts
    @State private var selectedDetail: VoiceClip?

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        HSplitView {
            controlsPanel
                .frame(minWidth: 300, maxWidth: 380)
            historyPanel
                .frame(minWidth: 380)
        }
        .background(Color.chatBackground)
        .onAppear { Task { await client.fetchVoices() } }
    }
    #endif

    // MARK: - iOS

    private var iOSLayout: some View {
        VStack(spacing: 0) {
            tabSelector
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 16) {
                    apiKeyBanner
                    activeTabContent
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)

            if !studio.clips.isEmpty {
                iOSMiniPlayer
            }
        }
        .background(Color.chatBackground)
        .onAppear { Task { await client.fetchVoices() } }
        .sheet(item: $selectedDetail) { clip in
            ClipDetailSheet(clip: clip)
        }
    }

    // MARK: - Controls Panel (macOS)

    private var controlsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                apiKeyBanner
                tabSelector
                activeTabContent
            }
            .padding(20)
        }
        .background(Color.sidebarBackground)
    }

    // MARK: - History Panel (macOS)

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Klipp").font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(studio.clips.count) genererade")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)

            if studio.clips.isEmpty {
                emptyHistory
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(studio.clips) { clip in
                            clipRow(clip)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(Color.chatBackground)
    }

    // MARK: - Tab selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(StudioTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { activeTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 12))
                        Text(tab.rawValue).font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(activeTab == tab ? Color.accentNavi.opacity(0.15) : Color.clear)
                    )
                    .foregroundColor(activeTab == tab ? .accentNavi : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Active tab content

    @ViewBuilder
    private var activeTabContent: some View {
        switch activeTab {
        case .tts: TTSPanel(studio: studio, client: client)
        case .sfx: SFXPanel(studio: studio)
        }
    }

    // MARK: - API key banner

    @ViewBuilder
    private var apiKeyBanner: some View {
        if KeychainManager.shared.elevenLabsAPIKey?.isEmpty != false {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.accentNavi)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ElevenLabs API-nyckel saknas")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Lägg till din nyckel under Inställningar → API-nycklar")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentNavi.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentNavi.opacity(0.2), lineWidth: 0.5)
                    )
            )
        }
    }

    // MARK: - Empty history

    private var emptyHistory: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.15))
            Text("Genererade klipp visas här")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Clip row

    @ViewBuilder
    private func clipRow(_ clip: VoiceClip) -> some View {
        let isPlaying = studio.playingClipID == clip.id

        HStack(spacing: 12) {
            // Play / stop button
            Button {
                if isPlaying {
                    studio.stop()
                } else {
                    Task { await studio.play(clip) }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isPlaying ? Color.accentNavi : Color.accentNavi.opacity(0.1))
                        .frame(width: 38, height: 38)
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isPlaying ? .white : .accentNavi)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label(clip.typeLabel, systemImage: clip.typeIcon)
                    if clip.clipType == .tts {
                        Text("·")
                        Text(clip.voiceName)
                    }
                    Text("·")
                    Text(clip.createdAt.relativeString)
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // Share / export button
            if let url = studio.audioURL(for: clip) {
                #if os(iOS)
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                #else
                Button {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                #endif
            }

            // Delete button
            Button { Task { await studio.delete(clip) } } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isPlaying
                                ? AnyShapeStyle(Color.accentNavi.opacity(0.4))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [.white.opacity(0.12), .white.opacity(0.04)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )),
                            lineWidth: isPlaying ? 1.5 : 0.5
                        )
                )
        )
    }

    // MARK: - iOS mini player bar

    private var iOSMiniPlayer: some View {
        VStack(spacing: 0) {
            if let err = studio.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red).font(.system(size: 12))
                    Text(err).font(.system(size: 12)).foregroundColor(.red)
                    Spacer()
                    Button { studio.errorMessage = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.red.opacity(0.07))
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(studio.clips.prefix(10)) { clip in
                        clipRow(clip).padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
            .background(Color.sidebarBackground)
        }
    }
}

// MARK: - TTS Panel

private struct TTSPanel: View {
    @ObservedObject var studio: VoiceStudioManager
    @ObservedObject var client: ElevenLabsClient

    @State private var text = ""
    @State private var stability: Double = 0.5
    @State private var similarityBoost: Double = 0.75
    @State private var style: Double = 0.0
    @State private var selectedVoiceID = SettingsStore.shared.selectedVoiceID
    @State private var selectedVoiceName = SettingsStore.shared.selectedVoiceName
    @State private var showVoicePicker = false
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Voice selector
            voiceSelector

            // Text input
            VStack(alignment: .leading, spacing: 6) {
                Text("Text att läsa upp")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Skriv eller klistra in text här…")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.top, 12)
                            .padding(.leading, 12)
                    }
                    TextEditor(text: $text)
                        .focused($textFocused)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 200)
                        .padding(10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.userBubble)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                        )
                )
            }

            // Voice settings
            GlassCard(cornerRadius: 10, padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Röstinställningar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    sliderRow(label: "Stabilitet", value: $stability,
                              hint: "Låg = varierat, Hög = konsistent")
                    sliderRow(label: "Likhet", value: $similarityBoost,
                              hint: "Hur nära originalrösten")
                    sliderRow(label: "Stil", value: $style,
                              hint: "Expressivitet (kräver v2-modell)")
                }
            }

            // Error banner
            if let err = studio.errorMessage {
                errorBanner(err)
            }

            // Generate button
            generateButton(
                label: studio.isGenerating ? "Genererar…" : "Generera tal",
                icon: "waveform",
                enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !studio.isGenerating
            ) {
                Task {
                    await studio.generateTTS(
                        text: text,
                        voiceID: selectedVoiceID.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : selectedVoiceID,
                        voiceName: selectedVoiceName.isEmpty ? "Rachel" : selectedVoiceName,
                        stability: stability,
                        similarityBoost: similarityBoost,
                        style: style
                    )
                }
            }

            #if os(macOS)
            Divider().opacity(0.1)
            clipListMac
            #endif
        }
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerSheet(
                selectedVoiceID: $selectedVoiceID,
                selectedVoiceName: $selectedVoiceName,
                voices: client.availableVoices
            )
        }
    }

    private var voiceSelector: some View {
        GlassCard(cornerRadius: 10, padding: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Röst")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(selectedVoiceName.isEmpty ? "Välj röst" : selectedVoiceName)
                        .font(.system(size: 14, weight: .medium))
                }
                Spacer()
                Button { showVoicePicker = true } label: {
                    HStack(spacing: 5) {
                        if client.availableVoices.isEmpty {
                            ProgressView().scaleEffect(0.6)
                        }
                        Text("Byt")
                            .font(.system(size: 12))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.accentNavi)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var clipListMac: some View {
        if !studio.clips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Senaste klipp")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(studio.clips.filter { $0.clipType == .tts }.prefix(5)) { clip in
                    miniClipRow(clip)
                }
            }
        }
    }

    private func miniClipRow(_ clip: VoiceClip) -> some View {
        let isPlaying = studio.playingClipID == clip.id
        return HStack(spacing: 8) {
            Button {
                if isPlaying { studio.stop() } else { Task { await studio.play(clip) } }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentNavi)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Text(clip.displayTitle)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(.secondary)

            Spacer()

            Button { Task { await studio.delete(clip) } } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPlaying ? Color.accentNavi.opacity(0.08) : Color.clear)
        )
    }

    private func sliderRow(label: String, value: Binding<Double>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accentNavi)
            }
            Slider(value: value, in: 0...1, step: 0.01)
                .tint(.accentNavi)
            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))
        }
    }
}

// MARK: - SFX Panel

private struct SFXPanel: View {
    @ObservedObject var studio: VoiceStudioManager

    @State private var text = ""
    @State private var duration: Double = 5.0
    @State private var influence: Double = 0.3
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Beskriv ljudeffekten")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("T.ex. \"regn mot ett fönster\", \"lasersvar\", \"glada applåder\"…")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.top, 12)
                            .padding(.leading, 12)
                    }
                    TextEditor(text: $text)
                        .focused($textFocused)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90, maxHeight: 160)
                        .padding(10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.userBubble)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                        )
                )
            }

            // Parameters
            GlassCard(cornerRadius: 10, padding: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Parametrar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Längd")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f sek", duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.accentNavi)
                        }
                        Slider(value: $duration, in: 0.5...22, step: 0.5)
                            .tint(.accentNavi)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Promptstyrning")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f", influence))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.accentNavi)
                        }
                        Slider(value: $influence, in: 0...1, step: 0.05)
                            .tint(.accentNavi)
                        Text("Hur nära prompten ljudet skall följa")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }

            // Error banner
            if let err = studio.errorMessage {
                errorBanner(err)
            }

            // Generate button
            generateButton(
                label: studio.isGenerating ? "Genererar…" : "Generera ljud",
                icon: "speaker.wave.3.fill",
                enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !studio.isGenerating
            ) {
                Task { await studio.generateSFX(text: text, duration: duration, influence: influence) }
            }

            #if os(macOS)
            Divider().opacity(0.1)
            sfxClipListMac
            #endif
        }
    }

    @ViewBuilder
    private var sfxClipListMac: some View {
        if studio.clips.contains(where: { $0.clipType == .sfx }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Senaste klipp")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                ForEach(studio.clips.filter { $0.clipType == .sfx }.prefix(5)) { clip in
                    let isPlaying = studio.playingClipID == clip.id
                    HStack(spacing: 8) {
                        Button {
                            if isPlaying { studio.stop() } else { Task { await studio.play(clip) } }
                        } label: {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentNavi)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        Text(clip.displayTitle)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button { Task { await studio.delete(clip) } } label: {
                            Image(systemName: "trash").font(.system(size: 10)).foregroundColor(.red.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isPlaying ? Color.accentNavi.opacity(0.08) : Color.clear)
                    )
                }
            }
        }
    }
}

// MARK: - Shared helpers

private func generateButton(
    label: String,
    icon: String,
    enabled: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
            Text(label).font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(enabled ? Color.accentNavi : Color.secondary.opacity(0.3))
        )
        .foregroundColor(.white)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
}

private func errorBanner(_ message: String) -> some View {
    HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.red).font(.system(size: 12))
        Text(message).font(.system(size: 12)).foregroundColor(.red.opacity(0.9))
        Spacer()
    }
    .padding(10)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.red.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
            )
    )
}

// MARK: - Voice Picker Sheet

private struct VoicePickerSheet: View {
    @Binding var selectedVoiceID: String
    @Binding var selectedVoiceName: String
    let voices: [ElevenLabsVoice]
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [ElevenLabsVoice] {
        search.isEmpty ? voices : voices.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if voices.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Laddar röster…")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { voice in
                        Button {
                            selectedVoiceID = voice.voice_id
                            selectedVoiceName = voice.name
                            SettingsStore.shared.selectedVoiceID = voice.voice_id
                            SettingsStore.shared.selectedVoiceName = voice.name
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(voice.voice_id)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                Spacer()
                                if voice.voice_id == selectedVoiceID {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.accentNavi)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .searchable(text: $search, prompt: "Sök röst")
                }
            }
            .navigationTitle("Välj röst")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 460)
        #endif
    }
}

// MARK: - Clip Detail Sheet

private struct ClipDetailSheet: View {
    let clip: VoiceClip
    @StateObject private var studio = VoiceStudioManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: clip.typeIcon)
                    .font(.system(size: 48))
                    .foregroundColor(.accentNavi.opacity(0.6))

                VStack(spacing: 8) {
                    Text(clip.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                    if clip.clipType == .tts {
                        Text(clip.voiceName)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Text(clip.createdAt.relativeString)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                let isPlaying = studio.playingClipID == clip.id
                Button {
                    if isPlaying { studio.stop() } else { Task { await studio.play(clip) } }
                } label: {
                    Label(isPlaying ? "Stoppa" : "Spela upp", systemImage: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32).padding(.vertical, 14)
                        .background(Color.accentNavi, in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(32)
            .navigationTitle("Klipp")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("VoiceStudioView") {
    VoiceStudioView()
        .frame(width: 900, height: 600)
}
