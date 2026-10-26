import XCTest
import AppKit
@testable import Reson

@MainActor final class BackgroundDismissalTests: XCTestCase {
    func testMouseScrubbingHidesStaleFocusRingAndKeyboardRestoresFocusFeedback() throws {
        let slider = ScrubSlider(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        slider.minValue = 0; slider.maxValue = 120; slider.doubleValue = 30
        let window = NSWindow(contentRect: slider.frame, styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        window.contentView = slider
        var began = 0; var finished = 0
        slider.begin = { began += 1 }; slider.finish = { finished += 1 }
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 80, y: 15), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let release = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: click.locationInWindow, modifierFlags: [], timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        NSApp.postEvent(release, atStart: true)
        slider.mouseDown(with: click)
        XCTAssertEqual(slider.focusRingType, .none)
        XCTAssertEqual(began, 1); XCTAssertEqual(finished, 1)
        XCTAssertFalse(slider.dragging)
        let right = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        let position = slider.doubleValue
        slider.keyDown(with: right)
        XCTAssertEqual(slider.doubleValue, min(position + 5, 120))
        XCTAssertEqual(slider.focusRingType, .default)
    }

    func testSettingsBackgroundDismissalWaitsForChildFileDialog() throws {
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil); settings.orderFront(nil)
        defer { main.orderOut(nil); settings.orderOut(nil) }
        let view = BackgroundDismissView()
        settings.contentView = view
        var dismissals = 0
        view.dismiss = { dismissals += 1 }
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: main.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let dialog = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        settings.beginSheet(dialog)
        XCTAssertFalse(view.handle(click))
        XCTAssertEqual(dismissals, 0)
        settings.endSheet(dialog)
        XCTAssertTrue(view.handle(click))
        XCTAssertEqual(dismissals, 1)
        settings.orderOut(nil)
        XCTAssertFalse(view.handle(click))
        XCTAssertEqual(dismissals, 1)
        view.removeFromSuperview()
        XCTAssertFalse(view.handle(click))
        XCTAssertEqual(dismissals, 1)
    }

    func testBackgroundClickDismissesAndIsConsumedButPanelClicksPassThrough() throws {
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        main.beginSheet(panel)
        defer { main.endSheet(panel); main.orderOut(nil); panel.orderOut(nil) }
        let view = BackgroundDismissView()
        panel.contentView = view
        var dismissals = 0
        view.dismiss = { dismissals += 1 }
        let inside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertFalse(view.handle(inside))
        XCTAssertEqual(dismissals, 0)
        let other = NSWindow(contentRect: main.frame, styleMask: [.titled], backing: .buffered, defer: false)
        let unrelated = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: other.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        XCTAssertFalse(view.handle(unrelated))
        XCTAssertEqual(dismissals, 0)
        let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: main.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertTrue(view.handle(outside))
        XCTAssertEqual(dismissals, 1)
    }
}
