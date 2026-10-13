import XCTest
import AppKit
@testable import Reson

@MainActor
final class ArtworkPresentationTests: XCTestCase {
    func testRapidSelectionRejectsOldArtworkAndPlaybackStaysIndependent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.flac"), b = root.appendingPathComponent("b.flac")
        try ArtworkTests.flac(ArtworkTests.png(width: 300, height: 100)).write(to: a)
        try ArtworkTests.flac(ArtworkTests.png(width: 100, height: 300)).write(to: b)
        let started = expectation(description: "Old extraction started")
        let release = DispatchSemaphore(value: 0)
        var first = true // Extractor is invoked only on the cache's serial queue.
        let cache = ArtworkCache(directory: root.appendingPathComponent("cache"), extract: { url in
            if first { first = false; started.fulfill(); release.wait() }
            return EmbeddedArtwork.read(url)
        })
        let inspector = ArtworkLoader(), transport = ArtworkLoader()
        let old = Task { await inspector.load(path: a.path, pixels: 384, cache: cache) }
        await fulfillment(of: [started], timeout: 2)
        let newer = Task { await inspector.load(path: b.path, pixels: 384, cache: cache) }
        while inspector.path != b.path { await Task.yield() }
        XCTAssertNil(inspector.image)
        release.signal()
        _ = await newer.value
        _ = await old.value
        await transport.load(path: a.path, cache: cache)
        XCTAssertEqual(inspector.path, b.path); XCTAssertEqual(inspector.image?.size, NSSize(width: 100, height: 300))
        XCTAssertEqual(transport.path, a.path); XCTAssertEqual(transport.image?.size, NSSize(width: 80, height: 27))
        await inspector.load(path: "", cache: cache)
        XCTAssertNil(inspector.image); XCTAssertNotNil(transport.image)
        await cache.shutdown()
    }
}
