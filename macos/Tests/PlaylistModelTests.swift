import XCTest
@testable import Reson
@MainActor final class PlaylistModelTests: XCTestCase {
    func testCreateRenameSelectDuplicateEntriesDeleteAndTerminalShutdown() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let model=PlayerModel(databaseURL:root.appendingPathComponent("db"))
        let created=await model.createPlaylist(name:"One"); let id=try XCTUnwrap(created)
        XCTAssertEqual(model.playlists.map(\.name),["One"])
        let renamed=await model.mutatePlaylist(["op":"playlist_rename","playlist_id":id,"name":"Two"]); XCTAssertTrue(renamed)
        model.selectPlaylist(id)
        for _ in 0..<100 {if !model.libraryLoading && model.selectedPlaylistID==id {break}; try await Task.sleep(for:.milliseconds(10))}
        XCTAssertEqual(model.listTitle,"Two"); XCTAssertTrue(model.tracks.isEmpty)
        let deleted=await model.mutatePlaylist(["op":"playlist_delete","playlist_id":id]); XCTAssertTrue(deleted)
        XCTAssertNil(model.selectedPlaylistID); XCTAssertTrue(model.playlists.isEmpty)
        await model.shutdown(); let closed=await model.createPlaylist(name:"Closed"); XCTAssertNil(closed)
    }
}
