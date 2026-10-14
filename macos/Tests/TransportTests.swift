import XCTest
import AppKit
@testable import Reson

final class TransportTests: XCTestCase {
    func testScrubbingIgnoresSnapshotsAndRejectsReplacement() {
        var timeline = PlaybackTimeline()
        var s = PlaybackSnapshot(); s.generation = 1; s.state = 2; s.duration = 90; s.position = 10
        timeline.begin(s); timeline.update(35, snapshot: s)
        s.position = 11
        XCTAssertEqual(timeline.display(s), 35)
        XCTAssertEqual(timeline.finish(s), 35)
        XCTAssertEqual(timeline.display(s), 11)
        timeline.begin(s); timeline.update(40, snapshot: s)
        s.generation = 2; s.position = 0
        XCTAssertNil(timeline.finish(s))
        XCTAssertEqual(timeline.display(s), 0)
    }
    func testReplacementDuringAnExistingDragCannotStartANewSeek() {
        var timeline=PlaybackTimeline();var s=PlaybackSnapshot();s.generation=1;s.state=2;s.duration=90
        timeline.begin(s);timeline.update(30,snapshot:s)
        timeline.cancel();s.generation=2
        timeline.update(45,snapshot:s)
        XCTAssertNil(timeline.finish(s))
    }
    func testUnknownDurationAndStopDisableSeek() {
        var timeline = PlaybackTimeline(); var s = PlaybackSnapshot(); s.state = 2
        timeline.begin(s); XCTAssertNil(timeline.finish(s))
        s.duration = 80; s.state = 4
        XCTAssertFalse(s.canSeek)
        s.state = 3; XCTAssertTrue(s.canSeek)
    }
    func testOutputUnavailableAndConversionPresentation() {
        var s = PlaybackSnapshot(); s.rate = 44100; s.channels = 1; s.outputRate = 48000; s.outputChannels = 2
        XCTAssertTrue(s.convertsOutput)
        s.rate = 48000; s.channels = 2; XCTAssertFalse(s.convertsOutput)
        let selection = OutputSelection(devices: [], preferred: "missing")
        XCTAssertEqual(selection.label, "Unavailable output")
    }
}

@MainActor final class TransportModelTests: XCTestCase {
    func testVolumePersistsAndZeroUnmuteRestoresPreviousGain() async throws {
        let name="reson-test-\(UUID())"; let defaults=try XCTUnwrap(UserDefaults(suiteName:name)); defer {defaults.removePersistentDomain(forName:name)}
        let model=PlayerModel(settings:defaults)
        XCTAssertEqual(model.volume,1)
        model.setVolume(0.37); model.toggleMute(); XCTAssertTrue(model.muted)
        model.toggleMute(); XCTAssertEqual(model.volume,0.37)
        model.setVolume(0); model.toggleMute(); XCTAssertFalse(model.muted); XCTAssertEqual(model.volume,0.37)
        model.setVolume(Double.nan); XCTAssertEqual(model.volume,0.37)
        model.setVolume(9); XCTAssertEqual(model.volume,1)
        model.setVolume(0.37); model.toggleMute()
        await model.shutdown()
        let reopened=PlayerModel(settings:defaults)
        XCTAssertEqual(reopened.volume,0.37); XCTAssertTrue(reopened.muted)
        await reopened.shutdown()
    }
    func testAcknowledgedGainReconcilesRejectedOptimisticControls() async throws {
        let name="reson-gain-\(UUID())";let defaults=try XCTUnwrap(UserDefaults(suiteName:name));defer {defaults.removePersistentDomain(forName:name)}
        let model=PlayerModel(settings:defaults);model.volume=0.9;model.muted=false
        var snapshot=PlaybackSnapshot();snapshot.volume=0.4;snapshot.muted=true
        model.reconcileGain(snapshot)
        XCTAssertEqual(model.volume,0.4);XCTAssertTrue(model.muted)
        XCTAssertEqual(defaults.double(forKey:"playbackVolume"),0.4);XCTAssertTrue(defaults.bool(forKey:"playbackMuted"))
        await model.shutdown()
    }
    func testNativeKeyboardSliderCommitsOnceAndIsAccessible() {
        var began=0, finished=0; var position=0.0
        let view=TimelineSlider(value:0,duration:60,enabled:true,begin:{began+=1},update:{position=$0},finish:{finished+=1})
        let coordinator=view.makeCoordinator(); let slider=ScrubSlider(); slider.maxValue=60; slider.doubleValue=25
        coordinator.changed(slider)
        XCTAssertEqual(position,25); XCTAssertEqual(began,1); XCTAssertEqual(finished,1)
    }
    func testFocusedTimelineArrowKeysCommitFiveSecondSeek() {
        _ = NSApplication.shared
        var committed=0.0
        let view=TimelineSlider(value:10,duration:60,enabled:true,begin:{},update:{committed=$0},finish:{})
        let coordinator=view.makeCoordinator(); let slider=ScrubSlider(); slider.minValue=0; slider.maxValue=60; slider.doubleValue=10
        slider.target=coordinator; slider.action=#selector(TimelineSlider.Coordinator.changed(_:))
        let right=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"\u{F703}",charactersIgnoringModifiers:"\u{F703}",isARepeat:false,keyCode:124)!
        slider.keyDown(with:right)
        XCTAssertEqual(slider.doubleValue,15)
        XCTAssertEqual(committed,15)
        XCTAssertTrue(slider.acceptsFirstResponder)
    }

}
