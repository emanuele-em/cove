import Foundation

@Observable
final class QueryState {
    var text = ""
    var selectedRange: NSRange = NSRange(location: 0, length: 0)
    var executing = false
    var error = ""
    var status = ""
    var result: QueryResult?

    var runnableRange: NSRange {
        if selectedRange.length > 0 {
            return selectedRange
        }

        let cursor = selectedRange.location
        let fullText = text
        guard !fullText.isEmpty else { return NSRange(location: 0, length: 0) }

        var blockStart = fullText.startIndex
        var blockEnd = fullText.endIndex

        let cursorIdx = fullText.index(fullText.startIndex, offsetBy: min(cursor, fullText.count))

        let before = fullText[fullText.startIndex..<cursorIdx]
        if let range = before.range(of: "\n\n", options: .backwards) {
            blockStart = range.upperBound
        }

        let after = fullText[cursorIdx..<fullText.endIndex]
        if let range = after.range(of: "\n\n") {
            blockEnd = range.lowerBound
        }

        let start = fullText.distance(from: fullText.startIndex, to: blockStart)
        let length = fullText.distance(from: blockStart, to: blockEnd)
        return NSRange(location: start, length: length)
    }

    var runnableSQL: String {
        let range = runnableRange
        guard range.length > 0 else { return "" }
        return (text as NSString).substring(with: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
