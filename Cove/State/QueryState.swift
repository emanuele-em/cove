import Foundation

@Observable
final class QueryState {
    var text = ""
    var selectedRange: NSRange = NSRange(location: 0, length: 0)
    var executing = false
    var error = ""
    var status = ""
    var result: QueryResult?
    var agentPrompt = ""
    var selectedAgent: QueryAgentKind? = .claude
    var agentInputVisible = false
    var agentTargetRange: NSRange?
    var agentExecuting = false
    var agentError = ""
    var agentStatus = ""
    var agentFocusGeneration = 0

    var runnableRange: NSRange {
        let nsText = text as NSString
        if selectedRange.length > 0 {
            return clampedRange(selectedRange, textLength: nsText.length)
        }

        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }

        let cursor = clampedCursorLocation
        let beforeRange = NSRange(location: 0, length: cursor)
        let beforeSeparator = nsText.range(of: "\n\n", options: .backwards, range: beforeRange)
        let blockStart = beforeSeparator.location == NSNotFound
            ? 0
            : beforeSeparator.location + beforeSeparator.length

        let afterRange = NSRange(location: cursor, length: nsText.length - cursor)
        let afterSeparator = nsText.range(of: "\n\n", options: [], range: afterRange)
        let blockEnd = afterSeparator.location == NSNotFound
            ? nsText.length
            : afterSeparator.location
        return NSRange(location: blockStart, length: max(blockEnd - blockStart, 0))
    }

    var runnableSQL: String {
        let range = runnableRange
        return sql(in: range)
    }

    var agentModeTargetRangeAtCursor: NSRange {
        if let blankLineRange = blankLineCursorRange {
            return blankLineRange
        }

        let candidateRange = runnableRange
        guard sql(in: candidateRange).isEmpty else { return candidateRange }
        return NSRange(location: clampedCursorLocation, length: 0)
    }

    var validAgentTargetRange: NSRange? {
        guard let range = agentTargetRange,
              range.length >= 0,
              range.location >= 0,
              range.location + range.length <= (text as NSString).length else {
            return nil
        }
        return range
    }

    private var clampedCursorLocation: Int {
        min(max(selectedRange.location, 0), (text as NSString).length)
    }

    private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(range.location, 0), textLength)
        let length = min(max(range.length, 0), textLength - location)
        return NSRange(location: location, length: length)
    }

    private var blankLineCursorRange: NSRange? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let cursor = clampedCursorLocation
        let previousNewlineRange = nsText.range(
            of: "\n",
            options: .backwards,
            range: NSRange(location: 0, length: cursor)
        )
        let lineStart = previousNewlineRange.location == NSNotFound
            ? 0
            : previousNewlineRange.location + previousNewlineRange.length
        let nextNewlineSearchRange = NSRange(location: lineStart, length: nsText.length - lineStart)
        let nextNewlineRange = nsText.range(of: "\n", options: [], range: nextNewlineSearchRange)
        let lineEnd = nextNewlineRange.location == NSNotFound
            ? nsText.length
            : nextNewlineRange.location
        let lineRange = NSRange(location: lineStart, length: max(lineEnd - lineStart, 0))
        let line = nsText.substring(with: lineRange)
        guard line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return NSRange(location: cursor, length: 0)
    }

    func sql(in range: NSRange) -> String {
        guard range.length > 0,
              range.location >= 0,
              range.location + range.length <= (text as NSString).length else {
            return ""
        }
        return (text as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func showAgentMode(for range: NSRange) {
        guard range.length >= 0,
              range.location >= 0,
              range.location + range.length <= (text as NSString).length else {
            return
        }
        agentTargetRange = range
        agentInputVisible = true
        agentFocusGeneration += 1
        agentError = ""
        agentStatus = ""
    }

    func hideAgentMode() {
        agentInputVisible = false
        agentTargetRange = nil
    }

    func replaceRunnableSQL(with sql: String) {
        replaceSQL(in: runnableRange, with: sql)
    }

    func appendSQL(_ sql: String) {
        let replacement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = replacement
        } else {
            text = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + replacement
        }
        selectedRange = NSRange(location: text.utf16.count, length: 0)
    }

    @discardableResult
    func insertSQL(_ sql: String, at location: Int) -> NSRange? {
        let replacement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return nil }

        let nsText = text as NSString
        let insertionLocation = min(max(location, 0), nsText.length)
        let insertion = insertionText(for: replacement, at: insertionLocation, in: nsText)
        text = nsText.replacingCharacters(
            in: NSRange(location: insertionLocation, length: 0),
            with: insertion.text
        )
        let insertedRange = NSRange(
            location: insertionLocation + insertion.sqlOffset,
            length: replacement.utf16.count
        )
        selectedRange = NSRange(location: insertedRange.location + insertedRange.length, length: 0)
        return insertedRange
    }

    func replaceSQL(in range: NSRange, with sql: String) {
        let replacement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        if range.length > 0,
           range.location >= 0,
           range.location + range.length <= (text as NSString).length {
            text = (text as NSString).replacingCharacters(in: range, with: replacement)
            selectedRange = NSRange(location: range.location + replacement.utf16.count, length: 0)
        } else {
            text = replacement
            selectedRange = NSRange(location: replacement.utf16.count, length: 0)
        }
    }

    private func insertionText(
        for replacement: String,
        at location: Int,
        in nsText: NSString
    ) -> (text: String, sqlOffset: Int) {
        let newline = "\n".utf16.first!
        let hasNewlineBefore = location > 0 && nsText.character(at: location - 1) == newline
        let hasNewlineAfter = location < nsText.length && nsText.character(at: location) == newline
        let hasContentBefore = !nsText.substring(to: location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let hasContentAfter = !nsText.substring(from: location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        var text = replacement
        var sqlOffset = 0
        if hasNewlineBefore && hasContentBefore {
            text = "\n" + text
            sqlOffset = 1
        }
        if hasNewlineAfter && hasContentAfter {
            text += "\n"
        }
        return (text, sqlOffset)
    }
}
