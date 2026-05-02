import SwiftUI
import AppKit

@MainActor
extension SQLEditorView.Coordinator {
    func handleHoverMoved(_ event: NSEvent) {
        guard let textView else { return }
        let point = textView.convert(event.locationInWindow, from: nil)
        hoveredQueryRange = boxedQueryRange(at: point, in: textView)
            ?? emptyLineActionRange(at: point, in: textView)
        updateInlineAgentViews()
    }

    func handleHoverExited(_ event: NSEvent) {
        hoveredQueryRange = nil
        updateInlineAgentViews()
    }

    func handleMouseDown(_ event: NSEvent) {
        hideAgentComposer()
    }

    func showAgentMode() {
        guard let textView,
              let range = actionRange(in: textView) else { return }
        parent.onAgentMode(range)
        updateInlineAgentViews()
        focusAgentComposerInput()
    }

    func updateInlineAgentViews() {
        guard let textView else { return }

        if parent.agentInputVisible, let range = validActionRange(parent.agentTargetRange, in: textView.string) {
            actionButton?.isHidden = true
            positionAgentComposer(for: range, in: textView)
            installOutsideMouseDownMonitor()
        } else {
            removeOutsideMouseDownMonitor()
            agentComposerView?.isHidden = true
            positionActionButton(in: textView)
        }
    }

    func hideAgentComposerIfSelectionMovedAway(in textView: NSTextView) {
        guard parent.agentInputVisible,
              let targetRange = validActionRange(parent.agentTargetRange, in: textView.string) else {
            return
        }

        let selectionRange = textView.selectedRange()
        let selectedLocation = min(selectionRange.location, (textView.string as NSString).length)
        let selectedBlock = queryRange(containing: selectedLocation, in: textView.string)
        let targetBlock = queryRange(containing: targetRange.location, in: textView.string)
        if selectedBlock == targetBlock {
            return
        }

        hideAgentComposer()
    }

    func currentRunnableRange(in textView: NSTextView) -> NSRange? {
        let selectionRange = textView.selectedRange()
        if selectionRange.length > 0 {
            return validRange(selectionRange, in: textView.string)
        }

        return queryRange(containing: selectionRange.location, in: textView.string)
    }

    func updateQueryBox(range: NSRange?) {
        guard let textView, let queryBoxView else { return }

        guard let range = validRange(range, in: textView.string),
              let boxRect = queryBoxRect(for: range, in: textView) else {
            queryBoxRange = nil
            queryBoxView.isHidden = true
            return
        }

        queryBoxRange = range
        queryBoxView.frame = boxRect
        queryBoxView.isHidden = false
        refreshHoveredQueryRangeFromCurrentMouseLocation(in: textView)
    }

