import XCTest
@testable import Reson

@MainActor final class PlaylistIntegrationTests:XCTestCase {
    func fixtureLibrary() async throws -> (URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let music=root.appendingPathComponent("music");try FileManager.default.createDirectory(at:music,withIntermediateDirectories:true)
        let source=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/pcm16-44100-1.wav")
        for name in ["a","b","c"] {try FileManager.default.copyItem(at:source,to:music.appendingPathComponent(name+".wav"))}
        let db=root.appendingPathComponent("library.db");let bridge=LibraryBridge(databaseURL:db)
        let _:LibraryReply=try await bridge.request(["op":"import","path":music.path])
        for _ in 0..<200 {let status:LibraryStatus=try await bridge.request(["op":"status"]);if !status.busy {break};try await Task.sleep(for:.milliseconds(5))}
        await bridge.shutdown();return(root,db)
    }
    func settle(_ model:PlayerModel) async throws {
        for _ in 0..<400 {if !model.libraryLoading {return};try await Task.sleep(for:.milliseconds(5))}
        XCTFail("Library did not finish loading")
    }
    func testBridgeBackedEditsNavigationSelectionAndSequenceAreIndependent() async throws {
        let (root,db)=try await fixtureLibrary();defer {try? FileManager.default.removeItem(at:root)}
        let model=PlayerModel(databaseURL:db);model.startLibrary();try await settle(model)
        let visible=model.tracks;let created=await model.createPlaylist(name:"Duplicates");let id=try XCTUnwrap(created)
        let tableRevision=model.tableRevision
        let added=await model.mutatePlaylist(["op":"playlist_add","playlist_id":id,"ids":[visible[1].libraryID!,visible[0].libraryID!,visible[1].libraryID!]])
        XCTAssertTrue(added);try await settle(model);XCTAssertEqual(model.tableRevision,tableRevision,"Editing a background playlist must not reload the whole library");model.selectPlaylist(id);try await settle(model)
        XCTAssertEqual(model.tracks.map(\.displayTitle),["b","a","b"]);XCTAssertNotEqual(model.tracks[0].rowID,model.tracks[2].rowID)
        _=model.session.start(model.tracks,at:0,label:model.listTitle);model.session.began()
        model.selectedPath=model.tracks[2].rowID;XCTAssertEqual(model.selected?.entryID,model.tracks[2].entryID)
        let removed=await model.mutatePlaylist(["op":"playlist_remove","playlist_id":id,"ids":[model.tracks[0].entryID!]])
        XCTAssertTrue(removed);try await settle(model);XCTAssertEqual(model.session.current?.displayTitle,"b")
        model.selectPlaylist(nil);model.search="c.wav";try await settle(model);XCTAssertEqual(model.tracks.map(\.displayTitle),["c"]);XCTAssertEqual(model.playingRowID,model.session.current?.path)
        XCTAssertEqual(model.session.next()?.displayTitle,"a");model.session.began();XCTAssertEqual(model.session.next()?.displayTitle,"b")
        await model.shutdown()
        let reopened=PlayerModel(databaseURL:db);reopened.startLibrary();try await settle(reopened);reopened.selectPlaylist(id);try await settle(reopened)
        XCTAssertEqual(reopened.tracks.map(\.displayTitle),["a","b"]);await reopened.shutdown()
    }
    func testNativeEngineEOFQueueDuplicatesStopAndRapidReplacement() async throws {
        guard ProcessInfo.processInfo.environment["RESON_NATIVE_PLAYBACK_TEST"]=="1" else {throw XCTSkip("Opt-in: opens a real CoreAudio output stream with synthetic audio")}
        let (root,db)=try await fixtureLibrary();defer {try? FileManager.default.removeItem(at:root)}
        let model=PlayerModel(databaseURL:db);model.startLibrary();try await settle(model);let rows=model.tracks
        model.playRow(rows[0].rowID);model.enqueue([rows[2],rows[2]],next:true);model.enqueue([rows[1]],next:false)
        for _ in 0..<1000 {if model.playback.state==6 {XCTFail(model.playback.error ?? "Output failed");break};if model.playback.state==5 && !model.canNext && model.playback.path==rows[2].path {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(model.playback.state,5);XCTAssertEqual(model.playback.path,rows[2].path);XCTAssertTrue(model.session.queue.isEmpty)
        var history=model.session
        for name in ["b","b","c","c","a"] {XCTAssertEqual(history.previous()?.displayTitle,name);history.began()}
        model.playRow(rows[0].rowID);model.stop()
        for _ in 0..<300 {if model.playback.state==4 {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(model.playback.state,4);try await Task.sleep(for:.milliseconds(350));XCTAssertEqual(model.playback.state,4)
        model.playRow(rows[0].rowID);model.playRow(rows[1].rowID);model.playRow(rows[2].rowID)
        for _ in 0..<400 {if model.playback.path==rows[2].path && [2,5,6].contains(model.playback.state) {break};try await Task.sleep(for:.milliseconds(5))}
        XCTAssertEqual(model.playback.path,rows[2].path);XCTAssertNotEqual(model.playback.state,6)
        await model.shutdown()
    }
}
