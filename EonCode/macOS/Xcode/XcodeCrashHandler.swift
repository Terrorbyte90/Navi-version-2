#if os(macOS)
import Foundation

struct XcodeCrashHandler {
    // Monitor for Xcode crashes and attempt recovery
    static func handleCrash(projectPath: String) async -> String {
        // Check if Xcode is running
        let checkCmd = "pgrep -x Xcode"
        let result = await MacTerminalExecutor.run(checkCmd)

        if result.trimmed.isEmpty {
            // Xcode crashed, try to restart build via xcodebuild CLI
            return await MacTerminalExecutor.run(
                "xcodebuild -project '\(projectPath)' build 2>&1 | tail -30"
            )
        }

        return "Xcode kör normalt"
    }

    static func readLatestCrashLog() async -> String {
        let logsDir = "~/Library/Logs/DiagnosticReports"
        let cmd = "ls -t \(logsDir)/Xcode_*.ips 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -100"
        return await MacTerminalExecutor.run(cmd)
    }
}
#endif
