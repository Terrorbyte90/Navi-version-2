import Foundation

struct DiffEngine {
    // Myers diff algorithm for line-level diffs
    static func diff(old: String, new: String) -> [DiffHunk] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        return computeHunks(oldLines: oldLines, newLines: newLines)
    }

    private static func computeHunks(oldLines: [String], newLines: [String]) -> [DiffHunk] {
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var hunks: [DiffHunk] = []
        var hunkLines: [DiffLine] = []

        var o = 0, n = 0, lo = 0, ln = 0
        var hunkOldStart = 0, hunkNewStart = 0
        var inHunk = false

        var i = 0, j = 0
        let lcsLines = lcs

        while o < oldLines.count || n < newLines.count {
            if i < lcsLines.count,
               o < oldLines.count && n < newLines.count &&
               oldLines[o] == lcsLines[i] && newLines[n] == lcsLines[i] {
                // Context line
                if !hunkLines.isEmpty {
                    hunkLines.append(DiffLine(type: .context, content: oldLines[o]))
                }
                o += 1; n += 1; i += 1
            } else if o < oldLines.count && (i >= lcsLines.count || oldLines[o] != lcsLines[i]) {
                // Removed
                if !inHunk { hunkOldStart = o + 1; hunkNewStart = n + 1; inHunk = true }
                hunkLines.append(DiffLine(type: .removed, content: oldLines[o]))
                o += 1; lo += 1
            } else {
                // Added
                if !inHunk { hunkOldStart = o + 1; hunkNewStart = n + 1; inHunk = true }
                hunkLines.append(DiffLine(type: .added, content: newLines[n]))
                n += 1; ln += 1
            }
        }

        if !hunkLines.isEmpty {
            hunks.append(DiffHunk(
                oldStart: hunkOldStart, oldCount: lo,
                newStart: hunkNewStart, newCount: ln,
                lines: hunkLines
            ))
        }

        return hunks
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        // Simplified — for large files use patience algorithm
        guard a.count < 500 && b.count < 500 else { return [] }

        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }

        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                result.append(a[i-1])
                i -= 1; j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }
}
