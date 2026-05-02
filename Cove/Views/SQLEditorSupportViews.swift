import SwiftUI
import AppKit

final class QueryBoxView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension NSView {
    func firstEditableTextInput() -> NSResponder? {
        if let textView = self as? NSTextView, textView.isEditable {
            return textView
        }

        if let textField = self as? NSTextField, textField.isEditable, textField.isEnabled {
            return textField
        }

        for subview in subviews {
            if let responder = subview.firstEditableTextInput() {
                return responder
            }
        }

        return nil
    }
}

final class HoverTextView: NSTextView {
    var onHoverMoved: ((NSEvent) -> Void)?
    var onHoverExited: ((NSEvent) -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        window?.acceptsMouseMovedEvents = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverMoved?(event)
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverMoved?(event)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverExited?(event)
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
        super.mouseDown(with: event)
    }
}

final class AgentModeButtonHostingView: NSHostingView<AnyView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }
}

struct AgentModeActionButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("agent mode", systemImage: "wand.and.sparkles")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .help("Agent Mode")
    }
}
