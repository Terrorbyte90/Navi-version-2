import Foundation
import WebKit

// MARK: - BrowserAgent
// Autonomous web browsing agent. Text-first, vision as fallback.

enum BrowserStatus { case idle, working, waitingForUser, complete, failed }

struct BrowserLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let displayText: String
    let isError: Bool

    init(_ text: String, isError: Bool = false) {
        self.timestamp = Date()
        self.displayText = text
        self.isError = isError
    }
}

@MainActor
final class BrowserAgent: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = BrowserAgent()

    @Published var status: BrowserStatus = .idle
    @Published var currentURL: URL?
    @Published var log: [BrowserLogEntry] = []
    @Published var pageTitle: String = ""
    @Published var userQuestion: String = ""
    @Published var loadingProgress: Double = 0

    let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }()

    private let api = ClaudeAPIClient.shared
    private var userInputContinuation: CheckedContinuation<String, Never>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        setupObservers()
    }

    // MARK: - KVO Observers

    private func setupObservers() {
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.loadingProgress = wv.estimatedProgress
            }
        }
        titleObservation = webView.observe(\.title, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.pageTitle = wv.title ?? ""
            }
        }
        urlObservation = webView.observe(\.url, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.currentURL = wv.url
            }
        }
    }

    // MARK: - Main execute loop

    func execute(goal: String) async {
        guard status != .working else { return }

        status = .working
        log = [BrowserLogEntry("🎯 Mål: \(goal)")]
        var attempt = 0
        let maxAttempts = 50
        var failureStreak = 0

        while status == .working && attempt < maxAttempts {
            attempt += 1

            // Extract page content
            let pageContent: PageContent
            do {
                pageContent = try await PageExtractor.extract(from: webView)
            } catch {
                appendLog("⚠️ Extraktion misslyckades: \(error.localizedDescription)", isError: true)
                failureStreak += 1
                if failureStreak > 3 { status = .failed; break }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            failureStreak = 0

            // Decide next action
            let action: BrowserAction
            do {
                action = try await BrowserActionDecider.decide(
                    goal: goal,
                    pageContent: pageContent,
                    history: log,
                    apiClient: api
                )
            } catch {
                appendLog("⚠️ Kunde inte bestämma nästa steg: \(error.localizedDescription)", isError: true)
                failureStreak += 1
                if failureStreak > 3 { status = .failed; break }
                continue
            }

            appendLog(action.logDescription)

            // Execute action
            do {
                switch action {
                case .navigate(let url):
                    try await navigate(to: url)

                case .click(let selector):
                    if let idx = linkIndex(from: selector), idx < pageContent.links.count {
                        try await navigate(to: pageContent.links[idx].href)
                    } else {
                        try await PageExtractor.clickElement(selector: selector, in: webView)
                        try? await Task.sleep(for: .seconds(1))
                    }

                case .type(let selector, let text):
                    try await PageExtractor.typeInField(selector: selector, text: text, in: webView)

                case .scroll(let direction):
                    try await PageExtractor.scroll(direction, in: webView)

                case .screenshot:
                    let data = try await ScreenshotAnalyzer.takeScreenshot(from: webView)
                    let analysis = try await ScreenshotAnalyzer.analyze(
                        screenshotData: data,
                        goal: goal,
                        context: log.suffix(5).map(\.displayText).joined(separator: "\n"),
                        apiClient: api
                    )
                    appendLog("👁 Vision: \(analysis)")

                case .waitForLoad:
                    try? await Task.sleep(for: .seconds(2))

                case .askUser(let question):
                    status = .waitingForUser
                    userQuestion = question
                    appendLog("❓ Väntar på svar: \(question)")
                    let answer = await waitForUserInput()
                    if answer.isEmpty { status = .idle; return }
                    appendLog("💬 Svar: \(answer)")
                    status = .working

                case .goalComplete(let summary):
                    appendLog("✅ Klart! \(summary)")
                    status = .complete

                case .goalFailed(let reason):
                    appendLog("❌ Misslyckades: \(reason)", isError: true)
                    failureStreak += 1
                    if failureStreak < 2 {
                        appendLog("🔄 Försöker alternativ strategi…")
                    } else {
                        status = .failed
                    }
                }
            } catch {
                appendLog("⚠️ Action-fel: \(error.localizedDescription)", isError: true)
                failureStreak += 1
                if failureStreak > 5 { status = .failed }
            }

            if status == .working {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        if status == .working {
            appendLog("⏹ Max antal steg nått (\(maxAttempts))")
            status = .complete
        }
    }

    // MARK: - Navigation

    func navigate(to urlString: String) async throws {
        let urlStr = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let url = URL(string: urlStr) else {
            throw BrowserError.navigationFailed(urlString)
        }

        // Cancel any pending navigation continuation
        navigationContinuation?.resume(throwing: BrowserError.navigationFailed("Cancelled"))
        navigationContinuation = nil

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            navigationContinuation = cont
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - User input

    func provideUserInput(_ input: String) {
        userInputContinuation?.resume(returning: input)
        userInputContinuation = nil
        userQuestion = ""
    }

    private func waitForUserInput() async -> String {
        await withCheckedContinuation { cont in
            userInputContinuation = cont
        }
    }

    // MARK: - Cancel

    func cancel() {
        webView.stopLoading()
        status = .idle
        userInputContinuation?.resume(returning: "")
        userInputContinuation = nil
        navigationContinuation?.resume(throwing: BrowserError.navigationFailed("Cancelled"))
        navigationContinuation = nil
        userQuestion = ""
    }

    // MARK: - Helpers

    private func appendLog(_ text: String, isError: Bool = false) {
        log.append(BrowserLogEntry(text, isError: isError))
    }

    private func linkIndex(from selector: String) -> Int? {
        guard selector.hasPrefix("["), selector.hasSuffix("]") else { return nil }
        let inner = selector.dropFirst().dropLast()
        return Int(inner)
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
            self.currentURL = webView.url
            self.pageTitle = webView.title ?? ""
            self.loadingProgress = 1.0
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            // Ignore cancelled navigation errors
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            self.navigationContinuation?.resume(throwing: error)
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            self.navigationContinuation?.resume(throwing: error)
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            self.loadingProgress = 0.1
        }
    }

    // Prevent popups
    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            Task { @MainActor in
                webView.load(navigationAction.request)
            }
        }
        return nil
    }
}
