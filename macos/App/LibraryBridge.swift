import Foundation
import CReson

struct LibraryTrack: Decodable {
    let id: Int64, path: String, title: String, artist: String?, album: String?, genre: String?
    let duration: Double?, sample_rate: UInt32?, channels: UInt32?, bit_depth: UInt32?, format: String
    let bpm: Double?, key: String?, missing: Bool
    var snapshot: PlaybackSnapshot {
        var value = PlaybackSnapshot()
        value.libraryID = id; value.path = path; value.title = title; value.artist = artist; value.album = album
        value.genre = genre; value.duration = duration ?? -1; value.rate = sample_rate ?? 0
        value.channels = channels ?? 0; value.bits = bit_depth ?? 0; value.format = format
        value.bpm = bpm; value.key = key; value.missing = missing
        return value
    }
}
struct LibraryPage: Decodable { let tracks: [LibraryTrack], revision: UInt64 }
struct LibraryReply: Decodable { let error: String? }
struct LibraryStatus: Decodable {
    let busy: Bool, revision: UInt64, summary: Summary
    struct Summary: Decodable { let visited: UInt64, indexed: UInt64, failed: UInt64, cancelled: Bool, error: String? }
}
struct LibraryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
// Separate queue and handle: database calls and shutdown cannot occupy the playback queue.
final class LibraryBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "reson.library.bridge", qos: .utility)
    private let databaseURL: URL?
    private var handle: OpaquePointer?
    private var closed = false
    init(databaseURL: URL? = nil) { self.databaseURL = databaseURL }
    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
    private func library() throws -> OpaquePointer {
        guard !closed else { throw BridgeError.closed }
        if let handle { return handle }
        let url: URL
        if let databaseURL { url = databaseURL }
        else { url = RuntimeStorage.current.database }
        let bytes = Array(url.path.utf8)
        var created: OpaquePointer?
        let code = bytes.withUnsafeBufferPointer { reson_library_create($0.baseAddress, $0.count, &created) }
        guard code == 0, let created else { throw LibraryError(message: "Could not open the library database (\(code)). Check folder permissions and database version.") }
        handle = created
        return created
    }
    func request<T: Decodable>(_ request: [String: Any]) async throws -> T {
        try await perform { [self] in
            let handle = try library()
            let input = [UInt8](try JSONSerialization.data(withJSONObject: request))
            let code = input.withUnsafeBufferPointer { reson_library_request(handle, $0.baseAddress, $0.count) }
            guard code == 0 else { throw LibraryError(message: "Library request failed (\(code)).") }
            var required = 0
            guard reson_library_read(handle, nil, 0, &required) == 4, required > 1, required <= 32 * 1024 * 1024 else { throw LibraryError(message: "Invalid library response.") }
            var output = [UInt8](repeating: 0, count: required)
            let read = output.withUnsafeMutableBufferPointer { reson_library_read(handle, $0.baseAddress, $0.count, &required) }
            guard read == 0 else { throw LibraryError(message: "Could not read the library response.") }
            let data = Data(output.prefix(required - 1))
            let decoder = JSONDecoder()
            if let error = try decoder.decode(LibraryReply.self, from: data).error { throw LibraryError(message: error) }
            return try decoder.decode(T.self, from: data)
        }
    }
    func shutdown() async {
        _ = try? await perform { [self] in
            guard !closed else { return }; closed = true
            if let handle { self.handle = nil; reson_library_destroy(handle) }
        }
    }
    deinit { if let handle { queue.async { reson_library_destroy(handle) } } }
}

struct PlaylistRecord: Decodable, Identifiable { let id: Int64, name: String, revision: Int64 }
struct PlaylistList: Decodable { let playlists: [PlaylistRecord] }
struct PlaylistCreated: Decodable { let playlist: PlaylistRecord, skipped: Int? }
struct PlaylistEntryRecord: Decodable {
    let id: Int64, track: LibraryTrack
    var snapshot: PlaybackSnapshot { var s=track.snapshot; s.entryID=id; if track.id==0 {s.libraryID=nil}; return s }
}
struct PlaylistPage: Decodable { let entries: [PlaylistEntryRecord], revision: Int64, library_revision: UInt64 }

struct LibrarySources: Decodable { let folders: [String], exclusions: [String] }
