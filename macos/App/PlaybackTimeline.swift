import Foundation

struct OutputDevice: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
}
struct OutputSelection {
    let devices: [OutputDevice]
    let preferred: String?
    var label: String { preferred.map { id in devices.first { $0.id == id }?.name ?? "Unavailable output" } ?? "System Default" }
}
// Temporary drag position is owned independently of engine snapshots.
struct PlaybackTimeline {
    private var generation: UInt64?
    private var value: Double = 0
    var editing: Bool { generation != nil }
    mutating func begin(_ snapshot: PlaybackSnapshot) {
        guard snapshot.canSeek else { return }
        generation = snapshot.generation; value = snapshot.position
    }
    mutating func update(_ seconds: Double, snapshot: PlaybackSnapshot) {
        guard seconds.isFinite, snapshot.canSeek, generation == snapshot.generation else { return }
        value = min(max(seconds, 0), snapshot.duration)
    }
    func display(_ snapshot: PlaybackSnapshot) -> Double {
        generation == snapshot.generation && snapshot.canSeek ? value : snapshot.position
    }
    mutating func finish(_ snapshot: PlaybackSnapshot) -> Double? {
        defer { cancel() }
        guard generation == snapshot.generation, snapshot.canSeek else { return nil }
        return value
    }
    mutating func cancel() { generation = nil }
}
