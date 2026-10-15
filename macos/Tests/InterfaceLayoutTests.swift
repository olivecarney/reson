import XCTest
import SwiftUI
import AppKit
@testable import Reson

@MainActor
final class InterfaceLayoutTests: XCTestCase {
    func testNativeLayoutFitsCompactWindowWithBothSidePanels() {
        let model = PlayerModel()
        model.showInspector = true
        var selected = PlaybackSnapshot()
        selected.path = "/tmp/reson-layout-selected.wav"; selected.title = String(repeating: "Long title · ", count: 20)
        selected.artist = "Example artist"; selected.album = "Original album"; selected.genre = "Ambient"
        selected.bpm = 85; selected.key = "A minor"; selected.rate = 48000; selected.bits = 24; selected.channels = 2; selected.duration = 61; selected.format = "WAV"
        model.tracks = [selected]; model.selectedPath = selected.path
        var playing = selected; playing.path = "/tmp/reson-layout-playing.flac"; playing.title = "Playing independently"; playing.format = "FLAC"
        model.playback = playing
        let hosting = NSHostingView(rootView: ContentView(model: model).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 520), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setContentSize(NSSize(width: 820, height: 520)); hosting.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(window.contentMinSize.width, 820, "Header/transport must not force a wider window")
        XCTAssertLessThanOrEqual(window.contentMinSize.height, 520, "Inspector must scroll within the compact height")
        XCTAssertEqual(hosting.frame.size, NSSize(width: 820, height: 520))
        let slider = descendants(hosting).compactMap {$0 as? ScrubSlider}.first
        XCTAssertNotNil(slider)
        if let slider {
            let rect=slider.convert(slider.bounds,to:hosting)
            XCTAssertGreaterThanOrEqual(rect.minX,0)
            XCTAssertLessThanOrEqual(rect.maxX,hosting.bounds.width)
            XCTAssertGreaterThan(rect.width,100,"Seek control remains usable with both panels visible")
        }
        save(hosting,name:"compact")
        window.setContentSize(NSSize(width: 1180, height: 740)); hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.frame.size, NSSize(width: 1180, height: 740))
        save(hosting,name:"normal")
        window.setContentSize(NSSize(width:1600,height:1000));hosting.layoutSubtreeIfNeeded()
        save(hosting,name:"large")
    }
    private func descendants(_ view:NSView)->[NSView] {view.subviews.flatMap {[$0]+descendants($0)}}
    private func save(_ view:NSView,name:String) {
        guard let folder=ProcessInfo.processInfo.environment["RESON_INTERFACE_EVIDENCE"], let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {return}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let png=bitmap.representation(using:.png,properties:[:]) {try? png.write(to:URL(fileURLWithPath:folder).appendingPathComponent(name+".png"))}
    }
}
