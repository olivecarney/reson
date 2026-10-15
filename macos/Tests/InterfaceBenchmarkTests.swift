import XCTest
import AppKit
import SwiftUI
@testable import Reson

@MainActor final class InterfaceBenchmarkTests: XCTestCase {
    func testNativeWindowAndQueuePresentation() async throws {
        guard let directory=ProcessInfo.processInfo.environment["RESON_PLAYLIST_BENCHMARKS"] else {throw XCTSkip("Opt-in synthetic native interface benchmarks")}
        for count in [270,5000,25000] {
            let model=PlayerModel(databaseURL:URL(fileURLWithPath:directory).appendingPathComponent("\(count).db"))
            model.startLibrary()
            for _ in 0..<3000 {if !model.libraryLoading {break};try await Task.sleep(for:.milliseconds(2))}
            XCTAssertEqual(model.tracks.count,count)
            model.showInspector=true
            let start=ContinuousClock.now
            let host=NSHostingView(rootView:ContentView(model:model).preferredColorScheme(.dark))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1180,height:740),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
            window.contentView=host;host.layoutSubtreeIfNeeded()
            let render=ms(start)
            let table=try XCTUnwrap(descendants(host).compactMap {$0 as? TrackListView}.first)
            var scroll:[Double]=[]
            var actionTimes:[Double]=[], layoutTimes:[Double]=[], cellTimes:[Double]=[]
            for step in 0..<30 {
                let row=[0,count/2,count-1,1,count-2][step % 5]
                let began=ContinuousClock.now;table.scrollRowToVisible(row);let actionMS=ms(began)
                let layout=ContinuousClock.now;host.layoutSubtreeIfNeeded();let layoutMS=ms(layout)
                let cells=ContinuousClock.now
                let cell=try XCTUnwrap(table.view(atColumn:1,row:row,makeIfNecessary:true) as? NSTableCellView)
                XCTAssertEqual(cell.textField?.stringValue,model.tracks[row].displayTitle);if step >= 5 {scroll.append(ms(began));actionTimes.append(actionMS);layoutTimes.append(layoutMS);cellTimes.append(ms(cells))}
            }
            model.enqueue(Array(model.tracks.prefix(100)),next:false)
            let queued=ContinuousClock.now
            let queue=NSHostingView(rootView:QueueView(model:model));queue.frame=NSRect(x:0,y:0,width:800,height:500);queue.layoutSubtreeIfNeeded()
            let queueMS=ms(queued)
            scroll.sort()
            print("NATIVE_INTERFACE count=\(count) host_ms=\(render) scroll_median_ms=\(scroll[scroll.count/2]) scroll_p95_ms=\(scroll[Int(Double(scroll.count-1)*0.95)]) scroll_max_ms=\(scroll.max() ?? 0) queue_host_ms=\(queueMS) action_avg_ms=\(actionTimes.reduce(0,+)/Double(actionTimes.count)) layout_avg_ms=\(layoutTimes.reduce(0,+)/Double(layoutTimes.count)) cell_avg_ms=\(cellTimes.reduce(0,+)/Double(cellTimes.count))")
            window.contentView=nil
            await model.shutdown()
        }
    }
    private func descendants(_ view:NSView)->[NSView] {view.subviews.flatMap {[$0]+descendants($0)}}
    private func ms(_ start:ContinuousClock.Instant)->Double {let d=start.duration(to:.now);return Double(d.components.seconds)*1000+Double(d.components.attoseconds)/1e15}
}
