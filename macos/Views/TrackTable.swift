import SwiftUI
import AppKit

struct TrackTable: NSViewRepresentable {
    let tracks: [PlaybackSnapshot]
    @Binding var selection: String?
    let play: (String) -> Void
    var sort: (String, Bool) -> Void = { _, _ in }
    var artworkCache: ArtworkCache = .shared
    var artworkRevision: UInt64 = 0
    var sourceID = "library"
    var move: (([PlaybackSnapshot],Int)->Void)?
    var insert: (([Int64],Int)->Void)?
    var remove: (([PlaybackSnapshot])->Void)?
    var playNext: ([PlaybackSnapshot])->Void = {_ in}
    var addQueue: ([PlaybackSnapshot])->Void = {_ in}
    var showQueue: ()->Void = {}
    var playlists: [PlaylistRecord] = []
    var addToPlaylist: ([PlaybackSnapshot],Int64)->Void = {_,_ in}
    var playingID: String?
    var dataRevision: UInt64?
    var editingEnabled = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); let table = TrackListView()
        table.style = .plain; table.rowHeight = 48; table.intercellSpacing = NSSize(width: 10, height: 0)
        table.allowsMultipleSelection=true
        table.backgroundColor = .clear; table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id,title,width) in [("art","",36.0),("title","Title",210),("artist","Artist",130),("album","Album",130),("bpm","BPM",48),("key","Key",48),("format","Format",65),("duration","Time",64)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "title" ? 120 : (id == "art" ? 36 : 32)
            if id == "art" { column.maxWidth = 36; column.resizingMask = [] }
            if id != "art", sourceID=="library" { column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true) }
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.registerForDraggedTypes([TrackDrag.type]); table.setDraggingSourceOperationMask(.copy.union(.move),forLocal:true)
        table.rowAction = { [weak coordinator=context.coordinator] action in coordinator?.performRows(action) }
        let menu=NSMenu(); menu.delegate=context.coordinator; table.menu=menu
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick(_:))
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false; context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: TrackTable
        weak var table: NSTableView?
        init(_ parent: TrackTable) { self.parent = parent }
        private var updating = false
        func update(_ next: TrackTable) {
            let old = parent.tracks
            let selectedIDs=table?.selectedRowIndexes.compactMap { old.indices.contains($0) ? old[$0].rowID : nil } ?? []
            let oldPlaying=parent.playingID
            let unchangedRevision=next.dataRevision != nil && next.dataRevision==parent.dataRevision
            let sourceChanged=parent.sourceID != next.sourceID
            let refreshArtwork = parent.artworkRevision != next.artworkRevision
            let selection = next.selection
            parent = next
            guard let table else { return }
            updating = true
            defer { updating = false }
            let sameOrder = !sourceChanged && (unchangedRevision || (old.count == next.tracks.count && zip(old, next.tracks).allSatisfy { $0.rowID == $1.rowID }))
            if !sameOrder || table.numberOfRows != next.tracks.count {
                table.reloadData()
            } else if !unchangedRevision {
                var changed = IndexSet()
                for row in old.indices where old[row].tableContent != next.tracks[row].tableContent { changed.insert(row) }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            if refreshArtwork, let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "art" }) {
                let visible = table.rows(in: table.visibleRect)
                if visible.location != NSNotFound, visible.length > 0 {
                    let end = min(visible.location + visible.length, next.tracks.count)
                    if visible.location < end {
                        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<end), columnIndexes: IndexSet(integer: column))
                    }
                }
            }
            if oldPlaying != next.playingID {
                let changed=IndexSet(next.tracks.indices.filter { next.tracks[$0].rowID==oldPlaying || next.tracks[$0].rowID==next.playingID })
                if !changed.isEmpty {table.reloadData(forRowIndexes:changed,columnIndexes:IndexSet(integer:1))}
            }
            let retained=Set(selectedIDs)
            let indexes: IndexSet
            if !sourceChanged, selection==nil || retained.contains(selection!) {
                indexes=IndexSet(next.tracks.indices.filter {retained.contains(next.tracks[$0].rowID)})
            } else if let index=next.tracks.firstIndex(where:{$0.rowID==selection}) {indexes=IndexSet(integer:index)}
            else {indexes=[]}
            if table.selectedRowIndexes != indexes {table.selectRowIndexes(indexes,byExtendingSelection:false)}
            for column in table.tableColumns where column.identifier.rawValue != "art" {
                column.sortDescriptorPrototype=next.sourceID=="library" ? NSSortDescriptor(key:column.identifier.rawValue,ascending:true) : nil
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.tracks.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let track = parent.tracks[row]; let id = tableColumn?.identifier.rawValue ?? ""
            let identifier = NSUserInterfaceItemIdentifier(id)
            if id == "art" {
                let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ArtworkCell ?? ArtworkCell()
                cell.identifier = identifier
                cell.configure(path: track.path, cache: parent.artworkCache)
                return cell
            }
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView,
               reused.textField != nil {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = identifier
                let label = NSTextField(labelWithString: "")
                cell.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),label.trailingAnchor.constraint(equalTo: cell.trailingAnchor),label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                cell.textField = label
            }
            let label = cell.textField!
            switch id { case "title": label.stringValue = (track.rowID==parent.playingID ? "▶ " : "") + track.displayTitle + (track.missing ? " · Missing" : ""); case "artist": label.stringValue = track.artist ?? "—"; case "album": label.stringValue = track.album ?? "—"; case "bpm": label.stringValue = track.bpm.map { String(format: "%g", $0) } ?? "—"; case "key": label.stringValue = track.key ?? "—"; case "format": label.stringValue = track.format; case "duration": label.stringValue = timeLabel(track.duration); default: label.stringValue = "—" }
            label.font = .systemFont(ofSize: 12, weight: id == "title" ? .medium : .regular)
            label.textColor = id == "title" ? .labelColor : .secondaryLabelColor
            if track.missing { label.textColor = .tertiaryLabelColor }
            label.lineBreakMode = .byTruncatingTail
            return cell
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            parent.sort(key, descriptor.ascending)
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table, parent.tracks.indices.contains(table.selectedRow) else { return }
            let path = parent.tracks[table.selectedRow].rowID
            if parent.selection != path { parent.selection = path }
        }
        var actionRows: [PlaybackSnapshot] {
            guard let table else {return []}
            let clicked=table.clickedRow
            let rows=clicked>=0 && !table.selectedRowIndexes.contains(clicked) ? IndexSet(integer:clicked) : table.selectedRowIndexes
            return rows.compactMap {parent.tracks.indices.contains($0) ? parent.tracks[$0] : nil}
        }
        func performRows(_ action: TrackRowAction) {
            let rows=actionRows
            switch action {
            case .playNext: parent.playNext(rows)
            case .addQueue: parent.addQueue(rows)
            case .remove: if parent.editingEnabled {parent.remove?(rows)}
            case .moveUp, .moveDown:
                guard parent.editingEnabled, !rows.isEmpty else {return}
                let ids=Set(rows.map(\.rowID)); let indexes=parent.tracks.indices.filter {ids.contains(parent.tracks[$0].rowID)}
                guard let first=indexes.first, let last=indexes.last else {return}
                if action == .moveUp, first>0 {parent.move?(rows,first-1)}
                if action == .moveDown, last+1<parent.tracks.count {parent.move?(rows,last+2)}
            case .showQueue: parent.showQueue()
            }
        }
        @objc private func menuAction(_ item: NSMenuItem) {if let action=TrackRowAction(rawValue:item.tag) {performRows(action)}}
        @objc private func playlistAction(_ item: NSMenuItem) {if let id=item.representedObject as? Int64 {parent.addToPlaylist(actionRows,id)}}
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems(); let rows=actionRows
            func add(_ title:String,_ action:TrackRowAction,_ enabled:Bool=true) {
                let item=NSMenuItem(title:title,action:#selector(menuAction(_:)),keyEquivalent:""); item.target=self; item.tag=action.rawValue; item.isEnabled=enabled; menu.addItem(item)
            }
            menu.autoenablesItems=false
            if parent.sourceID != "queue" {
                add("Play Next",.playNext,!rows.isEmpty); add("Add to Queue",.addQueue,!rows.isEmpty)
                let item=NSMenuItem(title:"Add to Playlist",action:nil,keyEquivalent:""); let submenu=NSMenu(); submenu.autoenablesItems=false
                for playlist in parent.playlists {
                    let child=NSMenuItem(title:playlist.name,action:#selector(playlistAction(_:)),keyEquivalent:"")
                    child.target=self; child.representedObject=playlist.id; child.isEnabled=parent.editingEnabled && !rows.isEmpty && rows.allSatisfy {$0.libraryID != nil}; submenu.addItem(child)
                }
                item.submenu=submenu; menu.addItem(item); menu.addItem(.separator())
            }
            if parent.remove != nil {add(parent.sourceID=="queue" ? "Remove from Queue" : "Remove from Playlist",.remove,parent.editingEnabled && !rows.isEmpty)}
            if parent.move != nil {
                add("Move Up (⌘⌥↑)",.moveUp,parent.editingEnabled && !rows.isEmpty)
                add("Move Down (⌘⌥↓)",.moveDown,parent.editingEnabled && !rows.isEmpty)
            }
            add("Show Queue",.showQueue)
        }
        func tableView(_ tableView:NSTableView,writeRowsWith rows:IndexSet,to board:NSPasteboard)->Bool {
            let selected=rows.compactMap {parent.tracks.indices.contains($0) ? parent.tracks[$0] : nil}
            guard !selected.isEmpty, selected.count<=1000, parent.editingEnabled else {return false}
            let payload=TrackDrag(sessionID:TrackDrag.session,sourceID:parent.sourceID,rowIDs:selected.map(\.rowID),trackIDs:selected.compactMap(\.libraryID))
            guard let bytes=try? JSONEncoder().encode(payload), bytes.count<=65536 else {return false}
            board.declareTypes([TrackDrag.type],owner:nil); return board.setData(bytes,forType:TrackDrag.type)
        }
        func accepts(_ payload:TrackDrag,row:Int)->Bool {
            guard parent.editingEnabled, row>=0,row<=parent.tracks.count else {return false}
            if payload.sourceID==parent.sourceID {
                return parent.move != nil && Set(payload.rowIDs).isSubset(of:Set(parent.tracks.map(\.rowID)))
            }
            return parent.insert != nil && payload.trackIDs.count==payload.rowIDs.count
        }
        func acceptPayload(_ board:NSPasteboard,row:Int)->Bool {
            guard let payload=TrackDrag.read(board), accepts(payload,row:row) else {return false}
            if payload.sourceID==parent.sourceID {
                let ids=Set(payload.rowIDs); parent.move?(parent.tracks.filter {ids.contains($0.rowID)},row)
            } else {parent.insert?(payload.trackIDs,row)}
            return true
        }
        func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
            guard let payload=TrackDrag.read(info.draggingPasteboard), accepts(payload,row:row) else {return []}
            tableView.setDropRow(row,dropOperation:.above)
            return payload.sourceID==parent.sourceID ? .move : .copy
        }
        func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation:NSTableView.DropOperation)->Bool {acceptPayload(info.draggingPasteboard,row:row)}
        @objc func doubleClick(_ sender: NSTableView) {
            guard parent.tracks.indices.contains(sender.clickedRow) else { return }
            parent.play(parent.tracks[sender.clickedRow].rowID)
        }
    }
}
func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let value = Int(seconds); return String(format: "%d:%02d", value / 60, value % 60)
}

// Compare only values actually displayed by the table, not transport or inspector state.
private extension PlaybackSnapshot {
    var tableContent: [String] {
        [displayTitle, artist ?? "—", album ?? "—", format, timeLabel(duration), bpm.map { String(format: "%g", $0) } ?? "—", key ?? "—", String(missing)]
    }
}