    private func installOutsideMouseDownMonitor() {
        guard outsideMouseDownMonitor == nil else { return }
        outsideMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handleOutsideMouseDown(event)
            return event
        }
    }

    private func removeOutsideMouseDownMonitor() {
        guard let outsideMouseDownMonitor else { return }
        NSEvent.removeMonitor(outsideMouseDownMonitor)
        self.outsideMouseDownMonitor = nil
    }

    private func handleOutsideMouseDown(_ event: NSEvent) {
        guard parent.agentInputVisible,
              let agentComposerView,
              !agentComposerView.isHidden,
              event.window === agentComposerView.window else {
            return
        }

        let point = agentComposerView.convert(event.locationInWindow, from: nil)
        guard !agentComposerView.bounds.contains(point) else { return }
        hideAgentComposer()
    }

    private func positionActionButton(in textView: NSTextView) {
        guard let actionButton,
              let range = actionRange(in: textView),
              !parent.agentInputVisible,
              parent.isEditable,
              let rect = actionRect(for: range, in: textView),
              let firstLineRect = actionFirstLineRect(for: range, in: textView) else {
            actionButton?.isHidden = true
            return
        }

        let visibleRect = textView.visibleRect
        let size = actionButton.fittingSize
        let buttonSize = NSSize(width: max(size.width + 10, 118), height: 26)
        let preferredY = firstLineRect.midY - buttonSize.height / 2
        let y = min(max(preferredY, visibleRect.minY + 8), visibleRect.maxY - buttonSize.height - 8)
        let topInset = textView.isFlipped
            ? max(y - rect.minY, 0)
            : max(rect.maxY - y - buttonSize.height, 0)
        let preferredX = range.length == 0
            ? rect.minX
            : rect.maxX - buttonSize.width - topInset
        let x = min(max(preferredX, visibleRect.minX + 12), visibleRect.maxX - buttonSize.width - 12)

        actionButton.frame = NSRect(origin: NSPoint(x: x, y: y), size: buttonSize)
        actionButton.isHidden = false
    }

    private func actionRange(in textView: NSTextView) -> NSRange? {
        if let hoveredQueryRange,
           validActionRange(hoveredQueryRange, in: textView.string) != nil {
            return hoveredQueryRange
        }

        return nil
    }

    private func boxedQueryRange(at point: NSPoint, in textView: NSTextView) -> NSRange? {
        guard let range = validRange(queryBoxRange, in: textView.string),
              let rect = queryBoxRect(for: range, in: textView),
              rect.contains(point) else {
            return nil
        }
        return range
    }

    private func emptyLineActionRange(at point: NSPoint, in textView: NSTextView) -> NSRange? {
        guard let rect = emptyLineRect(at: point, in: textView),
              caretIsOnEmptyLine(at: rect.location, in: textView) else {
            return nil
        }
        return NSRange(location: rect.location, length: 0)
    }

    private func refreshHoveredQueryRangeFromCurrentMouseLocation(in textView: NSTextView) {
        guard let window = textView.window else { return }
        let point = textView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hoveredQueryRange = boxedQueryRange(at: point, in: textView)
            ?? emptyLineActionRange(at: point, in: textView)
    }

    private func caretIsOnEmptyLine(at lineLocation: Int, in textView: NSTextView) -> Bool {
        let selectionRange = textView.selectedRange()
        guard selectionRange.length == 0 else { return false }

        let text = textView.string as NSString
        let caretLocation = min(max(selectionRange.location, 0), text.length)
        let lineLocation = min(max(lineLocation, 0), text.length)

        if text.length == 0 {
            return caretLocation == 0 && lineLocation == 0
        }

        if lineLocation == text.length {
            return caretLocation == text.length
        }

        let caretLineRange = text.lineRange(for: NSRange(location: caretLocation, length: 0))
        let hoveredLineRange = text.lineRange(for: NSRange(location: lineLocation, length: 0))
        return caretLineRange.location == hoveredLineRange.location
    }

    private func focusAgentComposerInput() {
        DispatchQueue.main.async { [weak self] in
            guard let agentComposerView = self?.agentComposerView,
                  !agentComposerView.isHidden,
                  let responder = agentComposerView.firstEditableTextInput() else {
                return
            }

            agentComposerView.window?.makeFirstResponder(responder)
        }
    }

    private func hideAgentComposer() {
        guard parent.agentInputVisible else { return }
        parent.onAgentCancel()
        agentComposerView?.isHidden = true
        updateInlineAgentViews()
    }

    private func positionAgentComposer(for range: NSRange, in textView: NSTextView) {
        guard let agentComposerView,
              let boxRect = actionRect(for: range, in: textView) else {
            agentComposerView?.isHidden = true
            return
        }

        let visibleRect = textView.visibleRect
        let horizontalInset: CGFloat = 12
        let gap: CGFloat = 14
        let maxAvailableWidth = max(240, visibleRect.width - horizontalInset * 2)
        let width = min(min(max(300, visibleRect.width * 0.36), 380), maxAvailableWidth)
        agentComposerView.frame.size = NSSize(width: width, height: 1)
        agentComposerView.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(agentComposerView.fittingSize.height)
        let height = min(max(fittingHeight, 78), 176)

        let minX = visibleRect.minX + horizontalInset
        let maxX = max(minX, visibleRect.maxX - width - horizontalInset)
        let rightSideX = boxRect.maxX + gap
        let hasSpaceOnRight = rightSideX + width <= visibleRect.maxX - horizontalInset
        let overlayX = boxRect.maxX - width - 8
        let x = hasSpaceOnRight ? rightSideX : min(max(overlayX, minX), maxX)

        let minY = visibleRect.minY + horizontalInset
        let maxY = max(minY, visibleRect.maxY - height - horizontalInset)
        let preferredY = textView.isFlipped ? boxRect.minY : boxRect.maxY - height
        let y = min(max(preferredY, minY), maxY)

        agentComposerView.frame = NSRect(x: x, y: y, width: width, height: height)
        agentComposerView.isHidden = false
    }
}
