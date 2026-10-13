import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import Darwin

// All file access, ImageIO work and memory ownership are serialized off-main.
// Cancellation prevents obsolete queued requests from touching disk. A running
// bounded read may finish, but never publishes into a cancelled UI request.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private let queue = DispatchQueue(label: "reson.artwork", qos: .utility)
    private let directory: URL
    private let extract: (URL) -> Data?
    private let lifecycle = Cancellation()
    private var memory: [String: Entry] = [:]
    private var order: [String] = []
    private var memoryBytes = 0
    private struct Entry { let image: CGImage?; let cost: Int }
    private static let maximumDimension = 8192
    private static let maximumPixels = 32 * 1024 * 1024

    init(directory: URL? = nil, extract: @escaping (URL) -> Data? = EmbeddedArtwork.read) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Reson/Artwork", isDirectory: true)
        self.extract = extract
    }
    func thumbnail(path: String, pixels: Int = 80) async -> CGImage? {
        guard !path.isEmpty, [80, 384].contains(pixels) else { return nil }
        let cancellation = Cancellation()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard !lifecycle.cancelled, !cancellation.cancelled else { continuation.resume(returning: nil); return }
                    let image = load(URL(fileURLWithPath: path), pixels: pixels)
                    continuation.resume(returning: cancellation.cancelled || lifecycle.cancelled ? nil : image)
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    func shutdown() async {
        lifecycle.cancel()
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                memory.removeAll(); order.removeAll(); memoryBytes = 0
                continuation.resume()
            }
        }
    }
    private func load(_ url: URL, pixels: Int) -> CGImage? {
        guard let identity = identity(url) else { return nil }
        let key = "\(identity)-\(pixels)"
        if let entry = memory[key] { touch(key); return entry.image }
        let cached = directory.appendingPathComponent(key + ".png")
        let absent = directory.appendingPathComponent(identity + ".none")
        if let bytes = boundedRead(cached, limit: 1024 * 1024),
           let image = decode(bytes, pixels: pixels), image.width <= pixels, image.height <= pixels {
            remember(image, key: key); return image
        }
        if let bytes = boundedRead(absent, limit: 16), bytes == Data("no-art-v1".utf8) {
            remember(nil, key: key); return nil
        }
        let bytes = extract(url)
        let image = bytes.flatMap { decode($0, pixels: pixels) }
        // A replacement/rescan during extraction must not cache an old image.
        guard identity == self.identity(url), !lifecycle.cancelled else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let image {
            let output = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                if CGImageDestinationFinalize(destination) { try? (output as Data).write(to: cached, options: .atomic) }
            }
        } else {
            try? Data("no-art-v1".utf8).write(to: absent, options: .atomic)
        }
        remember(image, key: key); return image
    }
    private func decode(_ data: Data, pixels: Int) -> CGImage? {
        guard !data.isEmpty, data.count <= EmbeddedArtwork.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= Self.maximumDimension, height <= Self.maximumDimension,
              width * height <= Self.maximumPixels else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
    private func identity(_ url: URL) -> String? {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in path.map { fstatat(AT_FDCWD, $0, &info, 0) } ?? -1 }) == 0,
              info.st_mode & S_IFMT == S_IFREG else { return nil }
        let value = "v1\n\(url.standardizedFileURL.path)\n\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func boundedRead(_ url: URL, limit: Int) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(), size <= UInt64(limit),
              (try? file.seek(toOffset: 0)) != nil else { return nil }
        return try? file.read(upToCount: limit)
    }
    private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
    private func remember(_ image: CGImage?, key: String) {
        let cost = image.map { $0.bytesPerRow * $0.height } ?? 0
        memory[key] = Entry(image: image, cost: cost); memoryBytes += cost; touch(key)
        while order.count > 128 || memoryBytes > 8 * 1024 * 1024 {
            let oldest = order.removeFirst()
            if let removed = memory.removeValue(forKey: oldest) { memoryBytes -= removed.cost }
        }
    }
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func cancel() { lock.lock(); value = true; lock.unlock() }
    }
}
