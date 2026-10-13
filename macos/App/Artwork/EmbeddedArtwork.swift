import Foundation

// Small streaming readers keep artwork independent of both Rust workers. The
// scanner intentionally disables Symphonia visuals; no second audio probe or ABI
// image buffer is needed. RIFF data chunks are sought over, never loaded.
enum EmbeddedArtwork {
    static let maximumBytes = 8 * 1024 * 1024
    private static let metadataBudget = 32 * 1024 * 1024

    static func read(_ url: URL) -> Data? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        do {
            let size = try file.seekToEnd(); try file.seek(toOffset: 0)
            let reader = Reader(file: file, size: size)
            let magic = try reader.bytes(4)
            if magic == Data("fLaC".utf8) { return try flac(reader) }
            if magic == Data("RIFF".utf8) {
                let end = UInt64(try reader.bytes(4).integer(little: true)) + 8
                guard end <= size, try reader.bytes(4) == Data("WAVE".utf8) else { return nil }
                return try wav(reader, end: end)
            }
        } catch { return nil }
        return nil
    }

    private static func flac(_ reader: Reader) throws -> Data? {
        var budget = metadataBudget
        var fallback: Data?
        for _ in 0..<4096 {
            let header = try reader.bytes(4)
            let count = Data(header.suffix(3)).integer()
            // Oversized picture blocks are skipped without allocating them.
            if header[0] & 127 == 6, count <= maximumBytes + 65536, count <= budget {
                budget -= count
                let block = try reader.bytes(count)
                if let picture = picture(block) {
                    if picture.front { return picture.data }
                    if fallback == nil { fallback = picture.data }
                }
            } else { try reader.skip(count) }
            if header[0] & 128 != 0 { return fallback }
        }
        return fallback
    }

    private static func picture(_ data: Data) -> (data: Data, front: Bool)? {
        var cursor = Cursor(data)
        guard let type = cursor.number(), let mime = cursor.number(), mime <= 1024,
              cursor.skip(mime), let description = cursor.number(), description <= 65536,
              cursor.skip(description), cursor.skip(16), let count = cursor.number(),
              count > 0, count <= maximumBytes, let payload = cursor.take(count) else { return nil }
        return (payload, type == 3)
    }

    private static func wav(_ reader: Reader, end: UInt64) throws -> Data? {
        var budget = metadataBudget
        for _ in 0..<4096 {
            guard reader.offset + 8 <= end else { return nil }
            let header = try reader.bytes(8)
            let count = Data(header.suffix(4)).integer(little: true)
            guard UInt64(count) <= end - reader.offset else { return nil }
            let name = Data(header.prefix(4))
            if (name == Data("id3 ".utf8) || name == Data("ID3 ".utf8)), count <= maximumBytes + 65536, count <= budget {
                budget -= count
                if let image = id3(try reader.bytes(count)) { return image }
            } else { try reader.skip(count) }
            if count % 2 == 1 { try reader.skip(1) }
        }
        return nil
    }

    private static func id3(_ data: Data) -> Data? {
        guard data.count >= 10, data.prefix(3) == Data("ID3".utf8),
              [3, 4].contains(data[3]), data[5] == 0,
              let count = Data(data[6..<10]).synchsafe(), count <= data.count - 10 else { return nil }
        let version = data[3]
        var cursor = Cursor(Data(data[10..<(10 + count)]))
        var fallback: Data?
        for _ in 0..<4096 {
            guard let header = cursor.take(10) else { return fallback }
            let rawSize = Data(header[4..<8])
            guard let size = version == 4 ? rawSize.synchsafe() : rawSize.integer(), size > 0,
                  let payload = cursor.take(size) else { return fallback }
            // Reject compressed, encrypted, grouped and unsynchronised frames.
            guard header[8] == 0, header[9] == 0, header.prefix(4) == Data("APIC".utf8) else { continue }
            var picture = Cursor(payload)
            guard let encoding = picture.take(1)?.first, encoding <= 3,
                  picture.terminated(unit: 1, limit: 1024), let type = picture.take(1)?.first,
                  picture.terminated(unit: encoding == 1 || encoding == 2 ? 2 : 1, limit: 65536),
                  let image = picture.take(payload.count - picture.offset), !image.isEmpty,
                  image.count <= maximumBytes else { continue }
            if type == 3 { return image }
            if fallback == nil { fallback = image }
        }
        return fallback
    }

    private final class Reader {
        let file: FileHandle
        let size: UInt64
        var offset: UInt64 = 0
        init(file: FileHandle, size: UInt64) { self.file = file; self.size = size }
        func bytes(_ count: Int) throws -> Data {
            guard count >= 0, UInt64(count) <= size - offset,
                  let data = try file.read(upToCount: count), data.count == count else { throw ReadError.truncated }
            offset += UInt64(count); return data
        }
        func skip(_ count: Int) throws {
            guard count >= 0, UInt64(count) <= size - offset else { throw ReadError.truncated }
            offset += UInt64(count); try file.seek(toOffset: offset)
        }
    }
    private enum ReadError: Error { case truncated }
    private struct Cursor {
        let data: Data
        var offset = 0
        init(_ data: Data) { self.data = data }
        mutating func take(_ count: Int) -> Data? {
            guard count >= 0, count <= data.count - offset else { return nil }
            defer { offset += count }; return Data(data[offset..<(offset + count)])
        }
        mutating func number() -> Int? { take(4)?.integer() }
        mutating func skip(_ count: Int) -> Bool { take(count) != nil }
        mutating func terminated(unit: Int, limit: Int) -> Bool {
            let end = offset + min(limit, data.count - offset)
            while offset + unit <= end {
                let zero = data[offset] == 0 && (unit == 1 || data[offset + 1] == 0)
                offset += unit
                if zero { return true }
            }
            return false
        }
    }
}
private extension Data {
    func integer(little: Bool = false) -> Int {
        (little ? Array(reversed()) : Array(self)).reduce(0) { ($0 << 8) | Int($1) }
    }
    func synchsafe() -> Int? {
        guard count == 4, allSatisfy({ $0 < 128 }) else { return nil }
        return reduce(0) { ($0 << 7) | Int($1) }
    }
}
