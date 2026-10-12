import XCTest
@testable import Reson
final class PlaybackSnapshotTests: XCTestCase {
    func testPollingWaitsForAcknowledgement() {
        var s = PlaybackSnapshot(); s.state = 4; s.acknowledged = 1
        XCTAssertTrue(s.needsRefresh(expected: 2))
        s.acknowledged = 2; XCTAssertFalse(s.needsRefresh(expected: 2))
        s.state = 2; XCTAssertTrue(s.needsRefresh(expected: 2))
        s.state = 3; XCTAssertFalse(s.needsRefresh(expected: 2))
    }
    func testReplacementRejectsStaleSnapshot() {
        var s = PlaybackSnapshot(); s.generation = 1; s.path = "old.wav"
        XCTAssertFalse(s.acceptable(after: 2))
        s.generation = 2; XCTAssertTrue(s.acceptable(after: 2))
    }
}
