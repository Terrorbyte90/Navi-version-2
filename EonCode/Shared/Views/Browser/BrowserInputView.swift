import SwiftUI

// MARK: - BrowserInputView
// Input for giving the browser agent a goal or responding to its questions.

struct BrowserInputView: View {
    @ObservedObject var agent: BrowserAgent
    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var isWaiting: Bool { agent.status == .waitingForUser }
    private var isWorking: Bool { agent.status == .working }

    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            statusDot

            // Text field
            ZStack(alignment: .leading) {
                if input.isEmpty {
                    Text(placeholderText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .allowsHitTesting(false)
                }
                TextField("", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isFocused)
                    .onSubmit { handleSend() }
                    .foregroundColor(isWaiting ? .yellow : .primary)
                    .disabled(isWorking)
            }

            // Action button
            actionButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Status dot

    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(dotColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Image(systemName: dotIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dotColor)
        }
    }

    private var dotColor: Color {
        switch agent.status {
        case .working:        return .green
        case .waitingForUser: return .yellow
        case .complete:       return .accentEon
        case .failed:         return .red
        case .idle:           return .secondary
        }
    }

    private var dotIcon: String {
        switch agent.status {
        case .working:        return "cpu"
        case .waitingForUser: return "questionmark"
        case .complete:       return "checkmark"
        case .failed:         return "xmark"
        case .idle:           return "globe"
        }
    }

    // MARK: - Placeholder

    private var placeholderText: String {
        switch agent.status {
        case .waitingForUser: return agent.userQuestion.isEmpty ? "Skriv ditt svar…" : agent.userQuestion
        case .working:        return "Agenten arbetar…"
        case .complete:       return "Klart! Ge ett nytt mål…"
        case .failed:         return "Misslyckades. Försök igen…"
        case .idle:           return "Ge webbläsaren ett mål…"
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if isWorking {
            Button {
                agent.cancel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                    Text("Avbryt")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        } else if isWaiting {
            Button { handleSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(input.isBlank ? .secondary.opacity(0.4) : .yellow)
            }
            .buttonStyle(.plain)
            .disabled(input.isBlank)
        } else {
            Button { handleSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(input.isBlank ? .secondary.opacity(0.3) : .accentEon)
            }
            .buttonStyle(.plain)
            .disabled(input.isBlank)
        }
    }

    // MARK: - Send

    private func handleSend() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        isFocused = false

        if isWaiting {
            agent.provideUserInput(text)
        } else {
            Task { await agent.execute(goal: text) }
        }
    }
}

// MARK: - Preview

#Preview("BrowserInputView") {
    VStack {
        BrowserInputView(agent: BrowserAgent.shared)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
