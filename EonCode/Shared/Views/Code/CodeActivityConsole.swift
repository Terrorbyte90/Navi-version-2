import SwiftUI

// MARK: - CodeActivityConsole
// 3-layer visual feedback for agent activity:
// Layer 1: Worker Orbs (compact pulsing circles)
// Layer 2: Live Activity Cards (glass cards with streaming code)
// Layer 3: Quiet Log (single status line, auto-fades)

struct CodeActivityConsole: View {
    let workerStatuses: [WorkerStatus]
    let quietLog: String

    // Maximum live cards visible at once
    private let maxCards = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Layer 1: Worker Orbs
            if !workerStatuses.isEmpty {
                WorkerOrbsRow(statuses: workerStatuses)
            }

            // Layer 2: Live Activity Cards (show active/recent files)
            let activeCards = recentActiveCards
            if !activeCards.isEmpty {
                VStack(spacing: 6) {
                    ForEach(activeCards) { status in
                        LiveActivityCard(status: status)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: activeCards.map { $0.id })
            }

            // Layer 3: Quiet Log
            if !quietLog.isEmpty {
                QuietLogLine(text: quietLog)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var recentActiveCards: [WorkerStatus] {
        let active = workerStatuses.filter { $0.isActive && $0.currentFile != nil }
        let recent = workerStatuses.filter { $0.isDone && $0.currentFile != nil }
        return Array((active + recent).prefix(maxCards))
    }
}

// MARK: - WorkerOrbsRow

struct WorkerOrbsRow: View {
    let statuses: [WorkerStatus]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(statuses) { status in
                WorkerOrb(status: status)
            }
            Spacer()
        }
    }
}

// MARK: - WorkerOrb

struct WorkerOrb: View {
    let status: WorkerStatus

    @State private var ripple = false

    var body: some View {
        ZStack {
            // Ripple ring (active only)
            if status.isActive {
                Circle()
                    .stroke(Color.accentNavi.opacity(0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .scaleEffect(ripple ? 1.8 : 1.0)
                    .opacity(ripple ? 0.0 : 0.6)
                    .animation(
                        .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: ripple
                    )
            }

            // Core orb
            Circle()
                .fill(orbFill)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle().stroke(orbBorder, lineWidth: 1.5)
                )

            // Checkmark when done
            if status.isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.green)
            }
        }
        .frame(width: 22, height: 22)
        .onAppear { if status.isActive { ripple = true } }
        .onChange(of: status.isActive) { _, active in
            ripple = active
        }
    }

    private var orbFill: Color {
        if status.isDone { return Color.green.opacity(0.2) }
        if status.isActive { return Color.accentNavi }
        return Color(.quaternarySystemFill)
    }

    private var orbBorder: Color {
        if status.isDone { return .green.opacity(0.6) }
        if status.isActive { return Color.accentNavi.opacity(0.8) }
        return Color.secondary.opacity(0.3)
    }
}

// MARK: - LiveActivityCard

struct LiveActivityCard: View {
    let status: WorkerStatus

    var body: some View {
        HStack(spacing: 10) {
            // Left accent line
            Rectangle()
                .fill(status.isDone ? Color.green : Color.accentNavi)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 2) {
                // Filename row
                HStack {
                    Text(status.currentFile ?? "…")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    // Worker label
                    Text("W\(status.workerIndex + 1)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }

                // Live code preview
                if !status.liveCode.isEmpty && !status.isDone {
                    HStack(spacing: 2) {
                        Text(liveCodePreview)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        // Blinking cursor
                        BlinkingCursor()
                    }
                } else if status.isDone {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text("Klar")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .opacity(status.isDone ? 0.55 : 1.0)
        .animation(.easeOut(duration: 0.3), value: status.isDone)
    }

    private var liveCodePreview: String {
        // Take last line of liveCode that has actual content
        let lines = status.liveCode.components(separatedBy: "\n")
        return lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? status.liveCode.suffix(60).description
    }
}

// MARK: - BlinkingCursor

struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.accentNavi)
            .frame(width: 2, height: 12)
            .opacity(visible ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - QuietLogLine

struct QuietLogLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.7))
            .lineLimit(1)
            .truncationMode(.middle)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: text)
    }
}

#Preview {
    CodeActivityConsole(
        workerStatuses: [
            WorkerStatus(workerIndex: 0, isActive: true, currentFile: "HomeView.swift",
                         liveCode: "struct HomeView: View {", filesWritten: [], isDone: false),
            WorkerStatus(workerIndex: 1, isActive: false, currentFile: "DataModel.swift",
                         liveCode: "", filesWritten: ["DataModel.swift"], isDone: true),
            WorkerStatus(workerIndex: 2, isActive: false, currentFile: nil, filesWritten: [], isDone: false),
            WorkerStatus(workerIndex: 3, isActive: false, currentFile: nil, filesWritten: [], isDone: false),
        ],
        quietLog: "write_file  Sources/Views/HomeView.swift  •  2.1s sedan"
    )
    .padding()
    .background(Color.chatBackground)
}
