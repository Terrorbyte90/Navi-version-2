import SwiftUI

struct ChatView: View {
    @ObservedObject var agent: ProjectAgent
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isAgentMode = false
    @State private var showImagePicker = false
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(agent.conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming indicator
                        if agent.isRunning && !agent.streamingText.isEmpty {
                            StreamingBubble(text: agent.streamingText)
                                .id("streaming")
                        } else if agent.isRunning {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: agent.conversation.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: agent.streamingText) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
            }

            // Input bar
            InputBar(
                text: $inputText,
                selectedImages: $selectedImages,
                isAgentMode: $isAgentMode,
                isLoading: agent.isRunning,
                costText: agent.lastCostSEK > 0 ? CostCalculator.shared.formatSEK(agent.lastCostSEK) : nil,
                model: agent.conversation.model
            ) {
                sendMessage()
            }
        }
        .background(Color.chatBackground)
    }

    private func sendMessage() {
        let text = inputText.trimmed
        guard !text.isBlank || !selectedImages.isEmpty else { return }
        let images = selectedImages

        inputText = ""
        selectedImages = []

        agent.sendMessage(text, images: images, isAgentMode: isAgentMode)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if agent.isRunning {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = agent.conversation.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundColor(.accentEon)
                        Text(message.model?.displayName ?? "EonCode")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Content
                contentView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? Color.userBubble : Color.assistantBubble)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                // Cost
                if message.costSEK > 0 {
                    Text(CostCalculator.shared.formatSEK(message.costSEK))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                switch content {
                case .text(let t):
                    if containsCode(t) {
                        renderTextWithCodeBlocks(t)
                    } else {
                        Text(t)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                case .image(let data, _):
                    if let uiImage = PlatformImage(data: data) {
                        Image(platformImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250)
                            .cornerRadius(8)
                    }
                case .toolUse(_, let name, _):
                    Label("Verktyg: \(name)", systemImage: "wrench.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                case .toolResult(_, let result, let isError):
                    Text(result.prefix(300))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(isError ? .red : .secondary)
                        .lineLimit(8)
                }
            }
        }
    }

    private func containsCode(_ text: String) -> Bool {
        text.contains("```")
    }

    @ViewBuilder
    private func renderTextWithCodeBlocks(_ text: String) -> some View {
        let parts = parseCodeBlocks(text)
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            if part.isCode {
                CodeBlockView(code: part.content, language: part.language)
            } else if !part.content.trimmed.isEmpty {
                Text(part.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    private func parseCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let lines = text.components(separatedBy: "\n")
        var currentText = ""
        var currentCode = ""
        var currentLang = ""
        var inCode = false

        for line in lines {
            if line.hasPrefix("```") && !inCode {
                if !currentText.isEmpty {
                    parts.append(TextPart(content: currentText, isCode: false, language: nil))
                    currentText = ""
                }
                currentLang = String(line.dropFirst(3)).trimmed
                inCode = true
            } else if line.hasPrefix("```") && inCode {
                parts.append(TextPart(content: currentCode, isCode: true, language: currentLang.isEmpty ? nil : currentLang))
                currentCode = ""
                currentLang = ""
                inCode = false
            } else if inCode {
                currentCode += line + "\n"
            } else {
                currentText += line + "\n"
            }
        }

        if !currentText.isEmpty { parts.append(TextPart(content: currentText, isCode: false, language: nil)) }
        if !currentCode.isEmpty { parts.append(TextPart(content: currentCode, isCode: true, language: nil)) }

        return parts
    }

    struct TextPart {
        let content: String
        let isCode: Bool
        let language: String?
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copyCode()
                } label: {
                    Label(copied ? "Kopierad!" : "Kopiera", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))

            Divider().opacity(0.3)

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                LargeTextView(text: code.trimmed, fontSize: 12, fontDesign: .monospaced)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.codeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    private func copyCode() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Streaming bubble

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundColor(.accentEon)
                        .symbolEffect(.pulse)
                    Text("Genererar…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Text(text.suffix(2000))  // Show last 2000 chars during streaming
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.assistantBubble)
                    )
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .top) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == i ? 1.4 : 1.0)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.assistantBubble))
            Spacer()
        }
        .onAppear {
            phase = 1
        }
    }
}

// MARK: - Input bar

struct InputBar: View {
    @Binding var text: String
    @Binding var selectedImages: [Data]
    @Binding var isAgentMode: Bool
    let isLoading: Bool
    let costText: String?
    let model: ClaudeModel
    let onSend: () -> Void

    @State private var showImagePicker = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)

            // Images preview
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { i, data in
                            ZStack(alignment: .topTrailing) {
                                if let img = PlatformImage(data: data) {
                                    Image(platformImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    selectedImages.remove(at: i)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Agent mode toggle
                Button {
                    isAgentMode.toggle()
                } label: {
                    Image(systemName: isAgentMode ? "robot.fill" : "robot")
                        .font(.system(size: 18))
                        .foregroundColor(isAgentMode ? .accentEon : .secondary)
                }
                .buttonStyle(.plain)
                .help("Agent-läge: " + (isAgentMode ? "PÅ" : "AV"))

                // Image attach
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Text input
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(isAgentMode ? "Ge agenten en uppgift…" : "Skriv ett meddelande…")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }

                    #if os(iOS)
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .frame(minHeight: 36, maxHeight: 120)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    #else
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .frame(minHeight: 36, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                    #endif
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

                // Send button
                Button(action: onSend) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(text.isBlank && selectedImages.isEmpty ? .secondary.opacity(0.3) : .accentEon)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading || (text.isBlank && selectedImages.isEmpty))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Status bar
            HStack {
                Text(model.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))

                if isAgentMode {
                    Text("· Agent-läge")
                        .font(.system(size: 11))
                        .foregroundColor(.accentEon.opacity(0.7))
                }

                Spacer()

                if let cost = costText {
                    Text(cost)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Platform image helpers

#if os(macOS)
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#else
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
