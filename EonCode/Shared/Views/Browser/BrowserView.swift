import SwiftUI
import WebKit

// MARK: - BrowserView

struct BrowserView: View {
    @StateObject private var agent = BrowserAgent.shared
    @State private var showControlSheet = false
    @State private var controlSheetDetent: PresentationDetent = .fraction(0.35)

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
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                Divider().opacity(0.08)
                WebViewContainer(agent: agent)
            }

            // Glass bottom bar
            BrowserGlassBar(agent: agent, showControlSheet: $showControlSheet)
        }
        .sheet(isPresented: $showControlSheet) {
            BrowserControlSheet(agent: agent)
                .frame(minWidth: 500, minHeight: 400)
        }
    }
    #endif

    // MARK: - iOS

    var iOSLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                Divider().opacity(0.08)
                WebViewContainer(agent: agent)
                    .ignoresSafeArea(edges: .bottom)
            }

            // Glass bottom bar
            BrowserGlassBar(agent: agent, showControlSheet: $showControlSheet)
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $showControlSheet) {
            BrowserControlSheet(agent: agent)
                .presentationDetents([.fraction(0.35), .medium, .large], selection: $controlSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

// MARK: - Glass Bottom Bar

struct BrowserGlassBar: View {
    @ObservedObject var agent: BrowserAgent
    @Binding var showControlSheet: Bool
    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var isIdle: Bool {
        if case .idle = agent.status { return true }
        return false
    }
    private var isComplete: Bool {
        if case .complete = agent.status { return true }
        return false
    }
    private var isFailed: Bool {
        if case .failed = agent.status { return true }
        return false
    }
    private var isWorking: Bool {
        switch agent.status {
        case .working, .planning: return true
        default: return false
        }
    }
    private var isWaiting: Bool {
        if case .waitingForUser = agent.status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // "Ta kontroll" button — only when agent is running
            if agent.canTakeControl && (isWorking || isWaiting) {
                Button { showControlSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11))
                        Text("Ta kontroll")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Main glass bar
            VStack(spacing: 6) {
                // Status/thought line
                if !isIdle || !agent.currentThought.isEmpty {
                    HStack(spacing: 6) {
                        statusDot
                        Text(agent.currentThought.isEmpty ? statusText : agent.currentThought)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)

                        Spacer()

                        // Session cost
                        if agent.sessionCost.apiCalls > 0 {
                            Text(agent.sessionCost.formatted)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }

                        // Cancel button
                        if isWorking {
                            Button { agent.cancel() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 22, height: 22)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Input field
                HStack(alignment: .bottom, spacing: 0) {
                    statusIcon
                        .frame(width: 32, height: 32)

                    TextField(placeholderText, text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit { handleSend() }
                        .foregroundColor(isWaiting ? .yellow : .white)
                        .disabled(isWorking && !isWaiting)
                        .padding(.vertical, 8)

                    Button { handleSend() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(input.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : .black)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle().fill(
                                    input.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.white.opacity(0.06)
                                    : isWaiting ? Color.yellow : Color.white
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || (isWorking && !isWaiting))
                    .padding(.trailing, 4)
                }
                .padding(.leading, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(
                                    isWaiting ? Color.yellow.opacity(0.4) :
                                    isFocused ? Color.accentEon.opacity(0.4) :
                                    Color.white.opacity(0.1),
                                    lineWidth: 0.5
                                )
                        )
                )
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
            .background(
                glassBackground
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: agent.canTakeControl)
    }

    private var glassBackground: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(Color.black.opacity(0.4))
        }
        .overlay(alignment: .top) {
            // Loading progress
            if isWorking && agent.loadingProgress > 0 && agent.loadingProgress < 1 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentEon.opacity(0.6))
                        .frame(width: geo.size.width * agent.loadingProgress, height: 2)
                        .animation(.easeInOut(duration: 0.3), value: agent.loadingProgress)
                }
                .frame(height: 2)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 6, height: 6)
            .overlay(
                Circle()
                    .fill(dotColor.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .opacity(isWorking ? 1 : 0)
            )
    }

    @ViewBuilder
    private var statusIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundColor(dotColor)
    }

    private var dotColor: Color {
        switch agent.status {
        case .working, .planning: return .green
        case .waitingForUser:     return .yellow
        case .complete:           return .accentEon
        case .failed:             return .red
        case .idle:               return .white.opacity(0.4)
        }
    }

    private var iconName: String {
        switch agent.status {
        case .working, .planning: return "cpu"
        case .waitingForUser:     return "questionmark"
        case .complete:           return "checkmark"
        case .failed:             return "xmark"
        case .idle:               return "globe"
        }
    }

    private var statusText: String {
        switch agent.status {
        case .planning:              return "Planerar…"
        case .working(let s, let t): return "Steg \(s)/\(t)"
        case .waitingForUser:        return "Väntar på dig"
        case .complete:              return "Klar"
        case .failed:                return "Misslyckades"
        case .idle:                  return ""
        }
    }

    private var placeholderText: String {
        switch agent.status {
        case .waitingForUser: return agent.userQuestion.isEmpty ? "Skriv ditt svar…" : agent.userQuestion
        case .working, .planning: return "Agenten arbetar…"
        case .complete:       return "Klart! Ge ett nytt mål…"
        case .failed:         return "Misslyckades. Försök igen…"
        case .idle:           return "Ge webbläsaren ett mål…"
        }
    }

    private func handleSend() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        isFocused = false

        if isWaiting {
            agent.provideUserInput(text)
        } else {
            if isComplete || isFailed { agent.status = .idle }
            Task { await agent.execute(goal: text) }
        }
    }
}

// MARK: - Control Sheet (pull up to change goal / see log)

struct BrowserControlSheet: View {
    @ObservedObject var agent: BrowserAgent
    @Environment(\.dismiss) private var dismiss
    @State private var newGoal = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentEon)
                Text("Kontrollpanel")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                // Session cost
                if agent.sessionCost.apiCalls > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(agent.sessionCost.formatted)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentEon)
                        Text("\(agent.sessionCost.apiCalls) anrop")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.1)

            // Current goal
            if !agent.currentGoal.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktivt mål")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.currentGoal)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Sub-goals
            if !agent.subGoals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delmål")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    ForEach(agent.subGoals) { sg in
                        HStack(spacing: 8) {
                            Image(systemName: subGoalIcon(sg.status))
                                .font(.system(size: 11))
                                .foregroundColor(subGoalColor(sg.status))
                                .frame(width: 16)
                            Text(sg.description)
                                .font(.system(size: 12))
                                .foregroundColor(sg.status == .active ? .primary : .secondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 8)
            }

            // Change goal
            VStack(alignment: .leading, spacing: 8) {
                Text("Ändra mål")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Nytt mål…", text: $newGoal)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color.inputBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                        )

                    Button {
                        guard !newGoal.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        agent.updateGoal(newGoal)
                        newGoal = ""
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(newGoal.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary.opacity(0.3) : .accentEon)
                    }
                    .buttonStyle(.plain)
                    .disabled(newGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().opacity(0.1)

            // Agent log
            BrowserAgentLogView(agent: agent)

            // Actions
            HStack(spacing: 16) {
                Button {
                    agent.cancel()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("Stoppa").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { dismiss() } label: {
                    Text("Stäng")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }

    private func subGoalIcon(_ status: BrowserSubGoal.SubGoalStatus) -> String {
        switch status {
        case .pending:   return "circle"
        case .active:    return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private func subGoalColor(_ status: BrowserSubGoal.SubGoalStatus) -> Color {
        switch status {
        case .pending:   return .secondary.opacity(0.4)
        case .active:    return .accentEon
        case .completed: return .green
        case .failed:    return .red
        }
    }
}

// MARK: - Address Bar

struct BrowserAddressBar: View {
    @ObservedObject var agent: BrowserAgent
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
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Button { agent.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(agent.webView.canGoBack ? .primary : .secondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!agent.webView.canGoBack)

                Button { agent.webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(agent.webView.canGoForward ? .primary : .secondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!agent.webView.canGoForward)
            }

            HStack(spacing: 6) {
                Image(systemName: agent.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11))
                    .foregroundColor(agent.currentURL?.scheme == "https" ? .green : .secondary)

                if editingURL {
                    TextField("URL eller sökterm", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($urlFocused)
                        .onSubmit { navigateToInput() }
                        .onAppear {
                            urlText = agent.currentURL?.absoluteString ?? ""
                            urlFocused = true
                        }
                } else {
                    Text(displayURL.isEmpty ? "Ange URL…" : displayURL)
                        .font(.system(size: 14))
                        .foregroundColor(displayURL.isEmpty ? .secondary.opacity(0.4) : .primary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { editingURL = true }
                }

                if !displayURL.isEmpty {
                    Button { agent.webView.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(editingURL ? Color.accentEon.opacity(0.5) : Color.inputBorder, lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.chatBackground)
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

#Preview("BrowserView") {
    BrowserView().preferredColorScheme(.dark)
}
