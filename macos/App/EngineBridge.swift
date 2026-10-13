import Foundation
import CReson

struct PlaybackSnapshot: Equatable {
    var entryID: Int64?
    var queueID: UUID?
    var rowID: String { queueID.map { "q:\($0)" } ?? entryID.map { "e:\($0)" } ?? path }
    var libraryID: Int64?
    var genre: String?
    var bpm: Double?
    var key: String?
    var missing = false
    var generation: UInt64 = 0
    var acknowledged: UInt64 = 0
    var state: UInt32 = 0
    var position: Double = 0
    var duration: Double = -1
    var rate: UInt32 = 0
    var channels: UInt32 = 0
    var bits: UInt32 = 0
    var path = ""
    var title = ""
    var artist: String?
    var album: String?
    var format = ""
    var failureKind: String?
    var error: String?
    var outputNotice: String?
    var outputRate: UInt32?
    var outputChannels: UInt32?
    var outputFormat: String?
    func needsRefresh(expected: UInt64) -> Bool { state == 1 || state == 2 || state == 3 || acknowledged < expected }
    func acceptable(after generation: UInt64) -> Bool { self.generation >= generation }
    var stateLabel: String { ["Ready", "Loading", "Playing", "Paused", "Stopped", "Ended", "Error"][Int(min(state, 6))] }
    var displayTitle: String { title.isEmpty ? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent : title }
}
struct SnapshotText: Decodable {
    let path: String, title: String, artist: String?, album: String?, format: String, error: String?
    let failure_kind: String?
    let output_notice: String?
    let output_rate: UInt32?, output_channels: UInt32?, output_sample_format: String?
}
enum BridgeError: LocalizedError {
    case status(Int32), closed, snapshotChanged
    var errorDescription: String? {
        switch self {
        case .closed: return "Playback engine is closed."
        case .snapshotChanged: return "Playback changed while reading its status. Try again."
        case .status(let code): return [1: "Invalid playback request.", 2: "Playback queue is full. Try again.", 3: "Playback worker is unavailable. Restart Reson.", 5: "Playback engine failed."][code] ?? "Playback error \(code)."
        }
    }
}
// All handle access, including destruction, happens exclusively on this queue.
struct PlaybackReceipt { let sequence: UInt64, generation: UInt64 }
final class EngineBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "reson.bridge")
    private var handle: OpaquePointer?
    private var sequence: UInt64 = 0
    private var closed = false // Queue-owned, terminal even if no handle was created.
    private func perform<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try operation() }) }
        }
    }
    private func engine() throws -> OpaquePointer {
        guard !closed else { throw BridgeError.closed }
        if let handle { return handle }
        var created: OpaquePointer?
        let status = reson_engine_create(&created)
        guard status == 0, let created else { throw BridgeError.status(status) }
        handle = created
        return created
    }
    func command(path: String? = nil, action: UInt32 = 0) async throws -> PlaybackReceipt {
        try await perform { [self] in
            let engine = try engine()
            let status: Int32
            if let path {
                let bytes = Array(path.utf8)
                status = bytes.withUnsafeBufferPointer { reson_engine_load(engine, $0.baseAddress, $0.count) }
            } else {
                switch action {
                case 1: status = reson_engine_play(engine)
                case 2: status = reson_engine_pause(engine)
                default: status = reson_engine_stop(engine)
                }
            }
            guard status == 0 else { throw BridgeError.status(status) }
            sequence += 1
            var scalars=ResonSnapshot(); var required=0
            let read=reson_engine_snapshot(engine,&scalars,nil,0,&required)
            guard read==4 else {throw BridgeError.status(read)}
            return PlaybackReceipt(sequence:sequence,generation:scalars.generation)
        }
    }
    func snapshot() async throws -> PlaybackSnapshot {
        try await perform { [self] in
            let engine = try engine()
            var scalars = ResonSnapshot()
            var required = 0
            let query = reson_engine_snapshot(engine, &scalars, nil, 0, &required)
            guard query == 4 else { throw BridgeError.status(query) }
            for _ in 0..<3 {
                var bytes = [UInt8](repeating: 0, count: required)
                let status = bytes.withUnsafeMutableBufferPointer {
                    reson_engine_snapshot(engine, &scalars, $0.baseAddress, $0.count, &required)
                }
                if status == 4 { continue }
                guard status == 0 else { throw BridgeError.status(status) }
                let text = try JSONDecoder().decode(SnapshotText.self, from: Data(bytes.prefix(required - 1)))
                var result = PlaybackSnapshot()
                result.generation = scalars.generation; result.acknowledged = scalars.acknowledged
                result.state = scalars.state; result.position = scalars.position_seconds; result.duration = scalars.duration_seconds
                result.rate = scalars.sample_rate; result.channels = scalars.channels; result.bits = scalars.bit_depth
                result.path = text.path; result.title = text.title; result.artist = text.artist; result.album = text.album; result.format = text.format; result.error = text.error; result.failureKind = text.failure_kind; result.outputNotice = text.output_notice
                result.outputRate = text.output_rate; result.outputChannels = text.output_channels; result.outputFormat = text.output_sample_format
                return result
            }
            throw BridgeError.snapshotChanged
        }
    }
    func shutdown() async {
        _ = try? await perform { [self] in
            guard !closed else { return }
            closed = true
            if let handle { self.handle = nil; reson_engine_destroy(handle) }
        }
    }
    // Queued work retains self until it finishes. Once deinit runs there are no
    // competing handle accesses; the fallback captures only the pointer, never self.
    deinit {
        if let handle { queue.async { reson_engine_destroy(handle) } }
    }
}
