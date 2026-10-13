import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Reson

final class ArtworkTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func write(_ bytes: Data, _ name: String = "track.flac") throws -> URL {
        let url = root.appendingPathComponent(name); try bytes.write(to: url); return url
    }
    func testFLACPictureAndNoArtwork() throws {
        let payload = Data([1, 2, 3, 4])
        XCTAssertEqual(EmbeddedArtwork.read(try write(Self.flac(payload))), payload)
        XCTAssertNil(EmbeddedArtwork.read(try write(Data([102, 76, 97, 67, 128, 0, 0, 0]))))
    }
    func testWAVID3APICAndUTF16Description() throws {
        let image = Data([9, 8, 7])
        for encoding: UInt8 in [0, 1, 2, 3] {
            XCTAssertEqual(EmbeddedArtwork.read(try write(Self.wav(image, encoding: encoding), "track.wav")), image)
        }
    }
    func testBoundsTruncationAndMissingSource() throws {
        XCTAssertNil(EmbeddedArtwork.read(root.appendingPathComponent("absent.flac")))
        XCTAssertNil(EmbeddedArtwork.read(try write(Self.flac(Data(repeating: 0, count: EmbeddedArtwork.maximumBytes + 1)))))
        var truncated = Self.flac(Data([1, 2, 3])); truncated.removeLast()
        XCTAssertNil(EmbeddedArtwork.read(try write(truncated)))
        XCTAssertNil(EmbeddedArtwork.read(try write(Data("RIFF\0\0\0\0WAVE".utf8), "empty.wav")))
    }
    func testCacheCreationReuseInvalidationAndCorruptRecovery() async throws {
        let url = try write(Self.flac(Self.png()))
        let directory = root.appendingPathComponent("cache")
        let cache = ArtworkCache(directory: directory)
        let first = await cache.thumbnail(path: url.path)
        XCTAssertEqual(first?.width, 80); XCTAssertEqual(first?.height, 53)
        await cache.shutdown()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "png" }.count, 1)
        let reopened = ArtworkCache(directory: directory, extract: { _ in XCTFail("Cache hit extracted source"); return nil })
        let hit = await reopened.thumbnail(path: url.path)
        XCTAssertEqual(hit?.width, 80)
        await reopened.shutdown()
        for file in files { try Data([0, 1]).write(to: file) }
        let recovered = ArtworkCache(directory: directory)
        let repaired = await recovered.thumbnail(path: url.path)
        XCTAssertEqual(repaired?.width, 80)
        let large = await recovered.thumbnail(path: url.path, pixels: 384)
        XCTAssertEqual(large?.width, 300)
        // Same path receives a different image; the old cached result must not win.
        try Self.flac(Self.png(width: 100, height: 300)).write(to: url)
        let changed = await recovered.thumbnail(path: url.path)
        XCTAssertEqual(changed?.height, 80); XCTAssertEqual(changed?.width, 27)
        await recovered.shutdown()
    }
    func testInvalidImagesDimensionsNegativeCacheAndMissingSource() async throws {
        let directory = root.appendingPathComponent("cache")
        let cache = ArtworkCache(directory: directory)
        let invalid = try write(Self.flac(Data([1, 2, 3])))
        let image = await cache.thumbnail(path: invalid.path)
        XCTAssertNil(image)
        await cache.shutdown()
        let reopened = ArtworkCache(directory: directory, extract: { _ in XCTFail("Negative cache did not survive restart"); return nil })
        let negative = await reopened.thumbnail(path: invalid.path)
        XCTAssertNil(negative)
        await reopened.shutdown()
        let bounded = ArtworkCache(directory: directory)
        let huge = try write(Self.flac(Self.png(width: 8193, height: 1)))
        let oversized = await bounded.thumbnail(path: huge.path)
        XCTAssertNil(oversized)
        let absent = await bounded.thumbnail(path: root.appendingPathComponent("missing.wav").path)
        XCTAssertNil(absent)
        await bounded.shutdown()
    }
    func testRepeatedRequestsAndShutdownAreTerminal() async throws {
        let url = try write(Self.flac(Self.png()))
        let cache = ArtworkCache(directory: root.appendingPathComponent("cache"))
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<30 { group.addTask { await cache.thumbnail(path: url.path)?.width == 80 } }
            for await value in group { XCTAssertTrue(value) }
        }
        let inFlight = Task { await cache.thumbnail(path: url.path, pixels: 384) }
        await cache.shutdown(); _ = await inFlight.value
        let closed = await cache.thumbnail(path: url.path)
        XCTAssertNil(closed)
    }
    static func be(_ n: Int) -> Data { Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
    static func le(_ n: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }) }
    static func flac(_ image: Data) -> Data {
        var block = be(3) + be(9) + Data("image/png".utf8) + be(0)
        block += be(300) + be(200) + be(24) + be(0) + be(image.count) + image
        return Data("fLaC".utf8) + Data([134]) + be(block.count).suffix(3) + block
    }
    static func wav(_ image: Data, encoding: UInt8 = 0) -> Data {
        let description = encoding == 1 || encoding == 2 ? Data([0, 0]) : Data([0])
        let apic = Data([encoding]) + Data("image/png\0".utf8) + Data([3]) + description + image
        let frame = Data("APIC".utf8) + be(apic.count) + Data([0, 0]) + apic
        let size = Data([UInt8((frame.count >> 21) & 127), UInt8((frame.count >> 14) & 127), UInt8((frame.count >> 7) & 127), UInt8(frame.count & 127)])
        let tag = Data("ID3".utf8) + Data([3, 0, 0]) + size + frame
        let chunk = Data("id3 ".utf8) + le(tag.count) + tag + (tag.count % 2 == 1 ? Data([0]) : Data())
        return Data("RIFF".utf8) + le(4 + chunk.count) + Data("WAVE".utf8) + chunk
    }
    static func png(width: Int = 300, height: Int = 200) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return output as Data
    }
}
