import XCTest
import AppKit
import SwiftUI
@testable import Reson

@MainActor final class PlaylistBenchmarkTests:XCTestCase {
    func testQueueLatencyLargeNativeTablesAndMainActorResponsiveness() async throws {
        guard let directory=ProcessInfo.processInfo.environment["RESON_PLAYLIST_BENCHMARKS"] else {throw XCTSkip("Opt-in synthetic 270/5000/25000 database benchmarks")}
        for count in [270,5000,25000] {
            let model=PlayerModel(databaseURL:URL(fileURLWithPath:directory).appendingPathComponent("\(count).db"));model.startLibrary()
            let ready=ContinuousClock.now
            for _ in 0..<3000 {if !model.libraryLoading {break};try await Task.sleep(for:.milliseconds(2))}
            XCTAssertEqual(model.tracks.count,count)
            let libraryMS=Double(ready.duration(to:.now).components.attoseconds)/1e15+Double(ready.duration(to:.now).components.seconds)*1000
            let start=ContinuousClock.now;model.enqueue(model.tracks,next:false)
            let queueMS=milliseconds(start.duration(to:.now));XCTAssertEqual(model.session.queue.count,count)
            let rows=model.queueTracks;let move=ContinuousClock.now;model.moveQueued([rows[0],rows[2],rows[4]],to:count)
            let moveMS=milliseconds(move.duration(to:.now));XCTAssertEqual(model.session.queue.suffix(3).map(\.track.path),[rows[0].path,rows[2].path,rows[4].path])
            let clear=ContinuousClock.now;model.session.clearQueue();let clearMS=milliseconds(clear.duration(to:.now))
            let parent=TrackTable(tracks:model.tracks,selection:.constant(nil),play:{_ in},dataRevision:1)
            let c=parent.makeCoordinator();let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:800,height:240));let table=NSTableView(frame:NSRect(x:0,y:0,width:800,height:CGFloat(count)*48))
            table.rowHeight=48;table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("title")));table.dataSource=c;table.delegate=c;c.table=table;scroll.documentView=table;table.reloadData()
            var scrollTimes:[Double]=[]
            for row in [0,count/2,count-1,1,count-2] {
                let begin=ContinuousClock.now;table.scrollRowToVisible(row);scroll.layoutSubtreeIfNeeded();table.layoutSubtreeIfNeeded()
                let cell=table.view(atColumn:0,row:row,makeIfNecessary:true) as! NSTableCellView
                XCTAssertEqual(cell.textField?.stringValue,model.tracks[row].displayTitle);scrollTimes.append(milliseconds(begin.duration(to:.now)))
            }
            let playlist=try XCTUnwrap(model.playlists.first);model.selectPlaylist(playlist.id)
            for _ in 0..<3000 {if !model.libraryLoading {break};try await Task.sleep(for:.milliseconds(2))}
            XCTAssertEqual(model.tracks.count,count)
            let ids=[model.tracks[0].entryID!,model.tracks[2].entryID!,model.tracks[4].entryID!]
            var gaps:[Double]=[];var last=ContinuousClock.now
            let heartbeat=Task {while !Task.isCancelled {try? await Task.sleep(for:.milliseconds(2));let now=ContinuousClock.now;gaps.append(milliseconds(last.duration(to:now)));last=now}}
            let mutation=ContinuousClock.now;let ok=await model.mutatePlaylist(["op":"playlist_move","playlist_id":playlist.id,"ids":ids,"position":count,"revision":model.playlistRevision])
            XCTAssertTrue(ok)
            for _ in 0..<3000 {if !model.libraryLoading {break};try await Task.sleep(for:.milliseconds(2))}
            heartbeat.cancel();let totalMS=milliseconds(mutation.duration(to:.now))
            print("SWIFT_PLAYLIST count=\(count) library_ready_ms=\(libraryMS) enqueue_ms=\(queueMS) queue_move_ms=\(moveMS) queue_clear_ms=\(clearMS) native_scroll_max_ms=\(scrollTimes.max() ?? 0) edit_and_reload_ms=\(totalMS) main_actor_gap_max_ms=\(gaps.max() ?? 0)")
            await model.shutdown()
        }
    }
    private func milliseconds(_ duration:Duration)->Double {Double(duration.components.seconds)*1000+Double(duration.components.attoseconds)/1e15}
}
