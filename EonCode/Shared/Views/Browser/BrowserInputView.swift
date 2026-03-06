import SwiftUI

// MARK: - BrowserInputView
// Input for giving the browser agent a goal or responding to its questions.

struct BrowserInputView: View {
    @ObservedObject var agent: BrowserAgent
    @State private var input = ""
    @FocusState private var isFocused: Bool

    var placeholder: String {
        switch agent.status {
        case .waitingForUser: return "Agenten väntar på ditt svar… (\(agent.userQuestion))"
        case .working:        return "Pågår: \(agent.pageTitle.isEmpty ? "surfar…" : agent.pageTitle)"
        default:              return "Ge webbläsaren ett mål…"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)
            HStack(spacing: 10) {
                // URL indicator
                if let url = agent.currentURL {
                    Text(url.host ?? "")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                }

                TextField(placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit { handleSend() }
                    .foregroundColor(agent.status == .waitingForUser ? .yellow : .primary)

                mainButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var mainButton: some View {
        switch agent.status {
        case .working:
            Button("Avbryt") {
                agent.cancel()
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            .font(.system(size: 13, weight: .medium))

        case .waitingForUser:
            Button("Skicka") {
                handleSend()
            }
            .buttonStyle(.plain)
            .foregroundColor(.yellow)
            .font(.system(size: 13, weight: .medium))
            .disabled(input.isBlank)

        default:
            Button {
                handleSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(input.isBlank ? .secondary : .accentEon)
            }
            .buttonStyle(.plain)
            .disabled(input.isBlank)
        }
    }

    private func handleSend() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        isFocused = false

        switch agent.status {
        case .waitingForUser:
            agent.provideUserInput(text)
        default:
            Task { await agent.execute(goal: text) }
        }
    }
}
