import SwiftUI
import AppKit

@MainActor
extension SQLEditorView.Coordinator {
    func queryRange(containing characterIndex: Int, in text: String) -> NSRange? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let clampedIndex = min(max(characterIndex, 0), nsText.length)
        let beforeRange = NSRange(location: 0, length: clampedIndex)
        let beforeSeparator = nsText.range(of: "\n\n", options: .backwards, range: beforeRange)
        var start = beforeSeparator.location == NSNotFound
            ? 0
            : beforeSeparator.location + beforeSeparator.length

        let afterRange = NSRange(location: clampedIndex, length: nsText.length - clampedIndex)
        let afterSeparator = nsText.range(of: "\n\n", options: [], range: afterRange)
        var end = afterSeparator.location == NSNotFound
            ? nsText.length
            : afterSeparator.location

        while start < end, isWhitespace(nsText.character(at: start)) {
            start += 1
        }
        while end > start, isWhitespace(nsText.character(at: end - 1)) {
            end -= 1
        }

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    func queryBoxRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        guard let textRect = queryTextRect(for: range, in: textView) else {
            return nil
        }
        return textRect.insetBy(dx: -8, dy: -5)
    }

    func actionRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        if range.length > 0 {
            return queryBoxRect(for: range, in: textView)
        }

        return insertionAnchorRect(at: range.location, in: textView)
    }

    func actionFirstLineRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        if range.length > 0 {
            return queryFirstLineRect(for: range, in: textView)
        }

        return insertionAnchorRect(at: range.location, in: textView)
    }

    func emptyLineRect(at point: NSPoint, in textView: NSTextView) -> (location: Int, rect: NSRect)? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let font = textView.font else {
            return nil
        }

        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        guard containerPoint.y >= 0 else { return nil }

        if text.length == 0 {
            let rect = insertionLineRect(at: 0, in: textView) ?? NSRect(
                x: origin.x,
                y: origin.y,
                width: max(textView.visibleRect.width - origin.x - 12, 2),
                height: lineHeight
            )
            return textView.visibleRect.contains(point) ? (0, rect) : nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let extraLineRect = layoutManager.extraLineFragmentRect
        if !extraLineRect.isEmpty,
           containerPoint.y >= extraLineRect.minY - 4,
           containerPoint.y <= extraLineRect.maxY + 4 {
            return (text.length, emptyLineRect(for: extraLineRect, origin: origin, in: textView))
        }

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard containerPoint.y >= lineRect.minY - 4,
              containerPoint.y <= lineRect.maxY + 4 else {
            return nil
        }

        let characterIndex = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let lineRange = text.lineRange(for: NSRange(location: min(characterIndex, text.length), length: 0))
        let visibleRange = rangeByTrimmingTrailingWhitespaceAndNewlines(lineRange, in: text)
        guard visibleRange.length == 0 else { return nil }

        return (lineRange.location, emptyLineRect(for: lineRect, origin: origin, in: textView))
    }

    func validRange(_ range: NSRange?, in text: String) -> NSRange? {
        guard let range,
              range.length > 0,
              range.location >= 0,
              range.location + range.length <= (text as NSString).length else {
            return nil
        }
        return range
    }

    func validActionRange(_ range: NSRange?, in text: String) -> NSRange? {
        guard let range,
              range.length >= 0,
              range.location >= 0,
              range.location + range.length <= (text as NSString).length else {
            return nil
        }
        return range
    }

    private func queryFirstLineRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        guard let validRange = validRange(range, in: textView.string),
              let layoutManager = textView.layoutManager,
              let font = textView.font else {
            return nil
        }

        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let lineRange = text.lineRange(for: NSRange(location: validRange.location, length: 0))
        let segmentRange = NSIntersectionRange(lineRange, validRange)
        let visibleRange = rangeByTrimmingTrailingWhitespaceAndNewlines(segmentRange, in: text)
        let layoutLocation = min(max(segmentRange.location, 0), max(text.length - 1, 0))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: layoutLocation)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let prefixRange = NSRange(
            location: lineRange.location,
            length: max(visibleRange.location - lineRange.location, 0)
        )
        let x = origin.x + textWidth(for: prefixRange, in: text, font: font)
        let width = max(textWidth(for: visibleRange, in: text, font: font), 2)
        return NSRect(
            x: x,
            y: origin.y + lineRect.minY,
            width: width,
            height: lineRect.height
        )
    }

    private func insertionLineRect(at location: Int, in textView: NSTextView) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let font = textView.font else {
            return nil
        }

        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
        guard text.length > 0 else {
            return NSRect(
                x: origin.x,
                y: origin.y,
                width: max(textView.visibleRect.maxX - origin.x - 12, 2),
                height: lineHeight
            )
        }

        layoutManager.ensureLayout(for: textContainer)
        let clampedLocation = min(max(location, 0), text.length)
        if clampedLocation == text.length,
           text.character(at: text.length - 1) == 10 {
            let extraLineRect = layoutManager.extraLineFragmentRect
            if !extraLineRect.isEmpty {
                return emptyLineRect(for: extraLineRect, origin: origin, in: textView)
            }
        }

        let layoutLocation = min(max(clampedLocation, 0), max(text.length - 1, 0))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: layoutLocation)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return emptyLineRect(for: lineRect, origin: origin, in: textView)
    }

    private func insertionAnchorRect(at location: Int, in textView: NSTextView) -> NSRect? {
        guard var lineRect = insertionLineRect(at: location, in: textView) else {
            return nil
        }

        lineRect.size.width = 2
        return lineRect
    }

    private func emptyLineRect(for lineRect: NSRect, origin: NSPoint, in textView: NSTextView) -> NSRect {
        NSRect(
            x: origin.x,
            y: origin.y + lineRect.minY,
            width: max(textView.visibleRect.maxX - origin.x - 12, 2),
            height: lineRect.height
        )
    }

    private func queryTextRect(for range: NSRange, in textView: NSTextView) -> NSRect? {
        guard let validRange = validRange(range, in: textView.string),
              let layoutManager = textView.layoutManager,
              let font = textView.font else {
            return nil
        }

        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        let validEnd = NSMaxRange(validRange)
        var result = NSRect.null
        var cursor = validRange.location

        while cursor < validEnd {
            let lineRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            let segmentRange = NSIntersectionRange(lineRange, validRange)
            let visibleRange = rangeByTrimmingTrailingWhitespaceAndNewlines(segmentRange, in: text)

            let layoutLocation = min(max(segmentRange.location, 0), max(text.length - 1, 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: layoutLocation)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            let prefixRange = NSRange(
                location: lineRange.location,
                length: max(visibleRange.location - lineRange.location, 0)
            )
            let x = origin.x + textWidth(for: prefixRange, in: text, font: font)
            let width = max(textWidth(for: visibleRange, in: text, font: font), 2)
            let segmentRect = NSRect(
                x: x,
                y: origin.y + lineRect.minY,
                width: width,
                height: lineRect.height
            )
            result = result.isNull ? segmentRect : result.union(segmentRect)

            let next = NSMaxRange(lineRange)
            cursor = next > cursor ? next : cursor + 1
        }

        guard !result.isNull else { return nil }
        return result
    }

    private func rangeByTrimmingTrailingWhitespaceAndNewlines(_ range: NSRange, in text: NSString) -> NSRange {
        var length = range.length
        while length > 0, isWhitespace(text.character(at: range.location + length - 1)) {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }

    private func textWidth(for range: NSRange, in text: NSString, font: NSFont) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let value = text.substring(with: range).replacingOccurrences(of: "\t", with: "    ")
        return ceil((value as NSString).size(withAttributes: [.font: font]).width)
    }

    private func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(UInt32(character)) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
