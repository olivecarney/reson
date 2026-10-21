import XCTest
import SwiftUI
@testable import Reson

@MainActor final class LibraryManagementTests: XCTestCase {
    func settle(_ model:PlayerModel) async throws {
        for _ in 0..<1000 {if !model.libraryLoading && !model.importBusy {return};try await Task.sleep(for:.milliseconds(5))}
        XCTFail("Library did not settle")
    }
    func testRemovalRestoreAndFolderEditsShareModelAndDoNotAlterPlaybackSession() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let music=root.appendingPathComponent("music");try FileManager.default.createDirectory(at:music,withIntermediateDirectories:true)
        let fixture=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/synthetic.mp3")
        for n in 0..<3 {try FileManager.default.copyItem(at:fixture,to:music.appendingPathComponent("\(n).mp3"))}
        let db=root.appendingPathComponent("library.db"),bridge=LibraryBridge(databaseURL:root.appendingPathComponent("library.db"))
        let _:LibraryReply=try await bridge.request(["op":"import","path":music.path])
        for _ in 0..<1000 {let s:LibraryStatus=try await bridge.request(["op":"status"]);if !s.busy {break};try await Task.sleep(for:.milliseconds(5))}
        await bridge.shutdown()
        let model=PlayerModel(databaseURL:db);model.startLibrary();try await settle(model);await model.refreshSources()
        XCTAssertEqual(model.libraryFolders.count,1);let rows=model.tracks;XCTAssertEqual(rows.count,3)
        let created=await model.createPlaylist(name:"Keep");let playlist=try XCTUnwrap(created)
        _=await model.mutatePlaylist(["op":"playlist_add","playlist_id":playlist,"ids":rows.compactMap(\.libraryID)])
        _=model.session.start(rows,at:0,label:"Library");model.session.began();model.enqueue([rows[1]],next:true)
        // Simulate the transient row retained after a playback snapshot update.
        model.sessionTracks=[rows[0]]
        let removed=await model.manageLibrary(["op":"tracks_remove","ids":[rows[0].libraryID!]])
        XCTAssertTrue(removed);try await settle(model)
        XCTAssertEqual(model.tracks.count,2);XCTAssertEqual(model.excludedPaths,[rows[0].path]);XCTAssertEqual(model.session.current?.path,rows[0].path);XCTAssertEqual(model.session.queue.count,1)
        model.sessionTracks=[rows[0]];model.reloadLibrary();try await settle(model);XCTAssertEqual(model.tracks.count,2,"Playback snapshots must not recreate excluded rows")
        model.rescanFolders();try await settle(model);XCTAssertEqual(model.tracks.count,2)
        let restored=await model.manageLibrary(["op":"exclusion_restore","path":rows[0].path]);XCTAssertTrue(restored)
        model.rescanFolders();try await settle(model);XCTAssertEqual(model.tracks.count,3)
        let folderRemoved=await model.manageLibrary(["op":"folder_remove","path":model.libraryFolders[0]]);XCTAssertTrue(folderRemoved);try await settle(model)
        XCTAssertTrue(model.tracks.isEmpty);XCTAssertTrue(model.libraryFolders.isEmpty);XCTAssertEqual(model.session.current?.path,rows[0].path)
        model.selectPlaylist(playlist);try await settle(model);XCTAssertEqual(model.tracks.count,3);XCTAssertTrue(model.tracks.allSatisfy(\.missing))
        for row in rows {XCTAssertTrue(FileManager.default.fileExists(atPath:row.path))}
        await model.shutdown()
        let reopened=PlayerModel(databaseURL:db);reopened.startLibrary();try await settle(reopened);reopened.selectPlaylist(playlist);try await settle(reopened);XCTAssertEqual(reopened.tracks.count,3);await reopened.shutdown()
    }
}


extension LibraryManagementTests {
    func testNativeRemovalKeepsMP3PlayingWithoutRecreatingLibraryRow() async throws {
        guard let fixtures=ProcessInfo.processInfo.environment["RESON_AUDIO_FIXTURES"] else {throw XCTSkip("Opt-in: silent MP3 on real CoreAudio")}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let music=root.appendingPathComponent("music");try FileManager.default.createDirectory(at:music,withIntermediateDirectories:true)
        let source=music.appendingPathComponent("silent.mp3")
        try FileManager.default.copyItem(at:URL(fileURLWithPath:fixtures).appendingPathComponent("silent.mp3"),to:source)
        let db=root.appendingPathComponent("library.db"),bridge=LibraryBridge(databaseURL:root.appendingPathComponent("library.db"))
        let _:LibraryReply=try await bridge.request(["op":"import","path":music.path])
        for _ in 0..<1000 {let status:LibraryStatus=try await bridge.request(["op":"status"]);if !status.busy {break};try await Task.sleep(for:.milliseconds(5))}
        await bridge.shutdown()
        let model=PlayerModel(databaseURL:db);model.startLibrary();try await settle(model)
        let row=try XCTUnwrap(model.tracks.first);model.playRow(row.rowID)
        for _ in 0..<1000 {if model.playback.state==2 {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(model.playback.state,2,model.playback.error ?? "")
        let generation=model.playback.generation
        let removed=await model.manageLibrary(["op":"tracks_remove","ids":[row.libraryID!]])
        XCTAssertTrue(removed);try await settle(model);try await Task.sleep(for:.milliseconds(500))
        XCTAssertTrue(model.tracks.isEmpty);XCTAssertEqual(model.playback.state,2);XCTAssertEqual(model.playback.generation,generation)
        XCTAssertEqual(model.session.current?.path,row.path);XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
        model.stop();await model.shutdown()
    }
}
