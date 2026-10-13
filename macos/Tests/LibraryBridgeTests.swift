import XCTest
@testable import Reson
final class LibraryBridgeTests: XCTestCase {
    func testEmptyReopenAndTerminalShutdown() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = LibraryBridge(databaseURL: directory.appendingPathComponent("library.db"))
        let first: LibraryPage = try await bridge.request(["op": "query", "limit": 500])
        XCTAssertTrue(first.tracks.isEmpty)
        await bridge.shutdown()
        do { let _: LibraryPage = try await bridge.request(["op": "query"]); XCTFail("Closed bridge reopened") }
        catch { }
        let reopened = LibraryBridge(databaseURL: directory.appendingPathComponent("library.db"))
        let second: LibraryPage = try await reopened.request(["op": "query"])
        XCTAssertTrue(second.tracks.isEmpty)
        await reopened.shutdown()
    }
    func testPersistentImportAcrossBridgeInstances() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("tests/fixtures/pcm16-44100-1.wav")
        let music = directory.appendingPathComponent("音 楽")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: music.appendingPathComponent("song.wav"))
        let database = directory.appendingPathComponent("library.db")
        let bridge = LibraryBridge(databaseURL: database)
        let _: LibraryReply = try await bridge.request(["op": "import", "path": music.path])
        for _ in 0..<100 {
            let status: LibraryStatus = try await bridge.request(["op": "status"])
            if !status.busy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await bridge.shutdown()
        let reopened = LibraryBridge(databaseURL: database)
        let page: LibraryPage = try await reopened.request(["op": "query"])
        XCTAssertEqual(page.tracks.count, 1)
        XCTAssertEqual(page.tracks.first?.snapshot.displayTitle, "song")
        await reopened.shutdown()
    }
}

extension LibraryBridgeTests {
    func testDiagnosticLibraryStartupAndWarmQuery() async throws {
        guard let root = ProcessInfo.processInfo.environment["RESON_BENCHMARK_DATABASES"] else { return }
        for count in [270, 5000, 25000] {
            let bridge = LibraryBridge(databaseURL: URL(fileURLWithPath: root).appendingPathComponent("\(count).db"))
            let first = Date()
            let page: LibraryPage = try await bridge.request(["op": "query", "limit": 500])
            let firstMS = Date().timeIntervalSince(first) * 1000
            XCTAssertEqual(page.tracks.count, min(count, 500))
            var timings: [Double] = []
            for _ in 0..<30 {
                let start = Date()
                let _: LibraryPage = try await bridge.request(["op": "query", "search": "Artist 42", "limit": 500])
                timings.append(Date().timeIntervalSince(start) * 1000)
            }
            timings.sort()
            print("NATIVE_BRIDGE count=\(count) first_page_ms=\(firstMS) warm_search_median_ms=\(timings[15])")
            await bridge.shutdown()
        }
    }
}
