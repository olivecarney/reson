import XCTest
import Darwin
@testable import Reson

final class ArtworkMaintenanceTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func name(_ n: Int, negative: Bool = false) -> String {
        String(format: "%064x", n) + (negative ? ".none" : "-80.png")
    }
    @discardableResult func file(_ n: Int, size: Int = 100, age: TimeInterval = 100, negative: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(name(n, negative: negative))
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size)); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path)
        return url
    }
    func testThresholdOldestAndFilenameTieBreak() async throws {
        for n in [3, 2, 1] { try file(n) }
        let date = Date(timeIntervalSince1970: 100)
        for n in 1...3 { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: root.appendingPathComponent(name(n)).path) }
        let cache = ArtworkCache(directory: root, diskCeiling: 300, diskTarget: 200)
        let below = await cache.maintain(force: true)
        XCTAssertEqual(below?.removedBytes, 0)
        try file(4, age: 50)
        let above = await cache.maintain(force: true)
        XCTAssertEqual(above?.beforeBytes, 400); XCTAssertEqual(above?.afterBytes, 200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(1)).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(2)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(3)).path))
        await cache.shutdown()
    }
    func testSafetyUnexpectedDirectoriesSymlinksAndNegativeMarkers() async throws {
        let outside = root.appendingPathComponent("outside")
        try Data(repeating: 1, count: 100).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(name(1)), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name(2)), withIntermediateDirectories: false)
        try Data([1]).write(to: root.appendingPathComponent("unrelated.png"))
        try file(3, negative: true); try file(4)
        let cache = ArtworkCache(directory: root, diskCeiling: 150, diskTarget: 0)
        let result = await cache.maintain(force: true)
        XCTAssertEqual(result?.removedBytes, 200)
        XCTAssertEqual(try Data(contentsOf: outside).count, 100)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(1)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(2)).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("unrelated.png").path))
        await cache.shutdown()
        let link = root.appendingPathComponent("linked-cache")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let linked = ArtworkCache(directory: link)
        let rejected = await linked.maintain(force: true)
        XCTAssertNil(rejected); await linked.shutdown()
    }
    func testSymlinkedParentCannotRedirectMaintenance() async throws {
        let actual = root.appendingPathComponent("actual/cache")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        let victim = actual.appendingPathComponent(name(1))
        try Data([1]).write(to: victim)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual.deletingLastPathComponent())
        let cache = ArtworkCache(directory: alias.appendingPathComponent("cache"), diskCeiling: 0, diskTarget: 0)
        let result = await cache.maintain(force: true)
        XCTAssertNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
        await cache.shutdown()
    }
    func testThrottlePersistenceForceMissingAndShutdown() async throws {
        let cache = ArtworkCache(directory: root)
        let first = await cache.maintain()
        XCTAssertNotNil(first)
        let throttled = await cache.maintain()
        XCTAssertNil(throttled)
        await cache.shutdown()
        let reopened = ArtworkCache(directory: root)
        let persisted = await reopened.maintain()
        XCTAssertNil(persisted)
        let forced = await reopened.maintain(force: true)
        XCTAssertNotNil(forced)
        await reopened.shutdown()
        let closed = await reopened.maintain(force: true)
        XCTAssertNil(closed)
        for path in [root.appendingPathComponent("missing"), try file(9)] {
            let invalid = ArtworkCache(directory: path)
            let result = await invalid.maintain(force: true)
            XCTAssertNil(result); await invalid.shutdown()
        }
    }
    func testProductionLimitsWithSparseFiles() async throws {
        try file(1, size: 128 * 1024 * 1024, age: 300)
        try file(2, size: 128 * 1024 * 1024, age: 200)
        let cache = ArtworkCache(directory: root)
        let exact = await cache.maintain(force: true)
        XCTAssertEqual(exact?.removedBytes, 0)
        try file(3, size: 1024 * 1024, age: 100)
        let pruned = await cache.maintain(force: true)
        XCTAssertEqual(pruned?.beforeBytes, 257 * 1024 * 1024)
        XCTAssertEqual(pruned?.afterBytes, 129 * 1024 * 1024)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(1)).path))
        await cache.shutdown()
    }
    func testInitialThumbnailDoesNotAdmitDirectoryScan() async throws {
        try file(1); try file(2)
        let source = root.appendingPathComponent("source.flac")
        try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
        var clockReads = 0
        let cache = ArtworkCache(directory: root, diskCeiling: 150, diskTarget: 100, now: { clockReads += 1; return Date() })
        _ = await cache.thumbnail(path: source.path)
        _ = await cache.thumbnail(path: source.path)
        // Shutdown drains any admitted slice without an arbitrary sleep.
        await cache.shutdown()
        XCTAssertEqual(clockReads, 0, "Startup requests must not even enter maintenance admission")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".maintenance-v1").path))
    }
    func testRoutineRequestsEventuallyMaintainAfterADay() async throws {
        var date = Date()
        let cache = ArtworkCache(directory: root, diskCeiling: 150, diskTarget: 100, opportunisticDelay: 0, now: { date })
        _ = await cache.maintain()
        try file(1); try file(2)
        date = date.addingTimeInterval(24 * 60 * 60 - 1)
        let early = await cache.maintain()
        XCTAssertNil(early)
        date = date.addingTimeInterval(2)
        let source = root.appendingPathComponent("source.flac")
        try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
        _ = await cache.thumbnail(path: source.path)
        // Joining/queuing routine admission waits for the opportunistic operation.
        _ = await cache.maintain()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(name(1)).path))
        await cache.shutdown()
    }
    func testRequestsPublishNewFilesDuringIncrementalMaintenanceAndShutdown() async throws {
        for n in 1...5000 { try file(n, size: 1) }
        let admitted = expectation(description: "maintenance admitted")
        let source = root.appendingPathComponent("source.flac")
        try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
        var first = true // Closure runs only on the cache queue.
        let cache = ArtworkCache(directory: root, diskCeiling: 0, diskTarget: 0, now: {
            let date = Date()
            if first { first = false; admitted.fulfill() }
            return date
        }, extract: { url in
            // Replace a candidate between scan slices, before eviction.
            try? Data([2, 3]).write(to: self.root.appendingPathComponent(self.name(1)), options: .atomic)
            return EmbeddedArtwork.read(url)
        })
        let maintenance = Task { await cache.maintain(force: true) }
        await fulfillment(of: [admitted], timeout: 5)
        let writing = try file(6000, size: 1, negative: true)
        let writer = try FileHandle(forWritingTo: writing)
        let image = await cache.thumbnail(path: source.path)
        XCTAssertEqual(image?.width, 80)
        let result = await maintenance.value
        XCTAssertNotNil(result)
        try writer.write(contentsOf: Data([4, 5])); try writer.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: writing.path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(name(1))), Data([2, 3]))
        let images = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" && $0.lastPathComponent != name(1) }
        XCTAssertEqual(images.count, 1, "A thumbnail atomically published after maintenance admission must survive")
        // A second active scan is cancelled by terminal shutdown; callers resume.
        let inFlight = Task { await cache.maintain(force: true) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await cache.thumbnail(path: source.path)
        }
        await cache.shutdown()
        _ = await inFlight.value
        let obsolete = await cancelled.value
        XCTAssertNil(obsolete)
    }
    func testDeletionFailuresAreNonfatalAndMarkerSymlinkDoesNotWriteOutside() async throws {
        let outside = root.appendingPathComponent("outside")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".maintenance-v1"), withDestinationURL: outside)
        try file(1)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let cache = ArtworkCache(directory: root, diskCeiling: 0, diskTarget: 0)
        let result = await cache.maintain(force: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        XCTAssertEqual(result?.afterBytes, 100)
        XCTAssertEqual(try String(contentsOf: outside), "keep")
        let retried = await cache.maintain(force: true)
        XCTAssertEqual(retried?.afterBytes, 0)
        XCTAssertEqual(try String(contentsOf: outside), "keep")
        await cache.shutdown()
    }
    func testDecodedMemoryByteLimitRemainsEightMiB() async throws {
        let source = root.appendingPathComponent("source.flac")
        try ArtworkTests.flac(ArtworkTests.png(width: 384, height: 384)).write(to: source)
        let disk = root.appendingPathComponent("cache")
        var extractions = 0
        let cache = ArtworkCache(directory: disk, extract: { url in
            extractions += 1; return EmbeddedArtwork.read(url)
        })
        var paths: [String] = []
        for n in 0..<16 {
            let url = root.appendingPathComponent("track-\(n).flac")
            try FileManager.default.linkItem(at: source, to: url); paths.append(url.path)
            _ = await cache.thumbnail(path: url.path, pixels: 384)
        }
        for url in try FileManager.default.contentsOfDirectory(at: disk, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        _ = await cache.thumbnail(path: paths[0], pixels: 384)
        await cache.shutdown()
        XCTAssertEqual(extractions, 17, "Byte cost must evict before the 128-entry cap")
    }
    func testMaintenanceBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["RESON_MAINTENANCE_BENCHMARK"] != nil else {
            throw XCTSkip("Set RESON_MAINTENANCE_BENCHMARK=1 for synthetic maintenance timing")
        }
        for count in [270, 5000, 25000] {
            let disk = root.appendingPathComponent(String(count))
            try FileManager.default.createDirectory(at: disk, withIntermediateDirectories: true)
            for n in 1...count {
                let url = disk.appendingPathComponent(name(n))
                try Data().write(to: url)
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 16384); try handle.close()
            }
            let source = root.appendingPathComponent("source.flac")
            try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
            let cache = ArtworkCache(directory: disk)
            // Prime memory and finish routine maintenance before measured force.
            _ = await cache.thumbnail(path: source.path)
            _ = await cache.maintain(force: true)
            // Restore evicted synthetic entries for a reproducible over-limit run.
            for n in 1...count where !FileManager.default.fileExists(atPath: disk.appendingPathComponent(name(n)).path) {
                let url = disk.appendingPathComponent(name(n))
                try Data().write(to: url)
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 16384); try handle.close()
            }
            var freshSources: [String] = []
            for index in 0..<50 {
                let fresh = root.appendingPathComponent("fresh-\(count)-\(index).flac")
                try FileManager.default.linkItem(at: source, to: fresh); freshSources.append(fresh.path)
            }
            let work = Task { await cache.maintain(force: true) }
            var missLatencies: [Double] = []
            var latencies: [Double] = []
            for index in 0..<100 {
                let start = ProcessInfo.processInfo.systemUptime
                let image = await cache.thumbnail(path: source.path)
                XCTAssertEqual(image?.width, 80)
                latencies.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                if index % 2 == 0 {
                    let missStart = ProcessInfo.processInfo.systemUptime
                    let fresh = await cache.thumbnail(path: freshSources[index / 2])
                    XCTAssertEqual(fresh?.width, 80)
                    missLatencies.append((ProcessInfo.processInfo.systemUptime - missStart) * 1000)
                }
            }
            let measured = await work.value
            let result = try XCTUnwrap(measured)
            print("MAINTENANCE entries=\(count) enumerate_ms=\(result.enumerationSeconds * 1000) total_ms=\(result.totalSeconds * 1000) before=\(result.beforeBytes) after=\(result.afterBytes) removed=\(result.removedBytes) request_max_ms=\(latencies.max()!) request_p95_ms=\(latencies.sorted()[94]) miss_max_ms=\(missLatencies.max()!) miss_p95_ms=\(missLatencies.sorted()[47])")
            XCTAssertLessThanOrEqual(result.afterBytes, 256 * 1024 * 1024)
            await cache.shutdown()
        }
    }
    func testEvictionRegenerationAndDisplayedImageSurvives() async throws {
        let source = root.appendingPathComponent("source.flac")
        try ArtworkTests.flac(ArtworkTests.png()).write(to: source)
        let disk = root.appendingPathComponent("cache")
        let cache = ArtworkCache(directory: disk, diskCeiling: 0, diskTarget: 0)
        let displayed = await cache.thumbnail(path: source.path)
        let result = await cache.maintain(force: true)
        XCTAssertGreaterThan(result?.removedBytes ?? 0, 0)
        XCTAssertEqual(displayed?.width, 80)
        let memory = await cache.thumbnail(path: source.path)
        XCTAssertEqual(memory?.width, 80)
        await cache.shutdown()
        let reopened = ArtworkCache(directory: disk)
        let regenerated = await reopened.thumbnail(path: source.path)
        XCTAssertEqual(regenerated?.width, 80); await reopened.shutdown()
        try ArtworkTests.flac(Data([1])).write(to: source)
        let negative = ArtworkCache(directory: disk, diskCeiling: 0, diskTarget: 0)
        _ = await negative.thumbnail(path: source.path)
        _ = await negative.maintain(force: true); await negative.shutdown()
        var negativeExtractions = 0
        let absent = ArtworkCache(directory: disk, extract: { url in
            negativeExtractions += 1; return EmbeddedArtwork.read(url)
        })
        let placeholder = await absent.thumbnail(path: source.path)
        XCTAssertNil(placeholder); await absent.shutdown()
        XCTAssertEqual(negativeExtractions, 1)
    }
}
