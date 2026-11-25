#if os(macOS)
import AppKit
import SwiftUI

/// Adjusts wheel input for the enclosing feed before AppKit applies its normal scroll physics.
struct MusicHomeScrollSpeed: NSViewRepresentable {
    func makeNSView(context: Context) -> ViewportMarker { ViewportMarker() }

    func updateNSView(_ view: ViewportMarker, context: Context) {}

    static func dismantleNSView(_ view: ViewportMarker, coordinator: ()) {
        view.stopMonitoring()
    }

    final class ViewportMarker: NSView {
        private enum Gesture {
            case outside, pending, vertical, horizontal
        }

        private var monitor: Any?
        private var gesture = Gesture.outside
        private var gain = MusicVerticalScrollGain()

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.adjust(event) ?? event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            gesture = .outside
            gain = MusicVerticalScrollGain()
        }

        private func adjust(_ event: NSEvent) -> NSEvent {
            guard let window, window.isKeyWindow, event.window === window,
                  let scrollView = enclosingScrollView, !scrollView.isHiddenOrHasHiddenAncestor else {
                gesture = .outside
                return event
            }
            if event.phase.contains(.mayBegin) || event.phase.contains(.cancelled)
                || event.momentumPhase.contains(.ended) {
                gesture = .outside
                return event
            }
            guard event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty else {
                gesture = .outside
                return event
            }

            let vertical = abs(event.scrollingDeltaY)
            let horizontal = abs(event.scrollingDeltaX)
            if event.phase.isEmpty, event.momentumPhase.isEmpty {
                guard vertical > horizontal, ownsEvent(at: event.locationInWindow, in: scrollView) else { return event }
                return gain.applying(to: event)
            }

            if event.phase.contains(.began) {
                gesture = ownsEvent(at: event.locationInWindow, in: scrollView) ? .pending : .outside
                gain = MusicVerticalScrollGain()
            }
            if gesture == .pending, vertical > 0 || horizontal > 0 {
                gesture = vertical > horizontal ? .vertical : .horizontal
            }
            // AppKit keeps the gesture on its initial view even when the pointer moves during momentum.
            guard gesture == .vertical, vertical > 0 else { return event }
            return gain.applying(to: event)
        }

        func ownsEvent(at location: NSPoint, in scrollView: NSScrollView) -> Bool {
            let clip = scrollView.contentView
            guard clip.bounds.contains(clip.convert(location, from: nil)),
                  let content = window?.contentView else { return false }
            let point = content.superview?.convert(location, from: nil) ?? location
            guard let hit = content.hitTest(point) else { return false }
            return ((hit as? NSScrollView) ?? hit.enclosingScrollView) === scrollView
        }
    }
}

struct MusicVerticalScrollGain {
    static let multiplier = 1.35
    private var pointRemainder = 0.0

    mutating func applying(to event: NSEvent) -> NSEvent {
        guard event.type == .scrollWheel, let core = event.cgEvent else { return event }
        let precise = event.hasPreciseScrollingDeltas
        let oldDelta = event.scrollingDeltaY
        let multiplier = Self.multiplier
        let points = Double(core.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let requested = points * multiplier + (precise ? pointRemainder : 0)
        let rounded = requested.rounded()
        if precise { pointRemainder = requested - rounded }

        let lines = core.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let fixed = core.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        core.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Self.integerDelta(Double(lines) * multiplier))
        core.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed * multiplier)
        core.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Self.integerDelta(rounded))

        // Retain the original NSEvent and its window whenever it exposes the edited CGEvent.
        let expected = precise ? rounded : fixed * multiplier
        if event.scrollingDeltaY != oldDelta || abs(expected - oldDelta) < 0.0001 { return event }
        guard let updated = NSEvent(cgEvent: core), updated.windowNumber == event.windowNumber,
              updated.locationInWindow == event.locationInWindow else { return event }
        return updated
    }

    private static func integerDelta(_ value: Double) -> Int64 {
        Int64(min(Double(Int32.max), max(Double(Int32.min), value.rounded())))
    }
}
#endif
