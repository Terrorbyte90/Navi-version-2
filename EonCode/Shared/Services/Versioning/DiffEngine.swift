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
        let m = a.count, n = b.count

        // For very large files, use a simpler line-matching approach
        // to avoid O(m*n) memory/time explosion
        if m > 2000 || n > 2000 {
            return hashBasedLCS(a, b)
        }

        // Standard DP approach with space optimization for medium files
        // Use rolling two rows instead of full m x n matrix
        var prev = Array(repeating: 0, count: n + 1)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    curr[j] = prev[j-1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j-1])
                }
            }
            prev = curr
            curr = Array(repeating: 0, count: n + 1)
        }

        // Backtrack to find the LCS (need full DP for this)
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

    /// Hash-based LCS for very large files — finds common lines by hash matching
    private static func hashBasedLCS(_ a: [String], _ b: [String]) -> [String] {
        // Build a map of line -> positions in b
        var bPositions: [String: [Int]] = [:]
        for (j, line) in b.enumerated() {
            bPositions[line, default: []].append(j)
        }

        // Find matching lines preserving order (patience-like)
        var result: [String] = []
        var lastJ = -1
        for line in a {
            guard let positions = bPositions[line] else { continue }
            // Find the first position in b after lastJ
            if let nextJ = positions.first(where: { $0 > lastJ }) {
                result.append(line)
                lastJ = nextJ
            }
        }
        return result
    }
}
