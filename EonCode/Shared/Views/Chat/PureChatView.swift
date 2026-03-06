import SwiftUI

// MARK: - Pure Chat View (ChatGPT/Claude.ai-style, no project context)

struct PureChatView: View {
    @StateObject private var manager = ChatManager.shared
    @StateObject private var memoryManager = MemoryManager.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isShowingImagePicker = false
    @State private var scrollProxy: ScrollViewProxy?

    var conversation: ChatConversation? { manager.activeConversation }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            chatTopBar

            Divider().opacity(0.15)

            if let conv = conversation {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(conv.messages) { msg in
                                PureChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            if manager.isStreaming {
                                StreamingBubble(text: manager.streamingText)
                                    .id("streaming")
                            }
                        }
                        .padding()
                    }
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: conv.messages.count) { _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: manager.streamingText) { _ in
                        scrollToBottom(proxy)
                    }
                }
            } else {
                // Empty state
                chatEmptyState
            }

            Divider().opacity(0.15)

            // Input bar
            chatInputBar
        }
        .background(Color.chatBackground)
        .onAppear {
            if manager.activeConversation == nil && !manager.conversations.isEmpty {
                manager.activeConversation = manager.conversations.first
            }
        }
    }

    // MARK: - Top bar

    var chatTopBar: some View {
        HStack(spacing: 12) {
            // Model picker
            if let conv = conversation {
                Menu {
                    ForEach(ClaudeModel.allCases) { model in
                        Button(model.displayName) {
                            if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                                manager.conversations[idx].model = model
                                manager.activeConversation?.model = model
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                        Text(conv.model.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Total cost
            if let conv = conversation, conv.totalCostSEK > 0 {
                Text(CostCalculator.shared.formatSEK(conv.totalCostSEK))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            // New chat
            Button {
                _ = manager.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.accentEon)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    var chatEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.accentEon.opacity(0.4))
            Text("Ny chatt")
                .font(.system(size: 22, weight: .bold))
            Text("Prata direkt med Claude — utan projektkontext.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            GlassButton("Starta ny chatt", icon: "plus", isPrimary: true) {
                _ = manager.newConversation()
            }
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar

    var chatInputBar: some View {
        VStack(spacing: 8) {
            // Image previews
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            #if os(iOS)
                            if let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                    .overlay(
                                        Button { selectedImages.remove(at: idx) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                        }
                                        .padding(4),
                                        alignment: .topTrailing
                                    )
                            }
                            #else
                            if let ns = NSImage(data: data) {
                                Image(nsImage: ns)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                    .overlay(
                                        Button { selectedImages.remove(at: idx) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                        }
                                        .padding(4),
                                        alignment: .topTrailing
                                    )
                            }
                            #endif
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 10) {
                // Image attach
                Button {
                    isShowingImagePicker = true
                } label: {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Text input
                TextField("Skriv ett meddelande…", text: $inputText, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { sendMessage() }

                // Send
                Button(action: sendMessage) {
                    Image(systemName: manager.isStreaming ? "stop.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(inputText.isBlank && !manager.isStreaming ? .secondary : .accentEon)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isBlank && !manager.isStreaming)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Send

    private func sendMessage() {
        guard !inputText.isBlank, var conv = conversation else { return }
        let text = inputText
        let images = selectedImages
        inputText = ""
        selectedImages = []

        Task {
            try? await manager.send(text: text, images: images, in: &conv) { _ in }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = manager.activeConversation?.messages.last else {
            if manager.isStreaming { proxy.scrollTo("streaming", anchor: .bottom) }
            return
        }
        proxy.scrollTo(manager.isStreaming ? "streaming" : last.id, anchor: .bottom)
    }
}

// MARK: - Chat bubble

struct PureChatBubble: View {
    let message: PureChatMessage
    @State private var isSpeaking = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Images
                if let imgs = message.imageData, !imgs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(imgs.enumerated()), id: \.offset) { _, data in
                                #if os(iOS)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFit()
                                        .frame(maxHeight: 200).cornerRadius(10)
                                }
                                #else
                                if let ns = NSImage(data: data) {
                                    Image(nsImage: ns).resizable().scaledToFit()
                                        .frame(maxHeight: 200).cornerRadius(10)
                                }
                                #endif
                            }
                        }
                    }
                }

                // Text / Markdown
                if isUser {
                    Text(message.content)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentEon.opacity(0.2))
                        .cornerRadius(18)
                        .textSelection(.enabled)
                } else {
                    MarkdownTextView(text: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(18)
                        .textSelection(.enabled)
                }

                // Cost + TTS
                HStack(spacing: 8) {
                    if let cost = message.costSEK, cost > 0 {
                        Text(CostCalculator.shared.formatSEK(cost))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    if !isUser {
                        Button {
                            if isSpeaking {
                                ElevenLabsClient.shared.stop()
                                isSpeaking = false
                            } else {
                                isSpeaking = true
                                Task {
                                    await ElevenLabsClient.shared.speak(message.content)
                                    isSpeaking = false
                                }
                            }
                        } label: {
                            Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.2")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Simple Markdown text renderer (reuses existing MarkdownPreview patterns)

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        // Reuse the app's code block detection
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    Text(.init(t)) // AttributedString markdown
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !lang.isEmpty {
                            Text(lang)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(12)
                                .textSelection(.enabled)
                        }
                    }
                    .background(Color.codeBackground)
                    .cornerRadius(10)
                }
            }
        }
    }

    enum Block { case text(String); case code(String, String) }

    func parseBlocks(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var inCode = false
        var lang = ""
        var codeBuf: [String] = []
        var textBuf: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(lang, codeBuf.joined(separator: "\n")))
                    codeBuf = []; inCode = false; lang = ""
                } else {
                    if !textBuf.isEmpty {
                        blocks.append(.text(textBuf.joined(separator: "\n")))
                        textBuf = []
                    }
                    lang = String(line.dropFirst(3))
                    inCode = true
                }
            } else if inCode {
                codeBuf.append(line)
            } else {
                textBuf.append(line)
            }
        }
        if !codeBuf.isEmpty { blocks.append(.code(lang, codeBuf.joined(separator: "\n"))) }
        if !textBuf.isEmpty { blocks.append(.text(textBuf.joined(separator: "\n"))) }
        return blocks
    }
}
