import SwiftUI
import AppKit

final class ScrubSlider: NSSlider {
    var begin: (() -> Void)?
    var finish: (() -> Void)?
    private(set) var dragging = false
    override var acceptsFirstResponder: Bool { isEnabled }
    override func becomeFirstResponder() -> Bool {
        focusRingType = .default
        return super.becomeFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        focusRingType = .default
        switch event.keyCode {
        case 123, 125: doubleValue=max(minValue,doubleValue-5)
        case 124, 126: doubleValue=min(maxValue,doubleValue+5)
        case 115: doubleValue=minValue
        case 119: doubleValue=maxValue
        default: super.keyDown(with:event); return
        }
        if let action {sendAction(action,to:target)}
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        // AppKit can cache the focus mask at the old thumb position while tracking.
        // Mouse scrubbing needs no keyboard focus ring; keyboard navigation restores it.
        focusRingType = .none
        dragging = true; begin?()
        super.mouseDown(with: event)
        dragging = false; finish?()
    }
}
struct TimelineSlider: NSViewRepresentable {
    let value: Double
    let duration: Double
    let enabled: Bool
    let begin: () -> Void
    let update: (Double) -> Void
    let finish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ScrubSlider {
        let slider=ScrubSlider()
        slider.minValue=0; slider.isContinuous=true; slider.controlSize = .small
        slider.target=context.coordinator; slider.action=#selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel("Playback position")
        slider.toolTip="Click or drag to seek. Space plays or pauses; arrow keys move five seconds; Home and End move to the beginning and end."
        return slider
    }
    func updateNSView(_ slider: ScrubSlider, context: Context) {
        context.coordinator.parent=self
        slider.begin=begin; slider.finish=finish
        slider.maxValue=max(duration,1); slider.doubleValue=min(max(value,0),slider.maxValue)
        slider.isEnabled=enabled
        slider.setAccessibilityValueDescription("\(timeLabel(value)) of \(timeLabel(duration))")
    }
    final class Coordinator: NSObject {
        var parent: TimelineSlider
        init(_ parent: TimelineSlider) { self.parent=parent }
        @objc func changed(_ slider: ScrubSlider) {
            if !slider.dragging {parent.begin()}
            parent.update(slider.doubleValue)
            if !slider.dragging {parent.finish()}
        }
    }
}
