import XCTest
import SwiftUI
import AppKit
@testable import Reson

@MainActor
final class TrackTableTests: XCTestCase {
    final class ReuseTable: NSTableView {
        var recycled: NSView?
        override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
            guard recycled?.identifier == identifier else { return nil }
            return recycled
        }
    }
    func track(_ path: String, title: String, artist: String? = nil) -> PlaybackSnapshot {
        var s = PlaybackSnapshot(); s.path = path; s.title = title; s.artist = artist; s.format = "FLAC"; s.duration = 61
        return s
    }
    func testTextCellReuseResetsContentAndKeepsConstraints() {
        var tracks = [track("a", title: "First", artist: "Artist"), track("b", title: "Second")]
        tracks[0].album = "First album"; tracks[1].format = "WAV"; tracks[1].duration = -1
        let parent = TrackTable(tracks: tracks, selection: .constant(nil), play: { _ in })
        let coordinator = parent.makeCoordinator(); let table = ReuseTable()
        for id in ["title", "artist", "album", "format", "duration", "bpm", "key"] {
            table.recycled = nil
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            let first = coordinator.tableView(table, viewFor: column, row: 0) as! NSTableCellView
            let count = first.constraints.count
            first.textField?.font = .systemFont(ofSize: 22); first.textField?.textColor = .red
            table.recycled = first
            let second = coordinator.tableView(table, viewFor: column, row: 1) as! NSTableCellView
            XCTAssertTrue(first === second, "\(id) did not reuse its cell")
            XCTAssertEqual(second.identifier, column.identifier)
            XCTAssertEqual(second.constraints.count, count)
            let expected = ["title": "Second", "artist": "—", "album": "—", "format": "WAV", "duration": "—", "bpm": "—", "key": "—"]
            XCTAssertEqual(second.textField?.stringValue, expected[id])
            XCTAssertEqual(second.textField?.textColor, id == "title" ? .labelColor : .secondaryLabelColor)
            XCTAssertEqual(second.textField?.font, .systemFont(ofSize: 13, weight: .regular))
        }
    }
    func testArtworkReuseResetsImageAndTint() {
        let parent = TrackTable(tracks: [track("a", title: "A"), track("b", title: "B")], selection: .constant(nil), play: { _ in })
        let coordinator = parent.makeCoordinator(); let table = ReuseTable()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("art"))
        let first = coordinator.tableView(table, viewFor: column, row: 0) as! ArtworkCell
        first.artwork.image = nil; first.artwork.contentTintColor = .red; table.recycled = first
        let second = coordinator.tableView(table, viewFor: column, row: 1) as! ArtworkCell
        XCTAssertTrue(first === second); XCTAssertNotNil(second.artwork.image); XCTAssertNotEqual(second.artwork.contentTintColor, .red)
    }
    func testReusedArtworkCellRejectsPreviousTrackAndOnlyUpdatesImage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.flac"), b = root.appendingPathComponent("b.flac")
        try ArtworkTests.flac(ArtworkTests.png(width: 300, height: 100)).write(to: a)
        try ArtworkTests.flac(ArtworkTests.png(width: 100, height: 300)).write(to: b)
        let cache = ArtworkCache(directory: root.appendingPathComponent("cache"))
        let parent = TrackTable(tracks: [track(a.path, title: "A"), track(b.path, title: "B")], selection: .constant(nil), play: { _ in }, artworkCache: cache)
        let coordinator = parent.makeCoordinator(); let table = ReuseTable()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("art"))
        let first = coordinator.tableView(table, viewFor: column, row: 0) as! ArtworkCell
        table.recycled = first
        let second = coordinator.tableView(table, viewFor: column, row: 1) as! ArtworkCell
        XCTAssertTrue(first === second)
        for _ in 0..<200 {
            if second.artwork.contentTintColor == nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(second.representedPath, b.path)
        XCTAssertEqual(second.artwork.image?.size, NSSize(width: 27, height: 80))
        XCTAssertNil(second.artwork.contentTintColor)
        await cache.shutdown()
    }
    final class CountingTable: NSTableView {
        var fullReloads = 0
        var updatedRows = IndexSet()
        override func reloadData() { fullReloads += 1; super.reloadData() }
        override func reloadData(forRowIndexes rows: IndexSet, columnIndexes columns: IndexSet) {
            updatedRows.formUnion(rows); super.reloadData(forRowIndexes: rows, columnIndexes: columns)
        }
    }
    func testPlaybackUpdatesDoNotReloadAndMetadataUpdatesOnlyAffectedRows() {
        let initial = [track("a", title: "A"), track("b", title: "B")]
        let parent = TrackTable(tracks: initial, selection: .constant("b"), play: { _ in })
        let coordinator = parent.makeCoordinator(); let table = CountingTable()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")))
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table
        table.reloadData(); table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.fullReloads = 0; table.updatedRows = []
        var playbackOnly = initial
        playbackOnly[0].position = 12; playbackOnly[0].state = 3; playbackOnly[0].acknowledged = 20
        coordinator.update(TrackTable(tracks: playbackOnly, selection: .constant("b"), play: { _ in }))
        XCTAssertEqual(table.fullReloads, 0); XCTAssertTrue(table.updatedRows.isEmpty)
        var metadata = playbackOnly; metadata[0].artist = "Changed artist"
        coordinator.update(TrackTable(tracks: metadata, selection: .constant("b"), play: { _ in }))
        XCTAssertEqual(table.fullReloads, 0); XCTAssertEqual(table.updatedRows, IndexSet(integer: 0)); XCTAssertEqual(table.selectedRow, 1)
        table.updatedRows = []
        coordinator.update(TrackTable(tracks: metadata + [track("c", title: "C")], selection: .constant("b"), play: { _ in }))
        XCTAssertEqual(table.fullReloads, 1); XCTAssertEqual(table.selectedRow, 1)
        coordinator.update(TrackTable(tracks: [metadata[1], metadata[0]], selection: .constant("b"), play: { _ in }))
        XCTAssertEqual(table.fullReloads, 2); XCTAssertEqual(table.selectedRow, 0)
    }

    func testRescanRefreshesVisibleArtworkWithoutFullReload() {
        let tracks = [track("a", title: "A"), track("b", title: "B")]
        let parent = TrackTable(tracks: tracks, selection: .constant(nil), play: { _ in })
        let coordinator = parent.makeCoordinator()
        let table = CountingTable(frame: NSRect(x: 0, y: 0, width: 400, height: 144))
        table.rowHeight = 48
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("art")))
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title")))
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table
        table.reloadData(); table.fullReloads = 0; table.updatedRows = []
        coordinator.update(TrackTable(tracks: tracks, selection: .constant(nil), play: { _ in }, artworkRevision: 1))
        XCTAssertEqual(table.fullReloads, 0); XCTAssertEqual(table.updatedRows, IndexSet(integersIn: 0..<2))
    }
    func testNativeArtworkScrollingIsLazyAndShowsCurrentImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wide = root.appendingPathComponent("wide.flac"), tall = root.appendingPathComponent("tall.flac")
        try ArtworkTests.flac(ArtworkTests.png(width: 300, height: 100)).write(to: wide)
        try ArtworkTests.flac(ArtworkTests.png(width: 100, height: 300)).write(to: tall)
        let directory = root.appendingPathComponent("cache")
        let cache = ArtworkCache(directory: directory)
        var tracks: [PlaybackSnapshot] = []
        for i in 0..<1000 {
            let url = root.appendingPathComponent("\(i).flac")
            try FileManager.default.linkItem(at: i % 2 == 0 ? wide : tall, to: url)
            tracks.append(track(url.path, title: "Track \(i)"))
        }
        let parent = TrackTable(tracks: tracks, selection: .constant(tracks[80].path), play: { _ in }, artworkCache: cache)
        let coordinator = parent.makeCoordinator()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 144))
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 48000))
        table.rowHeight = 48
        for id in ["art", "title"] { table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))) }
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table
        scroll.documentView = table; table.reloadData(); coordinator.update(parent)
        for row in [0, 800, 801, 999, 0] {
            table.scrollRowToVisible(row); scroll.layoutSubtreeIfNeeded(); table.layoutSubtreeIfNeeded()
            let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as! ArtworkCell
            for _ in 0..<200 {
                if cell.artwork.contentTintColor == nil { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(cell.representedPath, tracks[row].path)
            XCTAssertEqual(cell.artwork.image?.size, row % 2 == 0 ? NSSize(width: 80, height: 27) : NSSize(width: 27, height: 80))
            XCTAssertEqual(table.selectedRow, 80)
        }
        await cache.shutdown()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertLessThan(files.count, 40, "Invisible rows should not request thumbnails")
    }
    func testNativeScrollingShowsCurrentRowContent() {
        let tracks = (0..<100).map { track("path-\($0)", title: "Track \($0)", artist: $0 % 2 == 0 ? "Artist \($0)" : nil) }
        let parent = TrackTable(tracks: tracks, selection: .constant("path-80"), play: { _ in })
        let coordinator = parent.makeCoordinator()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 144))
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 4800))
        table.rowHeight = 48
        for id in ["title", "artist"] { table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))) }
        table.dataSource = coordinator; table.delegate = coordinator; coordinator.table = table
        scroll.documentView = table; table.reloadData()
        coordinator.update(parent)
        for row in [0, 80, 81, 99, 0] {
            table.scrollRowToVisible(row); scroll.layoutSubtreeIfNeeded(); table.layoutSubtreeIfNeeded()
            let title = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView
            let artist = table.view(atColumn: 1, row: row, makeIfNecessary: true) as? NSTableCellView
            XCTAssertEqual(title?.textField?.stringValue, "Track \(row)")
            XCTAssertEqual(artist?.textField?.stringValue, row % 2 == 0 ? "Artist \(row)" : "—")
            XCTAssertEqual(table.selectedRow, 80)
        }
    }

}
