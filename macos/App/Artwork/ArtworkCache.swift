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
    private let diskCeiling: Int64
    private let diskTarget: Int64
    private let opportunisticDelay: TimeInterval
    private var opportunisticEligibleAt: TimeInterval?
    private let now: () -> Date
    private var lastMaintenance: Date?
    private var markerLoaded = false
    private var maintenance: Maintenance?
    private let maintenanceInterval: TimeInterval = 24 * 60 * 60
    private let extract: (URL) -> Data?
    private let lifecycle = Cancellation()
    private var memory: [String: Entry] = [:]
    private var order: [String] = []
    private var memoryBytes = 0
    private struct Entry { let image: CGImage?; let cost: Int }
    private static let maximumDimension = 8192
    private static let maximumPixels = 32 * 1024 * 1024

    init(directory: URL? = nil, diskCeiling: Int64 = 256 * 1024 * 1024, diskTarget: Int64 = 192 * 1024 * 1024, opportunisticDelay: TimeInterval = 5, now: @escaping () -> Date = Date.init, extract: @escaping (URL) -> Data? = EmbeddedArtwork.read) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/Reson/Artwork", isDirectory: true)
        self.extract = extract
        self.diskCeiling = max(0, diskCeiling)
        self.diskTarget = max(0, min(diskTarget, diskCeiling))
        self.now = now
        self.opportunisticDelay = max(0, opportunisticDelay)
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
                    // Admission follows a completed request; initialization never scans.
                    queue.async { [self] in
                        let uptime = ProcessInfo.processInfo.systemUptime
                        if opportunisticEligibleAt == nil { opportunisticEligibleAt = uptime + opportunisticDelay }
                        guard uptime >= opportunisticEligibleAt! else { return }
                        startMaintenance(force: false, completion: nil)
                    }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    func shutdown() async {
        lifecycle.cancel()
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let work = maintenance { finishMaintenance(work, completed: false) }
                memory.removeAll(); order.removeAll(); memoryBytes = 0
                continuation.resume()
            }
        }
    }
    struct MaintenanceResult {
        let beforeBytes: Int64
        let afterBytes: Int64
        let enumerationSeconds: TimeInterval
        let totalSeconds: TimeInterval
        var removedBytes: Int64 { beforeBytes - afterBytes }
    }
    // Internal explicit entry point for tests/development. Production requests
    // opportunistically admit the same operation, at most once per day.
    func maintain(force: Bool = false) async -> MaintenanceResult? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                startMaintenance(force: force) { continuation.resume(returning: $0) }
            }
        }
    }
    private struct Candidate {
        let name: String
        let info: stat
        func precedes(_ other: Candidate) -> Bool {
            if info.st_mtimespec.tv_sec != other.info.st_mtimespec.tv_sec {
                return info.st_mtimespec.tv_sec < other.info.st_mtimespec.tv_sec
            }
            if info.st_mtimespec.tv_nsec != other.info.st_mtimespec.tv_nsec {
                return info.st_mtimespec.tv_nsec < other.info.st_mtimespec.tv_nsec
            }
            return name < other.name
        }
    }
    private final class Maintenance {
        let fd: Int32
        let stream: UnsafeMutablePointer<DIR>
        let started = ProcessInfo.processInfo.systemUptime
        let cutoff: Date
        var enumerationSeconds: TimeInterval = 0
        var enumerating = true
        var heap: [Candidate] = []
        var before: Int64 = 0
        var remaining: Int64 = 0
        var completions: [(MaintenanceResult?) -> Void] = []
        init(fd: Int32, stream: UnsafeMutablePointer<DIR>, cutoff: Date) {
            self.fd = fd; self.stream = stream; self.cutoff = cutoff
        }
        deinit { closedir(stream); close(fd) }
        // Build the oldest-first heap incrementally, avoiding a whole-directory
        // sort occupying the serial queue after enumeration.
        func insert(_ entry: Candidate) {
            heap.append(entry)
            var index = heap.count - 1
            while index > 0 {
                let parent = (index - 1) / 2
                guard heap[index].precedes(heap[parent]) else { break }
                heap.swapAt(index, parent); index = parent
            }
        }
        func pop() -> Candidate? {
            guard !heap.isEmpty else { return nil }
            let first = heap[0], last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var index = 0
                while index * 2 + 1 < heap.count {
                    var child = index * 2 + 1
                    if child + 1 < heap.count, heap[child + 1].precedes(heap[child]) { child += 1 }
                    guard heap[child].precedes(heap[index]) else { break }
                    heap.swapAt(index, child); index = child
                }
            }
            return first
        }
    }
    private static func recognized(_ name: String) -> Bool {
        let suffix: String
        if name.hasSuffix("-80.png") { suffix = "-80.png" }
        else if name.hasSuffix("-384.png") { suffix = "-384.png" }
        else if name.hasSuffix(".none") { suffix = ".none" }
        else { return false }
        let hash = name.dropLast(suffix.count).utf8
        return hash.count == 64 && hash.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func openMaintenanceDirectory() -> Int32 {
        // Reject symlinks in ancestors as well as the leaf. Walk with pinned
        // descriptors so a concurrent rename cannot redirect a later component.
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        // Foundation presents macOS temporary URLs through the system /var
        // alias even after resolvingSymlinksInPath. Use its fixed physical
        // spelling (likewise /tmp), without following any filesystem link.
        var components = Array(directory.pathComponents.dropFirst())
        if components.first == "var" || components.first == "tmp" { components.insert("private", at: 0) }
        for component in components {
            guard component != ".", component != ".." else { close(fd); return -1 }
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { return -1 }
            fd = next
        }
        return fd
    }
    private func startMaintenance(force: Bool, completion: ((MaintenanceResult?) -> Void)?) {
        guard !lifecycle.cancelled else { completion?(nil); return }
        if let work = maintenance {
            if let completion { work.completions.append(completion) }
            return
        }
        let date = now()
        if !force, let lastMaintenance, date.timeIntervalSince(lastMaintenance) < maintenanceInterval {
            completion?(nil); return
        }
        // Pin the cache directory. Relative stat/unlink/marker operations cannot
        // escape through a replaced path or an entry symlink. Never recurse.
        let fd = openMaintenanceDirectory()
        guard fd >= 0 else {
            lastMaintenance = date // Avoid retrying a missing/unreadable root on every request.
            completion?(nil); return
        }
        if !markerLoaded {
            markerLoaded = true
            let marker = openat(fd, ".maintenance-v1", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            if marker >= 0 {
                var info = stat()
                var bytes = [UInt8](repeating: 0, count: 64)
                if fstat(marker, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 64 {
                    let count = read(marker, &bytes, bytes.count)
                    if count > 0, let value = Double(String(decoding: bytes.prefix(count), as: UTF8.self)), value.isFinite {
                        lastMaintenance = Date(timeIntervalSince1970: value)
                    }
                }
                close(marker)
            }
        }
        if !force, let lastMaintenance, date.timeIntervalSince(lastMaintenance) < maintenanceInterval {
            close(fd); completion?(nil); return
        }
        let enumerationFD = dup(fd)
        guard enumerationFD >= 0 else { close(fd); lastMaintenance = date; completion?(nil); return }
        guard let stream = fdopendir(enumerationFD) else {
            close(enumerationFD); close(fd); lastMaintenance = date; completion?(nil); return
        }
        let work = Maintenance(fd: fd, stream: stream, cutoff: date)
        // Suppress repeated failed attempts in this instance; persist only completion.
        lastMaintenance = date
        if let completion { work.completions.append(completion) }
        maintenance = work
        queue.async { [self] in maintenanceSlice(work) }
    }
    private func maintenanceSlice(_ work: Maintenance) {
        guard maintenance === work else { return }
        guard !lifecycle.cancelled else { finishMaintenance(work, completed: false); return }
        let start = ProcessInfo.processInfo.systemUptime
        // Both an entry count and elapsed-time budget bound ordinary batches.
        // A single OS filesystem call can still stall; no queue can prevent that.
        for _ in 0..<64 {
            if work.enumerating {
                errno = 0
                guard let entry = readdir(work.stream) else {
                    if errno != 0 { finishMaintenance(work, completed: false); return }
                    work.enumerationSeconds += ProcessInfo.processInfo.systemUptime - start
                    work.enumerating = false
                    work.remaining = work.before
                    if work.before <= diskCeiling { finishMaintenance(work, completed: true); return }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
                }
                if Self.recognized(name) {
                    var info = stat()
                    if fstatat(work.fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                       info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0 {
                        work.before += info.st_size
                        // Files published/modified after admission are protected.
                        let changed = Double(info.st_ctimespec.tv_sec) + Double(info.st_ctimespec.tv_nsec) / 1e9
                        if changed < work.cutoff.timeIntervalSince1970 {
                            work.insert(Candidate(name: name, info: info))
                        }
                    }
                }
            } else {
                guard work.remaining > diskTarget, let candidate = work.pop() else {
                    finishMaintenance(work, completed: true); return
                }
                var info = stat()
                if fstatat(work.fd, candidate.name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                   info.st_mode & S_IFMT == S_IFREG,
                   info.st_dev == candidate.info.st_dev, info.st_ino == candidate.info.st_ino,
                   info.st_size == candidate.info.st_size,
                   info.st_mtimespec.tv_sec == candidate.info.st_mtimespec.tv_sec,
                   info.st_mtimespec.tv_nsec == candidate.info.st_mtimespec.tv_nsec,
                   info.st_ctimespec.tv_sec == candidate.info.st_ctimespec.tv_sec,
                   info.st_ctimespec.tv_nsec == candidate.info.st_ctimespec.tv_nsec,
                   unlinkat(work.fd, candidate.name, 0) == 0 {
                    work.remaining -= candidate.info.st_size
                }
            }
            if ProcessInfo.processInfo.systemUptime - start >= 0.002 { break }
        }
        if work.enumerating { work.enumerationSeconds += ProcessInfo.processInfo.systemUptime - start }
        queue.async { [self] in maintenanceSlice(work) }
    }
    private func finishMaintenance(_ work: Maintenance, completed: Bool) {
        guard maintenance === work else { return }
        maintenance = nil
        var result: MaintenanceResult?
        if completed {
            let date = now()
            lastMaintenance = date
            // Create a private temporary marker and atomically rename relative
            // to the pinned directory; an existing marker symlink is replaced.
            let temporary = ".maintenance-" + UUID().uuidString
            let fd = openat(work.fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            if fd >= 0 {
                let bytes = Array(String(date.timeIntervalSince1970).utf8)
                let count = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                close(fd)
                if count == bytes.count { _ = renameat(work.fd, temporary, work.fd, ".maintenance-v1") }
                _ = unlinkat(work.fd, temporary, 0)
            }
            result = MaintenanceResult(beforeBytes: work.before, afterBytes: work.remaining,
                                       enumerationSeconds: work.enumerationSeconds,
                                       totalSeconds: ProcessInfo.processInfo.systemUptime - work.started)
        }
        for completion in work.completions { completion(result) }
        work.completions.removeAll()
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
        // An inspector request may precede the table/transport (e.g. Open File).
        // Derive the smaller image from its cached thumbnail without re-reading
        // embedded metadata. Invalid larger cache data falls back to the source.
        let larger = directory.appendingPathComponent(identity + "-384.png")
        let reused = pixels == 80 ? boundedRead(larger, limit: 1024 * 1024).flatMap { decode($0, pixels: pixels) } : nil
        let image = reused ?? extract(url).flatMap { decode($0, pixels: pixels) }
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
