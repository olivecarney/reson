import XCTest
import AppKit
import SwiftUI
@testable import Reson

@MainActor final class NativeAppearanceTests: XCTestCase {
    // Selection must remain legible when AppKit changes emphasis, including reused cells.
    func testTrackCellFollowsNativeSelectionAndRestoresMetadataHierarchy() throws {
        var track = PlaybackSnapshot(); track.path = "/synthetic.wav"; track.artist = "Artist"
        let coordinator = TrackTable(tracks: [track], selection: .constant(nil), play: { _ in }).makeCoordinator()
        let column = NSTableColumn(identifier: .init("artist"))
        let cell = try XCTUnwrap(coordinator.tableView(NSTableView(), viewFor: column, row: 0) as? NSTableCellView)
        cell.backgroundStyle = .emphasized
        XCTAssertEqual(cell.textField?.textColor, NSColor.alternateSelectedControlTextColor)
        cell.backgroundStyle = .normal
        XCTAssertEqual(cell.textField?.textColor, NSColor.secondaryLabelColor)
    }

    func testDurationUsesAlignedSystemDigitsWithoutMonospacingTrackTitles() throws {
        var track = PlaybackSnapshot(); track.path = "/synthetic.wav"; track.duration = 61
        let coordinator = TrackTable(tracks: [track], selection: .constant(nil), play: { _ in }).makeCoordinator()
        let cell = try XCTUnwrap(coordinator.tableView(NSTableView(), viewFor: NSTableColumn(identifier: .init("duration")), row: 0) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.font, NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular))
        let title = try XCTUnwrap(coordinator.tableView(NSTableView(), viewFor: NSTableColumn(identifier: .init("title")), row: 0) as? NSTableCellView)
        XCTAssertFalse(title.textField!.font!.isFixedPitch)
    }

    func testLibraryNavigationUsesNativeSelectionAndPlaylistSelectionClearsIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = PlayerModel(databaseURL: directory.appendingPathComponent("library.db"))
        let host = NSHostingView(rootView: ContentView(model: model).preferredColorScheme(.dark))
        host.frame = NSRect(x: 0, y: 0, width: 1180, height: 740)
        host.layoutSubtreeIfNeeded()
        let library = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first { $0.accessibilityLabel() == "Library" })
        XCTAssertEqual(library.style, .sourceList)
        XCTAssertEqual(library.selectedRow, 0)
        XCTAssertLessThanOrEqual(library.rect(ofRow: 0).maxY, library.visibleRect.maxY,
                                 "The source-list selection must fit without clipping its lower corners")
        model.selectPlaylist(7)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(library.selectedRow, -1)
        // Selecting All Tracks routes back through the same model navigation as keyboard/menu actions.
        library.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertNil(model.selectedPlaylistID)
        await model.shutdown()
    }

    private func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }

    func testLibrarySelectionDoesNotIssueDuplicateNavigationForOneClick() throws {
        var navigations = 0
        let host = NSHostingView(rootView: LibraryNavigationRow(selected: false) { navigations += 1 })
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 44); host.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTableView }.first)
        // AppKit changes selection before sending a table's single-click action.
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        if let action = table.action { table.sendAction(action, to: table.target) }
        XCTAssertEqual(navigations, 1, "One click must not trigger two library reloads")
    }
}

extension NativeAppearanceTests {
    func testMaterialRemovesTranslucencyAndRestoresItWithoutStackingEffects() throws {
        let surface = NativeMaterialSurface()
        surface.frame = NSRect(x: 0, y: 0, width: 180, height: 300)
        surface.configure(material: .sidebar, opaque: true)
        let effect = try XCTUnwrap(surface.subviews.first as? NSVisualEffectView)
        XCTAssertTrue(effect.isHidden, "The opaque fallback must remove the blur, not just paint beneath it")
        XCTAssertNotNil(surface.layer?.backgroundColor)
        surface.configure(material: .sidebar, opaque: false)
        XCTAssertFalse(effect.isHidden)
        XCTAssertNil(surface.layer?.backgroundColor)
        XCTAssertEqual(effect.material, NSVisualEffectView.Material.sidebar)
        XCTAssertEqual(effect.blendingMode, NSVisualEffectView.BlendingMode.behindWindow)
        surface.configure(material: .titlebar, opaque: true)
        XCTAssertTrue(effect.isHidden)
        XCTAssertEqual(surface.subviews.count, 1)
        XCTAssertEqual(effect.blendingMode, NSVisualEffectView.BlendingMode.withinWindow)
    }
}
