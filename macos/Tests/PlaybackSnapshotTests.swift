import XCTest
@testable import Reson
final class PlaybackSnapshotTests: XCTestCase {
    func testPollingWaitsForAcknowledgement() {
        var s = PlaybackSnapshot(); s.state = 4; s.acknowledged = 1
        XCTAssertTrue(s.needsRefresh(expected: 2))
        s.acknowledged = 2; XCTAssertFalse(s.needsRefresh(expected: 2))
        s.state = 2; XCTAssertTrue(s.needsRefresh(expected: 2))
        s.state = 3; XCTAssertTrue(s.needsRefresh(expected: 2))
    }
    func testReplacementRejectsStaleSnapshot() {
        var s = PlaybackSnapshot(); s.generation = 1; s.path = "old.wav"
        XCTAssertFalse(s.acceptable(after: 2))
        s.generation = 2; XCTAssertTrue(s.acceptable(after: 2))
    }
}

extension PlaybackSnapshotTests {
    func testOutputNoticeDecodesSeparatelyFromFatalError() throws {
        let message = "Output notice (DeviceChanged): default output device changed. Playback continues."
        let data = try JSONSerialization.data(withJSONObject: ["path": "/fixture.wav", "title": "Fixture", "format": "WAV", "output_notice": message])
        let text = try JSONDecoder().decode(SnapshotText.self, from: data)
        XCTAssertEqual(text.output_notice, message)
        XCTAssertNil(text.error)
        var snapshot = PlaybackSnapshot()
        snapshot.state = 2; snapshot.outputNotice = text.output_notice
        XCTAssertTrue(snapshot.needsRefresh(expected: 0))
        XCTAssertEqual(snapshot.stateLabel, "Playing")
    }
}

extension PlaybackSnapshotTests {
    func testTransportRefreshTightensOnlyNearEOFOrPendingCommands() {
        var s=PlaybackSnapshot();s.state=2;s.duration=45;s.position=10;s.acknowledged=4
        XCTAssertEqual(s.refreshMilliseconds(expected:4),250)
        s.position=44.7;XCTAssertEqual(s.refreshMilliseconds(expected:4),100)
        s.state=3;XCTAssertEqual(s.refreshMilliseconds(expected:4),1000)
        XCTAssertEqual(s.refreshMilliseconds(expected:5),100)
        s.state=4;XCTAssertFalse(s.needsRefresh(expected:4))
    }
}
