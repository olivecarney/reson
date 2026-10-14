import XCTest
@testable import Reson

final class EngineBridgeTests: XCTestCase {
    private func assertClosed(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected terminal closed state", file: file, line: line) }
        catch BridgeError.closed {} catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }
    func testShutdownBeforeCreationIsTerminal() async {
        let bridge = EngineBridge()
        await bridge.shutdown()
        await assertClosed { _ = try await bridge.snapshot() }
        await assertClosed { _ = try await bridge.command(path: "/missing.wav") }
        for action: UInt32 in [0, 1, 2] { await assertClosed { _ = try await bridge.command(action: action) } }
    }
    func testRepeatedShutdownAfterCreationAndConcurrentShutdown() async throws {
        let bridge = EngineBridge()
        _ = try await bridge.snapshot()
        async let first: Void = bridge.shutdown()
        async let second: Void = bridge.shutdown()
        _ = await (first, second)
        await bridge.shutdown()
        await assertClosed { _ = try await bridge.snapshot() }
        await assertClosed { _ = try await bridge.command(action: 1) }
    }
    func testDeinitReleasesBridgeWithoutRetainCycle() async throws {
        var bridge: EngineBridge? = EngineBridge()
        weak var weakBridge = bridge
        _ = try await bridge?.snapshot()
        bridge = nil
        // The continuation can resume just before the queue releases its closure.
        for _ in 0..<100 {
            if weakBridge == nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(weakBridge)
    }
}

extension EngineBridgeTests {
    func testLateSupersededRequestsCannotReplaceLatestSelectionOrStop() async throws {
        let bridge=EngineBridge()
        let latest=try await bridge.command(path:"/missing-latest.wav",request:3)
        do {_=try await bridge.command(path:"/missing-old.wav",request:2);XCTFail("Superseded request was accepted")} catch BridgeError.superseded {}
        let stop=try await bridge.command(action:0,request:4)
        do {_=try await bridge.command(path:"/missing-later.wav",request:1);XCTFail("Old load overtook Stop")} catch BridgeError.superseded {}
        XCTAssertEqual(stop.sequence,latest.sequence+1)
        let snapshot=try await bridge.snapshot();XCTAssertEqual(snapshot.path,"/missing-latest.wav")
        await bridge.shutdown()
    }
}

extension EngineBridgeTests {
    func testLazyEngineRestoresMutedZeroAndRememberedVolume() async throws {
        let bridge=EngineBridge(initialVolume:0,initialMuted:true,initialPreviousVolume:0.37)
        let receipt=try await bridge.command(control:["op":"mute","value":false])
        var s=try await bridge.snapshot()
        for _ in 0..<100 where s.acknowledged < receipt.sequence {try await Task.sleep(for:.milliseconds(2));s=try await bridge.snapshot()}
        XCTAssertEqual(s.volume,0.37,accuracy:0.00001); XCTAssertFalse(s.muted)
        await bridge.shutdown()
    }
}

extension EngineBridgeTests {
    func testSavedZeroGainDoesNotUnmuteDuringEngineCreation() async throws {
        let bridge=EngineBridge(initialVolume:0,initialMuted:false,initialPreviousVolume:0.37)
        let receipt=try await bridge.command(action:0)
        var s=try await bridge.snapshot()
        for _ in 0..<100 where s.acknowledged < receipt.sequence {try await Task.sleep(for:.milliseconds(2));s=try await bridge.snapshot()}
        XCTAssertEqual(s.volume,0); XCTAssertFalse(s.muted)
        await bridge.shutdown()
    }
}
