import XCTest
@testable import Reson
final class PlaybackSessionTests: XCTestCase {
    func track(_ path: String, missing: Bool = false) -> PlaybackSnapshot { var t=PlaybackSnapshot(); t.path=path; t.title=path; t.missing=missing; return t }
    func testStableSequenceQueuePriorityDuplicatesAndConsumption() {
        var s=PlaybackSession()
        XCTAssertEqual(s.start([track("a"),track("b"),track("c")], at: 0, label: "Library")?.path,"a"); s.began()
        s.enqueue([track("x"),track("x")], next: false)
        s.enqueue([track("y"),track("z")], next: true)
        XCTAssertEqual(s.next()?.path,"y"); XCTAssertEqual(s.queue.count,4); s.began(); XCTAssertEqual(s.queue.count,3)
        for path in ["z","x","x","b","c"] { XCTAssertEqual(s.next()?.path,path); s.began() }
        XCTAssertNil(s.next()); XCTAssertEqual(s.previous()?.path,"b"); s.began()
        XCTAssertEqual(s.next()?.path,"c"); s.began(); XCTAssertNil(s.next())
        XCTAssertEqual(s.label,"Library")
    }
    func testRemoveClearMoveAndDuplicateQueueIdentity() {
        var s=PlaybackSession(); _=s.start([track("a"),track("b")],at:0,label:"Playlist"); s.began()
        s.enqueue([track("x"),track("x"),track("y")],next:false)
        let ids=s.queue.map(\.id); XCTAssertNotEqual(ids[0],ids[1])
        XCTAssertTrue(s.moveQueue(ids:[ids[0],ids[2]],to:3)); XCTAssertEqual(s.queue.map(\.id),[ids[1],ids[0],ids[2]])
        XCTAssertFalse(s.moveQueue(ids:[UUID()],to:0)); s.removeQueue(ids:[ids[1]])
        XCTAssertEqual(s.next()?.path,"x"); s.began(); s.clearQueue()
        XCTAssertEqual(s.current?.path,"x"); XCTAssertEqual(s.next()?.path,"b")
    }
    func testMissingEntriesAreBoundedAndPreviousUsesSuccessfulHistory() {
        var s=PlaybackSession(); _=s.start([track("a"),track("gone",missing:true),track("bad"),track("b")],at:0,label:"Playlist"); s.began()
        XCTAssertEqual(s.next()?.path,"bad") // model handles decoder failures; no cycling
        XCTAssertEqual(s.next()?.path,"b"); s.began()
        XCTAssertEqual(s.previous()?.path,"a"); s.began(); XCTAssertNil(s.previous())
        XCTAssertEqual(s.next()?.path,"b"); s.began(); XCTAssertNil(s.next())
    }
    func testCompletionFenceRequiresAcknowledgementAndIgnoresStopErrorsAndRepeatedEOF() {
        var f=PlaybackCompletion(); f.arm()
        var s=PlaybackSnapshot(); s.generation=3; s.acknowledged=6; s.state=5
        XCTAssertFalse(f.consume(s, generation:4, expected:6))
        XCTAssertFalse(f.consume(s, generation:3, expected:7))
        XCTAssertTrue(f.consume(s,generation:3,expected:6)); XCTAssertFalse(f.consume(s,generation:3,expected:6))
        f.arm(); s.state=6; XCTAssertFalse(f.consume(s,generation:3,expected:6))
        f.disarm(); s.state=5; XCTAssertFalse(f.consume(s,generation:3,expected:6))
    }
}
