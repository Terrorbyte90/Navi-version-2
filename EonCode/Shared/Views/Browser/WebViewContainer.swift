import SwiftUI
import WebKit

// MARK: - WebViewContainer
// Cross-platform WKWebView wrapper for use inside BrowserView.

#if os(iOS)

struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var agent: BrowserAgent

    func makeUIView(context: Context) -> WKWebView {
        agent.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#else

struct WebViewContainer: NSViewRepresentable {
    @ObservedObject var agent: BrowserAgent

    func makeNSView(context: Context) -> WKWebView {
        agent.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

#endif
