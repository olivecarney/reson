import Foundation

struct QueueEntry: Identifiable {
    let id = UUID()
    var track: PlaybackSnapshot
    var row: PlaybackSnapshot { var value=track; value.queueID=id; return value }
}
// A visible list is captured once. Navigation/edits never rewrite this sequence.
struct PlaybackSession {
    private var sequence: [PlaybackSnapshot] = []
    private var cursor = -1
    private var history: [PlaybackSnapshot] = []
    private var historyIndex = -1
    private var replaying = false
    private var pendingQueue: UUID?
    private var recorded = false
    private(set) var current: PlaybackSnapshot?
    private(set) var queue: [QueueEntry] = []
    private(set) var label = ""
    var needsBeginConfirmation: Bool { !recorded }
    var canNext: Bool { !queue.isEmpty || historyIndex+1 < history.count || cursor+1 < sequence.count }
    var canPrevious: Bool { historyIndex > 0 }
    mutating func start(_ tracks: [PlaybackSnapshot], at index: Int, label: String) -> PlaybackSnapshot? {
        guard tracks.indices.contains(index) else { return nil }
        pendingQueue=nil
        sequence=tracks; cursor=index; history=[]; historyIndex = -1; self.label=label
        current=tracks[index]; recorded=false; replaying=false
        return current
    }
    mutating func enqueue(_ tracks: [PlaybackSnapshot], next: Bool) {
        let entries=tracks.map { QueueEntry(track:$0) }
        if next { queue.insert(contentsOf:entries,at:0) } else { queue.append(contentsOf:entries) }
    }
    mutating func removeQueue(ids: [UUID]) { let set=Set(ids); queue.removeAll { set.contains($0.id) } }
    mutating func clearQueue() { queue=[] }
    mutating func moveQueue(ids: [UUID], to position: Int) -> Bool {
        let set=Set(ids)
        guard position>=0, position<=queue.count, !ids.isEmpty, set.count==ids.count, set.isSubset(of:Set(queue.map(\.id))) else {return false}
        let destination=queue.prefix(position).filter { !set.contains($0.id) }.count
        let moving=queue.filter { set.contains($0.id) }
        queue.removeAll { set.contains($0.id) }; queue.insert(contentsOf:moving,at:destination); return true
    }
    private mutating func discardPending() {
        if let pendingQueue { removeQueue(ids:[pendingQueue]) }
        pendingQueue=nil
    }
    mutating func next() -> PlaybackSnapshot? {
        discardPending(); recorded=false; replaying=false
        while let entry=queue.first {
            if entry.track.missing { queue.removeFirst(); continue }
            pendingQueue=entry.id; current=entry.track; return current
        }
        if historyIndex+1 < history.count {
            historyIndex+=1; current=history[historyIndex]; replaying=true; return current
        }
        while cursor+1 < sequence.count {
            cursor+=1
            if !sequence[cursor].missing {current=sequence[cursor]; return current}
        }
        return nil
    }
    mutating func previous() -> PlaybackSnapshot? {
        guard canPrevious else {return nil}
        pendingQueue=nil; historyIndex-=1; current=history[historyIndex]; replaying=true; recorded=false
        return current
    }
    // Queue entries are consumed only after the engine reports Playing.
    mutating func began() {
        guard !recorded, let current else {return}
        discardPending(); recorded=true
        if !replaying {
            if historyIndex+1 < history.count {history.removeSubrange((historyIndex+1)..<history.count)}
            history.append(current)
            if history.count>1000 {history.removeFirst()}
            historyIndex=history.count-1
        }
    }
    mutating func shutdown() { self=PlaybackSession() }
}
struct PlaybackCompletion {
    private var armed=false
    mutating func arm() { armed=true }
    mutating func disarm() { armed=false }
    mutating func consume(_ snapshot: PlaybackSnapshot, generation: UInt64, expected: UInt64) -> Bool {
        guard armed, snapshot.state==5, snapshot.generation>=generation, snapshot.acknowledged>=expected else {return false}
        armed=false; return true
    }
}
