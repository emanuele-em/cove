import SwiftUI
import AppKit

final class PromptNativeTextView: NSTextView {
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }
    var onCommandReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, !placeholder.isEmpty else { return }

        let origin = textContainerOrigin
        let rect = NSRect(
            x: origin.x,
            y: origin.y,
            width: max(bounds.width - origin.x, 0),
            height: bounds.height
        )
        placeholder.draw(
            in: rect,
            withAttributes: [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandReturn = modifiers.contains(.command)
            && (event.keyCode == 36 || event.keyCode == 76 || event.charactersIgnoringModifiers == "\r")
        let isEscape = event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}"
        if isEscape {
            onEscape?()
            return
        }

        guard isCommandReturn else {
            super.keyDown(with: event)
            return
        }

        onCommandReturn?()
    }
}

struct AgentPromptTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    @Binding var height: CGFloat
    var autoFocus: Bool
    var focusTrigger: Int
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> GrowingTextScrollView {
        let scrollView = GrowingTextScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = PromptNativeTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.placeholder = placeholder
        textView.onCommandReturn = { [weak coordinator = context.coordinator] in
            coordinator?.submit()
        }
        textView.onEscape = { [weak coordinator = context.coordinator] in
            coordinator?.cancel()
        }
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        context.coordinator.textView = textView
        scrollView.onFrameSizeChanged = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.updateHeight(for: scrollView)
        }

        context.coordinator.updateHeight(for: scrollView)
        context.coordinator.focusIfNeeded()
        return scrollView
    }

    func updateNSView(_ scrollView: GrowingTextScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        if let promptTextView = textView as? PromptNativeTextView {
            promptTextView.placeholder = placeholder
            promptTextView.onCommandReturn = { [weak coordinator = context.coordinator] in
                coordinator?.submit()
            }
            promptTextView.onEscape = { [weak coordinator = context.coordinator] in
                coordinator?.cancel()
            }
        }
        textView.isEditable = isEnabled
        textView.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        context.coordinator.updateHeight(for: scrollView)
        context.coordinator.focusIfNeeded()
    }

    final class GrowingTextScrollView: NSScrollView {
        var onFrameSizeChanged: (() -> Void)?

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            onFrameSizeChanged?()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentPromptTextView
        weak var textView: NSTextView?
        private var focusedGeneration: Int?

        init(_ parent: AgentPromptTextView) {
            self.parent = parent
        }

        func submit() {
            parent.onSubmit()
        }

        func cancel() {
            parent.onCancel()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let scrollView = textView.enclosingScrollView as? GrowingTextScrollView {
                updateHeight(for: scrollView)
            }
        }

        func updateHeight(for scrollView: GrowingTextScrollView) {
            guard let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let font = textView.font else {
                return
            }

            let width = max(scrollView.contentSize.width, 1)
            if abs(textView.frame.width - width) > 0.5 {
                textView.frame.size.width = width
            }
            textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)

            let lineHeight = ceil(layoutManager.defaultLineHeight(for: font))
            let insetHeight = textView.textContainerInset.height * 2
            let contentHeight = max(ceil(layoutManager.usedRect(for: textContainer).height), lineHeight) + insetHeight
            let minHeight = lineHeight + insetHeight
            let maxHeight = lineHeight * 5 + insetHeight
            let clampedHeight = min(max(contentHeight, minHeight), maxHeight)
            let documentHeight = max(contentHeight, clampedHeight)

            scrollView.hasVerticalScroller = contentHeight > maxHeight + 0.5
            textView.frame.size = NSSize(width: width, height: documentHeight)

            guard abs(parent.height - clampedHeight) > 0.5 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.height = clampedHeight
            }
        }

        func focusIfNeeded() {
            if !parent.autoFocus {
                focusedGeneration = nil
                return
            }

            guard focusedGeneration != parent.focusTrigger,
                  let textView,
                  textView.isEditable else {
                return
            }

            focusedGeneration = parent.focusTrigger
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
}
