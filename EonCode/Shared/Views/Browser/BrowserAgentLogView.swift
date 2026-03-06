import SwiftUI

// MARK: - BrowserAgentLogView
// Shows the browser agent's steps and thoughts in real time.

struct BrowserAgentLogView: View {
    @ObservedObject var agent: BrowserAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(.accentEon)
                    .font(.system(size: 12))
                Text("Agent-log")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(agent.log.count) steg")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.15)

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(agent.log) { entry in
                            BrowserLogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: agent.log.count) { _ in
                    if let last = agent.log.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Status badge
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if agent.status == .working {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.03))
        }
        .background(Color.chatBackground)
    }

    private var statusColor: Color {
        switch agent.status {
        case .idle: return .secondary
        case .working: return .green
        case .waitingForUser: return .yellow
        case .complete: return .accentEon
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch agent.status {
        case .idle: return "Inaktiv"
        case .working: return "Arbetar…"
        case .waitingForUser: return "Väntar på dig"
        case .complete: return "Klar"
        case .failed: return "Misslyckades"
        }
    }
}

struct BrowserLogEntryRow: View {
    let entry: BrowserLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.displayText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(entry.isError ? .red : .primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
