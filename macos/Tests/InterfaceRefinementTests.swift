import XCTest
import AppKit
import SwiftUI
@testable import Reson

@MainActor final class InterfaceRefinementTests: XCTestCase {
    func testReturnPlaysSelectedOccurrenceAndMissingRowsCannotPlay() {
        var a = PlaybackSnapshot(); a.path = "/duplicate.wav"; a.entryID = 1
        var b = a; b.entryID = 2; b.missing = true
        var played: String?
        let parent = TrackTable(tracks: [a,b], selection: .constant(nil), play: {played=$0}, sourceID: "playlist:1")
        let c = parent.makeCoordinator(); let table = TrackListView()
        table.dataSource=c; c.table=table; table.reloadData()
        table.rowAction={c.performRows($0)}
        table.selectRowIndexes(IndexSet(integer:0), byExtendingSelection:false)
        table.keyDown(with:key(36))
        XCTAssertEqual(played,"e:1")
        played=nil; table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        table.keyDown(with:key(36)); XCTAssertNil(played)
    }
    func testContextMenuOffersPlayAndDisablesBoundaryMoves() {
        var a=PlaybackSnapshot(); a.path="a"; a.title="A"
        let parent=TrackTable(tracks:[a],selection:.constant(nil),play:{_ in},sourceID:"playlist:1",move:{_,_ in})
        let c=parent.makeCoordinator(); let table=NSTableView();table.dataSource=c;c.table=table;table.reloadData()
        table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        let menu=NSMenu();c.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.first?.title,"Play")
        XCTAssertFalse(menu.items.first(where:{$0.title.hasPrefix("Move Up")})?.isEnabled ?? true)
        XCTAssertFalse(menu.items.first(where:{$0.title.hasPrefix("Move Down")})?.isEnabled ?? true)
    }
    func testDeselectingAllRowsClearsInspectorIdentity() {
        var a=PlaybackSnapshot();a.path="a"
        var selected:String?="a"
        let parent=TrackTable(tracks:[a],selection:Binding(get:{selected},set:{selected=$0}),play:{_ in})
        let c=parent.makeCoordinator();let table=NSTableView();table.dataSource=c;table.delegate=c;c.table=table;table.reloadData()
        table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        table.deselectAll(nil)
        XCTAssertNil(selected)
    }
    func testNumericAlignmentAndFullTextHelp() {
        var a=PlaybackSnapshot();a.path="a";a.title=String(repeating:"Long title ",count:20);a.bpm=128
        let parent=TrackTable(tracks:[a],selection:.constant(nil),play:{_ in})
        let c=parent.makeCoordinator();let table=NSTableView()
        let bpm=c.tableView(table,viewFor:NSTableColumn(identifier:.init("bpm")),row:0) as! NSTableCellView
        XCTAssertEqual(bpm.textField?.alignment,.right)
        let title=c.tableView(table,viewFor:NSTableColumn(identifier:.init("title")),row:0) as! NSTableCellView
        XCTAssertEqual(title.toolTip,a.title)
    }
    func testSpaceDoesNotTogglePlaybackWhenAControlHasFocus() {
        XCTAssertFalse(AppDelegate.handlesPlaybackSpace(key(49),responder:ScrubSlider()))
        XCTAssertFalse(AppDelegate.handlesPlaybackSpace(key(49),responder:NSButton()))
        XCTAssertFalse(AppDelegate.handlesPlaybackSpace(key(49),responder:NSTextView()))
        XCTAssertTrue(AppDelegate.handlesPlaybackSpace(key(49),responder:TrackListView()))
    }
    func testNavigationFocusRequestMakesNativeTableFirstResponder() async {
        let parent=TrackTable(tracks:[],selection:.constant(nil),play:{_ in})
        let c=parent.makeCoordinator(); let table=TrackListView();c.table=table
        table.addTableColumn(NSTableColumn(identifier:.init("title")));table.dataSource=c
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=table
        c.update(TrackTable(tracks:[],selection:.constant(nil),play:{_ in},focusRequest:1))
        for _ in 0..<30 {try? await Task.sleep(for:.milliseconds(2))}
        XCTAssertTrue(window.firstResponder === table)
    }
    func testPlaylistHeadersDoNotRetainLibrarySortIndicators() {
        var sorts=0
        let parent=TrackTable(tracks:[],selection:.constant(nil),play:{_ in},sort:{_,_ in sorts+=1})
        let c=parent.makeCoordinator();let table=NSTableView();c.table=table
        table.addTableColumn(NSTableColumn(identifier:.init("title")))
        table.sortDescriptors=[NSSortDescriptor(key:"title",ascending:false)]
        table.delegate=c
        c.update(TrackTable(tracks:[],selection:.constant(nil),play:{_ in},sourceID:"playlist:1"))
        XCTAssertTrue(table.sortDescriptors.isEmpty)
        c.update(parent)
        XCTAssertEqual(table.sortDescriptors.first?.key,"title")
        XCTAssertEqual(table.sortDescriptors.first?.ascending,false)
        XCTAssertEqual(sorts,0,"Restoring header feedback must not issue a redundant library query")
    }
    func testSourceReplacementCancelsPendingFocusRequest() async {
        let parent=TrackTable(tracks:[],selection:.constant(nil),play:{_ in})
        let c=parent.makeCoordinator(); let table=TrackListView();c.table=table
        table.addTableColumn(NSTableColumn(identifier:.init("title")));table.dataSource=c
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:400,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=table;window.makeFirstResponder(nil)
        c.update(TrackTable(tracks:[],selection:.constant(nil),play:{_ in},focusRequest:1))
        c.update(TrackTable(tracks:[],selection:.constant(nil),play:{_ in},sourceID:"playlist:2",focusRequest:1))
        for _ in 0..<30 {try? await Task.sleep(for:.milliseconds(2))}
        XCTAssertFalse(window.firstResponder === table,"A superseded navigation request must not steal focus")
    }
    private final class ClickedTable: NSTableView {
        override var clickedRow: Int {0}
    }
    func testKeyboardActionsUseCurrentSelectionAfterAnEarlierPointerClick() {
        var a=PlaybackSnapshot();a.path="a";var b=a;b.path="b"
        var played:String?
        let parent=TrackTable(tracks:[a,b],selection:.constant(nil),play:{played=$0})
        let c=parent.makeCoordinator();let table=ClickedTable();table.dataSource=c;c.table=table;table.reloadData()
        table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false)
        c.performRows(.play)
        XCTAssertEqual(played,"b","A stale clickedRow must not override keyboard selection")
        XCTAssertEqual(c.actionRows.map(\.rowID),["a"],"A context click outside the selection still targets its clicked row")
        played=nil;c.performRows(.play,contextMenu:true);XCTAssertEqual(played,"a")
    }
    private final class ColumnRecordingTable: NSTableView {
        var updatedColumns=IndexSet()
        override func reloadData(forRowIndexes rows:IndexSet,columnIndexes columns:IndexSet) {updatedColumns=columns}
    }
    func testPlayingIndicatorRefreshFollowsTheTitleColumnAfterNativeReordering() {
        var a=PlaybackSnapshot();a.path="a"
        let parent=TrackTable(tracks:[a],selection:.constant(nil),play:{_ in},dataRevision:1)
        let c=parent.makeCoordinator();let table=ColumnRecordingTable();table.dataSource=c;c.table=table
        for name in ["art","title","artist"] {table.addTableColumn(NSTableColumn(identifier:.init(name)))}
        table.reloadData();table.moveColumn(1,toColumn:2)
        c.update(TrackTable(tracks:[a],selection:.constant(nil),play:{_ in},playingID:"a",dataRevision:1))
        XCTAssertEqual(table.updatedColumns,IndexSet(integer:2))
    }
    func testTimeCellKeepsAnInsetAtTheTableEdge() {
        var a=PlaybackSnapshot();a.path="a";a.duration=61
        let parent=TrackTable(tracks:[a],selection:.constant(nil),play:{_ in})
        let host=NSHostingView(rootView:parent)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:200),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentView=host;host.layoutSubtreeIfNeeded()
        let table=descendants(host).compactMap {$0 as? TrackListView}.first!
        let cell=table.view(atColumn:7,row:0,makeIfNecessary:true) as! NSTableCellView
        cell.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(cell.textField!.alignmentRect(forFrame:cell.textField!.frame).maxX,cell.bounds.maxX-12)
        XCTAssertEqual(cell.textField?.stringValue,"1:01")
    }
    private func key(_ code:UInt16)->NSEvent {
        NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
    }
}

