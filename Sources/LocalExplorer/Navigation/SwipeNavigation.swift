import AppKit
import SwiftUI

/// Two-finger horizontal trackpad swipe over the wrapped area → back / forward, like
/// Safari and Finder. Fingers moving right go back; fingers moving left go forward.
extension View {
    func swipeNavigation(onBack: @escaping () -> Void, onForward: @escaping () -> Void) -> some View {
        background(SwipeNavigationMonitor(onBack: onBack, onForward: onForward))
    }
}

private struct SwipeNavigationMonitor: NSViewRepresentable {
    let onBack: () -> Void
    let onForward: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onBack = onBack
        view.onForward = onForward
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stopMonitoring() }

    final class MonitorView: NSView {
        var onBack: () -> Void = {}
        var onForward: () -> Void = {}

        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var triggered = false

        /// Horizontal travel (in points) before a swipe counts.
        private let threshold: CGFloat = 80

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        // Never intercept clicks meant for the content above.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func handle(_ event: NSEvent) {
            guard let window, event.window === window, event.hasPreciseScrollingDeltas else { return }
            // Ignore the inertia tail so one swipe fires once.
            guard event.momentumPhase.isEmpty else { return }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulatedX = 0
                accumulatedY = 0
                triggered = false
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulatedX = 0
                accumulatedY = 0
                triggered = false
                return
            }
            guard !triggered else { return }
            guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }

            accumulatedX += event.scrollingDeltaX
            accumulatedY += event.scrollingDeltaY
            // Mostly-vertical scrolling must never navigate.
            guard abs(accumulatedX) > threshold, abs(accumulatedX) > abs(accumulatedY) * 2 else { return }

            triggered = true
            // Deltas follow the content, so undo "natural scrolling" to get finger direction.
            let fingersMovedRight = (accumulatedX > 0) == event.isDirectionInvertedFromDevice
            if fingersMovedRight { onBack() } else { onForward() }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
