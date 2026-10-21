import XCTest
import CoreAudio
@testable import Reson

final class AudioRefinementIntegrationTests: XCTestCase {
    func acknowledged(_ bridge: EngineBridge, _ receipt: PlaybackReceipt) async throws -> PlaybackSnapshot {
        for _ in 0..<1000 {
            let s=try await bridge.snapshot()
            if s.acknowledged >= receipt.sequence {return s}
            try await Task.sleep(for:.milliseconds(2))
        }
        throw NSError(domain:"Reson integration timeout",code:1)
    }
    func command(_ bridge: EngineBridge, _ control: [String: Any]) async throws -> PlaybackSnapshot {
        let receipt=try await bridge.command(control:control)
        return try await acknowledged(bridge,receipt)
    }
    func defaultVolumes() -> [Float32] {
        var device=AudioDeviceID(0), size=UInt32(MemoryLayout<AudioDeviceID>.size)
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:0)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device)==noErr else {return []}
        return (0...2).compactMap { channel in
            var value=Float32(0); var size=UInt32(MemoryLayout<Float32>.size)
            var property=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyVolumeScalar,mScope:kAudioObjectPropertyScopeOutput,mElement:UInt32(channel))
            guard AudioObjectGetPropertyData(device,&property,0,nil,&size,&value)==noErr else {return nil}
            return value
        }
    }
    func testNativeSeekingGainDeviceSwitchAndUnavailableRecovery() async throws {
        guard let root=ProcessInfo.processInfo.environment["RESON_AUDIO_FIXTURES"] else {throw XCTSkip("Opt-in: generate-audio-fixtures.py and set RESON_AUDIO_FIXTURES; opens real CoreAudio with silent audio")}
        let systemVolumeBefore=defaultVolumes()
        let bridge=EngineBridge()
        do {
            _=try await command(bridge,["op":"volume","value":0.35])
            _=try await command(bridge,["op":"mute","value":true])
            var latencies:[Double]=[]
            for ext in ["wav","flac"] {
                _=try await command(bridge,["op":"mute","value":true])
                let receipt=try await bridge.command(path:root+"/silent."+ext)
                var s=try await acknowledged(bridge,receipt)
                XCTAssertEqual(s.state,2,s.error ?? ""); XCTAssertEqual(s.rate,44100); XCTAssertEqual(s.duration,8,accuracy:0.001)
                XCTAssertNotNil(s.outputRate); XCTAssertNotNil(s.outputFormat)
                s=try await acknowledged(bridge,bridge.command(action:2))
                XCTAssertEqual(s.state,3)
                for seconds in [5.0,1.5,0,7.999,3.0] {
                    let start=ContinuousClock.now
                    s=try await command(bridge,["op":"seek","seconds":seconds,"generation":s.generation])
                    latencies.append(Double(start.duration(to:.now).components.attoseconds)/1e15 + Double(start.duration(to:.now).components.seconds)*1000)
                    XCTAssertNil(s.operationError); XCTAssertEqual(s.state,3); XCTAssertEqual(s.position,seconds,accuracy:1/44100)
                }
                s=try await command(bridge,["op":"devices"])
                XCTAssertFalse(s.devices.isEmpty)
                let device=try XCTUnwrap(s.devices.first)
                for n in 0..<10 {
                    s=try await command(bridge,["op":"device","id":n%2==0 ? device.id as Any : NSNull()])
                    XCTAssertEqual(s.state,3,s.error ?? ""); XCTAssertEqual(s.position,3,accuracy:1/44100)
                    XCTAssertEqual(s.volume,0.35,accuracy:0.00001); XCTAssertTrue(s.muted)
                    XCTAssertNotNil(s.outputRate)
                }
                s=try await command(bridge,["op":"device","id":"reson-test-unavailable"])
                XCTAssertEqual(s.state,6); XCTAssertEqual(s.failureKind,"output"); XCTAssertNil(s.outputRate)
                s=try await command(bridge,["op":"device","id":NSNull()])
                XCTAssertEqual(s.state,3,s.error ?? ""); XCTAssertEqual(s.position,3,accuracy:1/44100)
                s=try await command(bridge,["op":"mute","value":false]); XCTAssertFalse(s.muted)
                s=try await acknowledged(bridge,bridge.command(action:1)); XCTAssertEqual(s.state,2)
                s=try await command(bridge,["op":"seek","seconds":2.0,"generation":s.generation]); XCTAssertEqual(s.state,2)
                s=try await acknowledged(bridge,bridge.command(action:0)); XCTAssertEqual(s.state,4)
            }
            XCTAssertEqual(defaultVolumes(),systemVolumeBefore)
            print("V04_SYSTEM_VOLUME \(systemVolumeBefore)")
            print("V04_NATIVE_SEEK_MS \(latencies)")
            await bridge.shutdown()
            do {_=try await command(bridge,["op":"devices"]);XCTFail("Closed engine accepted command")} catch BridgeError.closed {}
        } catch {await bridge.shutdown();throw error}
    }
}