extension InterfaceRefinementTests {
    func testHostedTimelineHasDisabledStateAndAccessibleValues() throws {
        var committed=0.0
        let host=NSHostingView(rootView:TimelineSlider(value:12,duration:60,enabled:false,begin:{},update:{committed=$0},finish:{}))
        host.frame=NSRect(x:0,y:0,width:240,height:20);host.layoutSubtreeIfNeeded()
        let slider=try XCTUnwrap(descendants(host).compactMap {$0 as? ScrubSlider}.first)
        XCTAssertFalse(slider.isEnabled);XCTAssertFalse(slider.acceptsFirstResponder)
        XCTAssertEqual(slider.accessibilityLabel(),"Playback position")
        XCTAssertEqual(slider.accessibilityValueDescription(),"0:12 of 1:00")
        slider.keyDown(with:key(124));XCTAssertEqual(committed,0)
        host.rootView=TimelineSlider(value:12,duration:60,enabled:true,begin:{},update:{committed=$0},finish:{})
        host.layoutSubtreeIfNeeded()
        slider.keyDown(with:key(119));XCTAssertEqual(committed,60)
        slider.keyDown(with:key(124));XCTAssertEqual(committed,60)
        slider.keyDown(with:key(115));XCTAssertEqual(committed,0)
    }
    func testHostedTableAndSidebarExposeNativeLabelsAndSelection() throws {
        var a=PlaybackSnapshot();a.path="a";a.title="Available";a.missing=true
        let host=NSHostingView(rootView:TrackTable(tracks:[a],selection:.constant("a"),play:{_ in},playingID:"a"))
        host.frame=NSRect(x:0,y:0,width:650,height:180);host.layoutSubtreeIfNeeded()
        let table=try XCTUnwrap(descendants(host).compactMap {$0 as? TrackListView}.first)
        XCTAssertEqual(table.accessibilityLabel(),"Tracks")
        XCTAssertTrue(table.allowsMultipleSelection)
        XCTAssertLessThan(table.rowHeight,48)
        XCTAssertEqual(table.selectedRow,0)
        let cell=try XCTUnwrap(table.view(atColumn:1,row:0,makeIfNecessary:true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("▶") ?? false)
        XCTAssertTrue(cell.textField?.accessibilityLabel()?.contains("Missing") ?? false)
        let sidebar=PlaylistSidebar(playlists:[PlaylistRecord(id:1,name:"One",revision:0),PlaylistRecord(id:2,name:"Two",revision:0)],selection:2,select:{_ in},rename:{_ in},delete:{_ in},export:{_ in},add:{_,_ in})
        let sideHost=NSHostingView(rootView:sidebar);sideHost.frame=NSRect(x:0,y:0,width:160,height:200);sideHost.layoutSubtreeIfNeeded()
        let side=try XCTUnwrap(descendants(sideHost).compactMap {$0 as? NSTableView}.first)
        XCTAssertEqual(side.accessibilityLabel(),"Playlists");XCTAssertEqual(side.selectedRow,1)
        let c=sidebar.makeCoordinator();c.table=side;c.update(PlaylistSidebar(playlists:[PlaylistRecord(id:1,name:"Renamed",revision:1)],selection:nil,select:{_ in},rename:{_ in},delete:{_ in},export:{_ in},add:{_,_ in}))
        XCTAssertEqual(side.selectedRow,-1)
    }
    private func descendants(_ view:NSView)->[NSView] {view.subviews.flatMap {[$0]+descendants($0)}}
}
