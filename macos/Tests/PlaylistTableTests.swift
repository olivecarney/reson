import XCTest
import SwiftUI
import AppKit
@testable import Reson
@MainActor final class PlaylistTableTests: XCTestCase {
    func rows() -> [PlaybackSnapshot] { (1...4).map { n in var s=PlaybackSnapshot(); s.path="/duplicate.wav"; s.title="Row \(n)"; s.entryID=Int64(n); s.libraryID=Int64(n); return s } }
    func testDuplicateIdentityAndMultipleSelectionSurviveReorder() {
        let initial=rows(); let parent=TrackTable(tracks:initial,selection:.constant("e:2"),play:{_ in},sourceID:"playlist:1")
        let c=parent.makeCoordinator(); let t=NSTableView(); t.dataSource=c; t.delegate=c; c.table=t; t.reloadData()
        t.selectRowIndexes(IndexSet([1,3]),byExtendingSelection:false)
        c.update(TrackTable(tracks:[initial[3],initial[0],initial[2],initial[1]],selection:.constant("e:2"),play:{_ in},sourceID:"playlist:1"))
        XCTAssertEqual(t.selectedRowIndexes,IndexSet([0,3]))
    }
    func testNativeDragPayloadMovesSelectedEntryOccurrencesAndPreservesTheirOrder() throws {
        let initial=rows(); var moved:[String]=[]; var destination = -1
        let parent=TrackTable(tracks:initial,selection:.constant(nil),play:{_ in},sourceID:"playlist:1",move:{rows,position in moved=rows.map(\.rowID); destination=position})
        let c=parent.makeCoordinator(); let t=NSTableView(); c.table=t
        let board=NSPasteboard.withUniqueName(); defer {board.releaseGlobally()}
        XCTAssertTrue(c.tableView(t,writeRowsWith:IndexSet([0,2]),to:board))
        XCTAssertTrue(c.acceptPayload(board,row:4)); XCTAssertEqual(moved,["e:1","e:3"]); XCTAssertEqual(destination,4)
        XCTAssertFalse(c.acceptPayload(board,row:5))
    }
    func testCancelledOrForeignDropCannotMoveEntriesAndLibraryDropAddsInRowOrder() {
        var inserted:[Int64]=[]
        let library=TrackTable(tracks:rows(),selection:.constant(nil),play:{_ in},sourceID:"library")
        let c=library.makeCoordinator(); let board=NSPasteboard.withUniqueName(); defer {board.releaseGlobally()}
        XCTAssertTrue(c.tableView(NSTableView(),writeRowsWith:IndexSet([0,2]),to:board))
        let target=TrackTable(tracks:[],selection:.constant(nil),play:{_ in},sourceID:"playlist:2",insert:{ids,_ in inserted=ids})
        let drop=target.makeCoordinator(); XCTAssertTrue(drop.acceptPayload(board,row:0)); XCTAssertEqual(inserted,[1,3])
        board.clearContents(); board.setString("malformed",forType:TrackDrag.type); XCTAssertFalse(drop.acceptPayload(board,row:0))
    }
    func testContextActionsOperateOnAllSelectedRowsAndKeyboardMoveUsesOriginalBoundary() {
        var next:[String]=[]; var removed:[String]=[]; var position = -1
        let parent=TrackTable(tracks:rows(),selection:.constant(nil),play:{_ in},sourceID:"playlist:1",move:{_,p in position=p},remove:{removed=$0.map(\.rowID)},playNext:{next=$0.map(\.rowID)})
        let c=parent.makeCoordinator(); let t=NSTableView(); t.dataSource=c; c.table=t; t.reloadData(); t.selectRowIndexes(IndexSet([1,2]),byExtendingSelection:false)
        c.performRows(.playNext); XCTAssertEqual(next,["e:2","e:3"])
        c.performRows(.remove); XCTAssertEqual(removed,["e:2","e:3"])
        c.performRows(.moveDown); XCTAssertEqual(position,4)
    }
}

extension PlaylistTableTests {
    func testNativeSidebarSelectionAndDropTargetUsePlaylistID() {
        var selected:Int64?; var added:[Int64]=[]; var target:Int64?
        let sidebar=PlaylistSidebar(playlists:[PlaylistRecord(id:7,name:"Seven",revision:0)],selection:nil,select:{selected=$0},rename:{_ in},delete:{_ in},export:{_ in},add:{ids,id in added=ids; target=id})
        let c=sidebar.makeCoordinator(); let t=NSTableView(); t.dataSource=c; t.delegate=c; c.table=t; t.reloadData(); t.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        XCTAssertEqual(selected,7)
        let source=TrackTable(tracks:rows(),selection:.constant(nil),play:{_ in}); let board=NSPasteboard.withUniqueName(); defer {board.releaseGlobally()}
        XCTAssertTrue(source.makeCoordinator().tableView(t,writeRowsWith:IndexSet([0,1]),to:board))
        XCTAssertTrue(c.acceptPayload(board,row:0)); XCTAssertEqual(added,[1,2]); XCTAssertEqual(target,7)
        XCTAssertFalse(c.acceptPayload(board,row:1))
    }
}

extension PlaylistTableTests {
    func testSidebarUsesHoveredRowInsteadOfAppKitInsertionBoundary() {
        let parent=PlaylistSidebar(playlists:[PlaylistRecord(id:1,name:"One",revision:0),PlaylistRecord(id:2,name:"Two",revision:0)],selection:nil,select:{_ in},rename:{_ in},delete:{_ in},export:{_ in},add:{_,_ in})
        let c=parent.makeCoordinator(); let table=NSTableView(frame:NSRect(x:0,y:0,width:180,height:300)); table.headerView=nil; table.rowHeight=30; table.intercellSpacing = .zero; table.dataSource=c; table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("playlist")));table.reloadData()
        XCTAssertEqual(c.hoveredRow(table,location:NSPoint(x:40,y:58)),1)
        XCTAssertNil(c.hoveredRow(table,location:NSPoint(x:40,y:90)))
    }
}
