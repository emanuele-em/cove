import SwiftUI
import AppKit

struct SQLEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    var runnableRange: NSRange
    var keywords: Set<String> = []
    var completionSchema: CompletionSchema?
    var isEditable = true
    @Binding var agentInputVisible: Bool
    @Binding var agentTargetRange: NSRange?
    var onAgentMode: (NSRange) -> Void
    var onAgentCancel: () -> Void
    var agentComposer: () -> AnyView

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let textView = HoverTextView()
        textView.isEditable = isEditable
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

        let queryBoxView = QueryBoxView()
        queryBoxView.wantsLayer = true
        queryBoxView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        queryBoxView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor
        queryBoxView.layer?.borderWidth = 1
        queryBoxView.layer?.cornerRadius = 6
        queryBoxView.isHidden = true
        textView.addSubview(queryBoxView)
        context.coordinator.queryBoxView = queryBoxView

        textView.delegate = context.coordinator
        scrollView.documentView = textView
        context.coordinator.textView = textView

        let coordinator = context.coordinator
        textView.onHoverMoved = { [weak coordinator] event in
            coordinator?.handleHoverMoved(event)
        }
        textView.onHoverExited = { [weak coordinator] event in
            coordinator?.handleHoverExited(event)
        }
        textView.onMouseDown = { [weak coordinator] event in
            coordinator?.handleMouseDown(event)
        }

        let actionButton = AgentModeButtonHostingView(rootView: AnyView(AgentModeActionButton { [weak coordinator] in
            coordinator?.showAgentMode()
        }))
        actionButton.isHidden = true
        textView.addSubview(actionButton)
        context.coordinator.actionButton = actionButton

        let agentComposerView = NSHostingView(rootView: agentComposer())
        agentComposerView.isHidden = true
        textView.addSubview(agentComposerView)
        context.coordinator.agentComposerView = agentComposerView

        if !text.isEmpty {
            textView.string = text
            highlightText(textView)
            textView.setSelectedRange(clampedRange(selectedRange, in: text))
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.agentComposerView?.rootView = agentComposer()
        if textView.string != text {
            textView.string = text
            highlightText(textView)
            textView.setSelectedRange(clampedRange(selectedRange, in: text))
        }
        textView.isEditable = isEditable
        context.coordinator.updateQueryBox(range: runnableRange)
        context.coordinator.completionSchema = completionSchema
        context.coordinator.updateInlineAgentViews()
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

    private func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let textLength = (text as NSString).length
        let location = min(max(range.location, 0), textLength)
        let length = min(max(range.length, 0), textLength - location)
        return NSRange(location: location, length: length)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditorView
        weak var textView: NSTextView?
        var queryBoxView: QueryBoxView?
        var actionButton: NSHostingView<AnyView>?
        var agentComposerView: NSHostingView<AnyView>?
        var completionSchema: CompletionSchema?
        var hoveredQueryRange: NSRange?
        var queryBoxRange: NSRange?
        nonisolated(unsafe) var outsideMouseDownMonitor: Any?
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

        deinit {
            if let outsideMouseDownMonitor {
                NSEvent.removeMonitor(outsideMouseDownMonitor)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.selectedRange = textView.selectedRange()
            parent.highlightText(textView)
            updateQueryBox(range: currentRunnableRange(in: textView))
            scheduleCompletion()
            updateInlineAgentViews()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selectedRange = textView.selectedRange()
            hideAgentComposerIfSelectionMovedAway(in: textView)
            updateQueryBox(range: currentRunnableRange(in: textView))
            updateInlineAgentViews()
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

            if commandSelector == #selector(NSResponder.complete(_:)) {
                completionWork?.cancel()
                updateCompletions()
                return true
            }

            return false
        }

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

            let chars = Array(text.utf16)
            var ws = cursor
            while ws > 0 && CompletionEngine.isIdent(chars[ws - 1]) { ws -= 1 }
            wordRange = NSRange(location: ws, length: cursor - ws)

            guard let layoutManager = textView.layoutManager else {
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
    }
}