@MainActor final class TransitionIntegrationTests: XCTestCase {
    func testMeasuredNativeModelQueueTransitions() async throws {
        guard let root=ProcessInfo.processInfo.environment["RESON_AUDIO_FIXTURES"] else {throw XCTSkip("Opt-in: muted original transition markers on real CoreAudio")}
        let suite="reson-transition-\(UUID())", defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
        let model=PlayerModel(databaseURL:directory.appendingPathComponent("library.db"),settings:defaults)
        model.setVolume(0)
        var a=PlaybackSnapshot(); a.path=root+"/boundary-a.flac";a.title="a"
        var b=PlaybackSnapshot(); b.path=root+"/boundary-b.flac";b.title="b"
        var c=PlaybackSnapshot(); c.path=root+"/boundary-48k.wav";c.title="c"
        model.tracks=[a,b,c];model.playRow(a.rowID);model.enqueue([b,b],next:true)
        var starts:[ContinuousClock.Instant]=[], generations:[UInt64]=[], paths:[String]=[]
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        while .now < deadline {
            if model.playback.state==6 {XCTFail(model.playback.error ?? "output failed");break}
            if model.playback.state==2 && generations.last != model.playback.generation {starts.append(.now);generations.append(model.playback.generation);paths.append(model.playback.path)}
            if model.playback.state==5 && !model.canNext && model.playback.path==c.path {break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertEqual(paths,[a.path,b.path,b.path,b.path,c.path])
        XCTAssertTrue(model.session.queue.isEmpty)
        for (before,after) in zip(starts,starts.dropFirst()) {let d=before.duration(to:after);print("V04_MODEL_START_INTERVAL_MS \(Double(d.components.seconds)*1000+Double(d.components.attoseconds)/1e15)")}
        await model.shutdown()
    }
    func testNativeGainBackpressureKeepsVisualStateAndQueueConsistent() async throws {
        guard let root=ProcessInfo.processInfo.environment["RESON_AUDIO_FIXTURES"] else {throw XCTSkip("Opt-in: silent gain burst during a real output switch")}
        let suite="reson-gain-pressure-\(UUID())", defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
        let model=PlayerModel(databaseURL:directory.appendingPathComponent("library.db"),settings:defaults)
        var row=PlaybackSnapshot();row.path=root+"/silent.wav";model.tracks=[row];model.playRow(row.rowID)
        for _ in 0..<1000 {if model.playback.state==2 {break};try await Task.sleep(for:.milliseconds(2))}
        XCTAssertEqual(model.playback.state,2,model.playback.error ?? "");model.enqueue([row,row],next:true)
        model.refreshDevices()
        for _ in 0..<1000 {if !model.playback.devices.isEmpty {break};try await Task.sleep(for:.milliseconds(2))}
        let device=try XCTUnwrap(model.playback.devices.first)
        model.selectOutput(device.id)
        for n in 0..<40 {model.setVolume(Double(n)/39)}
        for _ in 0..<2000 {
            if model.playback.preferredDevice==device.id && abs(model.volume-model.playback.volume)<0.000001 {break}
            try await Task.sleep(for:.milliseconds(2))
        }
        XCTAssertEqual(model.playback.state,2,model.playback.error ?? "")
        XCTAssertEqual(model.volume,model.playback.volume,accuracy:0.000001)
        XCTAssertEqual(model.session.queue.count,2)
        XCTAssertEqual(model.volume,defaults.double(forKey:"playbackVolume"),accuracy:0.000001)
        print("V04_GAIN_BURST_UI=\(model.volume) ENGINE=\(model.playback.volume)")
        await model.shutdown()
    }

}
