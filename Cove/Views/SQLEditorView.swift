import SwiftUI
import AppKit

struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var runnableRange: NSRange
    var keywords: Set<String> = []
    var completionSchema: CompletionSchema?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        textView.insertionPointColor = .labelColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let barView = NSView()
        barView.wantsLayer = true
        barView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        barView.layer?.cornerRadius = 1.5
        textView.addSubview(barView)
        context.coordinator.barView = barView

        textView.delegate = context.coordinator
        scrollView.documentView = textView
        context.coordinator.textView = textView

        if !text.isEmpty {
            textView.string = text
            highlightText(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            highlightText(textView)
            textView.selectedRanges = selectedRanges
        }
        context.coordinator.updateBar(range: runnableRange)
        context.coordinator.completionSchema = completionSchema
    }

    private func highlightText(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        storage.addAttribute(.font, value: font, range: fullRange)
        for token in SQLHighlighter.tokenize(textView.string, keywords: keywords) {
            storage.addAttribute(.foregroundColor, value: SQLHighlighter.colorFor(token.kind), range: token.range)
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: SQLEditorView
        weak var textView: NSTextView?
        var barView: NSView?
        var completionSchema: CompletionSchema?
        private let popup = CompletionPopup()
        private var completionWork: DispatchWorkItem?
        private var wordRange = NSRange(location: 0, length: 0)

        init(_ parent: SQLEditorView) {
            self.parent = parent
            super.init()
            popup.onAccept = { [weak self] item in
                self?.insertCompletion(item)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            parent.highlightText(textView)
            scheduleCompletion()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if popup.isVisible {
                switch commandSelector {
                case #selector(NSResponder.moveUp(_:)):
                    return popup.moveUp()
                case #selector(NSResponder.moveDown(_:)):
                    return popup.moveDown()
                case #selector(NSResponder.insertTab(_:)),
                     #selector(NSResponder.insertNewline(_:)):
                    if let item = popup.selectedItem {
                        insertCompletion(item)
                        return true
                    }
                    return false
                case #selector(NSResponder.cancelOperation(_:)):
                    popup.hide()
                    return true
                default:
                    break
                }
            }

            // Manual trigger via Escape when popup not visible
            if commandSelector == #selector(NSResponder.complete(_:)) {
                completionWork?.cancel()
                updateCompletions()
                return true
            }

            return false
        }

        // MARK: - Completion logic

        private func scheduleCompletion() {
            completionWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.updateCompletions()
            }
            completionWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }

        private func updateCompletions() {
            guard let textView, let schema = completionSchema else {
                popup.hide()
                return
            }

            let cursor = textView.selectedRange().location
            let text = textView.string
            let items = CompletionEngine.complete(
                text: text,
                cursor: cursor,
                schema: schema,
                keywords: parent.keywords
            )

            guard !items.isEmpty else {
                popup.hide()
                return
            }

            // Compute word range for replacement
            let chars = Array(text.utf16)
            var ws = cursor
            while ws > 0 && CompletionEngine.isIdent(chars[ws - 1]) { ws -= 1 }
            wordRange = NSRange(location: ws, length: cursor - ws)

            // Position popup at cursor
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                popup.hide()
                return
            }

            let glyphCount = layoutManager.numberOfGlyphs
            let glyphIndex = glyphCount > 0
                ? layoutManager.glyphIndexForCharacter(at: min(cursor, text.utf16.count - 1))
                : 0
            let safeGlyph = min(glyphIndex, max(glyphCount - 1, 0))

            let lineRect = glyphCount > 0
                ? layoutManager.lineFragmentRect(forGlyphAt: safeGlyph, effectiveRange: nil)
                : .zero
            let location = glyphCount > 0
                ? layoutManager.location(forGlyphAt: safeGlyph)
                : .zero

            let origin = textView.textContainerOrigin
            let pointInView = NSPoint(
                x: lineRect.minX + location.x + origin.x,
                y: lineRect.maxY + origin.y
            )

            let pointInWindow = textView.convert(pointInView, to: nil)
            guard let window = textView.window else {
                popup.hide()
                return
            }
            let screenPoint = window.convertPoint(toScreen: pointInWindow)

            popup.show(items: items, at: screenPoint, textView: textView)
        }

        private func insertCompletion(_ item: CompletionItem) {
            guard let textView else { return }
            popup.hide()

            if textView.shouldChangeText(in: wordRange, replacementString: item.insertText) {
                textView.replaceCharacters(in: wordRange, with: item.insertText)
                let newCursor = wordRange.location + item.insertText.utf16.count
                textView.setSelectedRange(NSRange(location: newCursor, length: 0))
                textView.didChangeText()
            }
        }

        // MARK: - Runnable range bar

        func updateBar(range: NSRange) {
            guard let textView, let barView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            guard range.length > 0, range.location + range.length <= (textView.string as NSString).length else {
                barView.isHidden = true
                return
            }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let blockRect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )

            let origin = textView.textContainerOrigin
            barView.frame = NSRect(
                x: 4,
                y: blockRect.minY + origin.y,
                width: 3,
                height: blockRect.height
            )
            barView.isHidden = false
        }
    }
}
