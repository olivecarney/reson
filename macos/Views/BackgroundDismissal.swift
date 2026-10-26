import AppKit
import SwiftUI

/// Observes clicks before AppKit's modal-sheet dispatch swallows parent-window events.
struct BackgroundDismissal: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> BackgroundDismissView {
        let view = BackgroundDismissView()
        view.dismiss = dismiss
        return view
    }

    func updateNSView(_ view: BackgroundDismissView, context: Context) {
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: BackgroundDismissView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class BackgroundDismissView: NSView {
    var dismiss: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    /// Consume the dismissal click so it cannot also activate a library control.
    func handle(_ event: NSEvent) -> Bool {
        guard event.type == .leftMouseDown,
              let window, window.isVisible, window.attachedSheet == nil,
              let background = window.sheetParent ?? NSApp.orderedWindows.first(where: {
                  $0 !== window && $0.isVisible && $0.canBecomeMain && $0.sheetParent == nil
              }),
              background !== window,
              background.attachedSheet == nil || background.attachedSheet === window,
              let eventWindow = event.window else { return false }
        if eventWindow === background {
            dismiss?()
            return true
        }
        // Some modal dispatch paths address an outside click to the sheet itself.
        if eventWindow === window, !NSRect(origin: .zero, size: window.frame.size).contains(event.locationInWindow),
           background.frame.contains(window.convertPoint(toScreen: event.locationInWindow)) {
            dismiss?()
            return true
        }
        return false
    }
}
