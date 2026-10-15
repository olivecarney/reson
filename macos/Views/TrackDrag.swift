import AppKit

struct TrackDrag: Codable {
    static let type=NSPasteboard.PasteboardType("com.reson.local-tracks")
    static let session=UUID().uuidString
    let sessionID: String
    let sourceID: String
    let rowIDs: [String]
    let trackIDs: [Int64]
    static func read(_ board: NSPasteboard) -> TrackDrag? {
        guard let data=board.data(forType:type), data.count<=65536,
              let value=try? JSONDecoder().decode(Self.self,from:data), value.sessionID==session,
              !value.rowIDs.isEmpty, value.rowIDs.count<=1000, Set(value.rowIDs).count==value.rowIDs.count else {return nil}
        return value
    }
}
enum TrackRowAction: Int { case playNext, addQueue, remove, moveUp, moveDown, showQueue, play }
final class TrackListView: NSTableView {
    var rowAction: ((TrackRowAction)->Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command,.option,.control,.shift])==[.command,.option], [125,126].contains(event.keyCode) {
            rowAction?(event.keyCode==126 ? .moveUp : .moveDown); return
        }
        if [51,117].contains(event.keyCode), event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty {
            rowAction?(.remove); return
        }
        if [36,76].contains(event.keyCode), event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty {
            rowAction?(.play); return
        }
        super.keyDown(with:event)
    }
}
