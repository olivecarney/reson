import XCTest
@testable import Reson

final class ArtworkBenchmarkTests: XCTestCase {
    // Opt-in workload: original image/audio metadata, no personal library access.
    func testSyntheticArtworkWorkloads() async throws {
        guard let output = ProcessInfo.processInfo.environment["RESON_ARTWORK_BENCHMARK"] else { throw XCTSkip("Set RESON_ARTWORK_BENCHMARK to an isolated output directory") }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("fixture.flac")
        try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
        for count in [270, 5000, 25000] {
            let folder = root.appendingPathComponent("\(count)")
            let directory = root.appendingPathComponent("cache-\(count)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var urls: [URL] = []
            for i in 0..<count {
                let url = folder.appendingPathComponent("\(i).flac")
                if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.linkItem(at: source, to: url) }
                urls.append(url)
            }
            let cache = ArtworkCache(directory: directory)
            let start = ContinuousClock.now
            for url in urls { let image = await cache.thumbnail(path: url.path); XCTAssertEqual(image?.width, 80) }
            let miss = start.duration(to: .now)
            await cache.shutdown()
            let reopened = ArtworkCache(directory: directory)
            let hitStart = ContinuousClock.now
            for url in urls { let image = await reopened.thumbnail(path: url.path); XCTAssertEqual(image?.width, 80) }
            let hits = hitStart.duration(to: .now)
            let largeStart = ContinuousClock.now
            for url in urls.prefix(30) { _ = await reopened.thumbnail(path: url.path, pixels: 384) }
            let large = largeStart.duration(to: .now)
            await reopened.shutdown()
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            let bytes = try files.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
            print("ARTWORK_BENCH tracks=\(count) miss=\(miss) diskHit=\(hits) inspector30=\(large) cacheBytes=\(bytes)")
        }
    }
}
