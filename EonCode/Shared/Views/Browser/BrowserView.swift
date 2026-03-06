import SwiftUI
import WebKit

// MARK: - BrowserView

struct BrowserView: View {
    @StateObject private var agent = BrowserAgent.shared
    @State private var showLog = false

    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    var macOSLayout: some View {
        HSplitView {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                WebViewContainer(agent: agent)
            }
            .frame(minWidth: 520)

            VStack(spacing: 0) {
                BrowserAgentLogView(agent: agent)
                BrowserInputView(agent: agent)
            }
            .frame(width: 300)
            .background(Color.chatBackground)
        }
    }
    #endif

    // MARK: - iOS

    var iOSLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                WebViewContainer(agent: agent)
                    .ignoresSafeArea(edges: .bottom)
            }

            // Floating bottom panel
            BrowserBottomPanel(agent: agent, showLog: $showLog)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Address Bar

struct BrowserAddressBar: View {
    @ObservedObject var agent: BrowserAgent
    @State private var progressWidth: CGFloat = 0
    @State private var editingURL = false
    @State private var urlText = ""
    @FocusState private var urlFocused: Bool

    var displayURL: String {
        guard let url = agent.currentURL else { return "" }
        let str = url.absoluteString
        return str.hasPrefix("https://") ? String(str.dropFirst(8)) :
               str.hasPrefix("http://")  ? String(str.dropFirst(7)) : str
    }

    var body: some View {
        HStack(spacing: 8) {
            // Back / Forward
            Button { agent.webView.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(agent.webView.canGoBack ? .primary : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!agent.webView.canGoBack)

            Button { agent.webView.goForward() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(agent.webView.canGoForward ? .primary : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!agent.webView.canGoForward)

            // URL pill
            HStack(spacing: 6) {
                // Lock / globe icon
                Image(systemName: agent.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11))
                    .foregroundColor(agent.currentURL?.scheme == "https" ? .green : .secondary)

                if editingURL {
                    TextField("URL eller sökterm", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($urlFocused)
                        .onSubmit {
                            navigateToInput()
                        }
                        .onAppear {
                            urlText = agent.currentURL?.absoluteString ?? ""
                            urlFocused = true
                        }
                } else {
                    Text(displayURL.isEmpty ? "Ange URL eller ge agenten ett mål nedan" : displayURL)
                        .font(.system(size: 13))
                        .foregroundColor(displayURL.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { editingURL = true }
                }

                if agent.status == .working {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 14, height: 14)
                } else if !displayURL.isEmpty {
                    Button { agent.webView.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                editingURL ? Color.accentEon.opacity(0.6) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .frame(maxWidth: .infinity)
            .onTapGesture { if !editingURL { editingURL = true } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.chatBackground)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .leading) {
                Divider().opacity(0.15)
                // Loading progress line
                if agent.status == .working && agent.loadingProgress > 0 && agent.loadingProgress < 1 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentEon.opacity(0.8))
                            .frame(width: geo.size.width * agent.loadingProgress, height: 2)
                            .animation(.easeInOut(duration: 0.3), value: agent.loadingProgress)
                    }
                    .frame(height: 2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {} // absorb taps on bar background
    }

    private func navigateToInput() {
        editingURL = false
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let urlStr: String
        if raw.contains(".") && !raw.contains(" ") {
            urlStr = raw.hasPrefix("http") ? raw : "https://\(raw)"
        } else {
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            urlStr = "https://www.google.com/search?q=\(encoded)"
        }
        Task { try? await agent.navigate(to: urlStr) }
    }
}

// MARK: - Bottom Panel (iOS)

struct BrowserBottomPanel: View {
    @ObservedObject var agent: BrowserAgent
    @Binding var showLog: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Log toggle handle
            if !agent.log.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showLog.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 36, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            if showLog {
                BrowserAgentLogView(agent: agent)
                    .frame(height: 180)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider().opacity(0.12)
            BrowserInputView(agent: agent)
        }
        .background(
            Color.chatBackground
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: -4)
        )
    }
}

// MARK: - Previews

#Preview("BrowserView") {
    BrowserView()
        .preferredColorScheme(.dark)
}
