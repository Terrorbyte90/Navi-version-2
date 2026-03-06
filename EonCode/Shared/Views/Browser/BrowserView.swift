import SwiftUI

// MARK: - BrowserView
// Main view for the autonomous browser feature.

struct BrowserView: View {
    @StateObject private var agent = BrowserAgent.shared

    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }

    // MARK: - macOS: side-by-side

    var macOSLayout: some View {
        HSplitView {
            // Web content (left, wider)
            VStack(spacing: 0) {
                browserToolbar
                WebViewContainer(agent: agent)
            }
            .frame(minWidth: 500)

            // Agent log + input (right panel)
            VStack(spacing: 0) {
                BrowserAgentLogView(agent: agent)
                BrowserInputView(agent: agent)
            }
            .frame(width: 320)
        }
        .background(Color.chatBackground)
    }

    // MARK: - iOS: stacked

    var iOSLayout: some View {
        VStack(spacing: 0) {
            browserToolbar

            // Split: web on top, log below
            VStack(spacing: 0) {
                WebViewContainer(agent: agent)
                    .frame(minHeight: 300)

                Divider().opacity(0.2)

                BrowserAgentLogView(agent: agent)
                    .frame(maxHeight: 240)
            }

            BrowserInputView(agent: agent)
        }
        .background(Color.chatBackground)
    }

    // MARK: - Toolbar

    var browserToolbar: some View {
        HStack(spacing: 10) {
            // Back/Forward
            Button {
                if agent.webView.canGoBack { agent.webView.goBack() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(!agent.webView.canGoBack)

            Button {
                if agent.webView.canGoForward { agent.webView.goForward() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(!agent.webView.canGoForward)

            Button {
                agent.webView.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)

            // URL bar (display only)
            Text(agent.currentURL?.absoluteString ?? "Ange ett mål nedan för att börja surfa")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)

            // Status indicator
            if agent.status == .working {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
    }
}
