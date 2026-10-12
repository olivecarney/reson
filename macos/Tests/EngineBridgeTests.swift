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
