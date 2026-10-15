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
    var focusRequest: UInt64 = 0
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); let table = TrackListView()
        table.style = .plain; table.rowHeight = 38; table.intercellSpacing = NSSize(width: 10, height: 0)
        table.allowsMultipleSelection=true
        table.setAccessibilityLabel(sourceID == "queue" ? "Pending queue" : "Tracks")
        table.autosaveName = "ResonTracks-" + (sourceID == "library" ? "library" : "ordered")
        table.autosaveTableColumns = true
        table.backgroundColor = .clear; table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (id,title,width) in [("art","",36.0),("title","Title",210),("artist","Artist",130),("album","Album",130),("bpm","BPM",48),("key","Key",48),("format","Format",65),("duration","Time",84)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            if id == "duration" {column.headerCell = TimeColumnHeaderCell(textCell:title)}
            column.title = title; column.headerCell.alignment = ["bpm", "duration"].contains(id) ? .right : .left; column.width = width; column.minWidth = id == "title" ? 120 : (id == "art" ? 36 : (id == "format" ? 55 : (id == "duration" ? 72 : 40)))
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
        private var librarySortDescriptors: [NSSortDescriptor] = []
        func update(_ next: TrackTable) {
            let old = parent.tracks
            let selectedIDs=table?.selectedRowIndexes.compactMap { old.indices.contains($0) ? old[$0].rowID : nil } ?? []
            let oldPlaying=parent.playingID
            let unchangedRevision=next.dataRevision != nil && next.dataRevision==parent.dataRevision
            let focusChanged=next.focusRequest != parent.focusRequest
            let sourceChanged=parent.sourceID != next.sourceID
            let refreshArtwork = parent.artworkRevision != next.artworkRevision
            let selection = next.selection
            if sourceChanged, parent.sourceID == "library" {librarySortDescriptors=table?.sortDescriptors ?? []}
            parent = next
            guard let table else { return }
            if focusChanged {
                let request=next.focusRequest, source=next.sourceID
                DispatchQueue.main.async { [weak self, weak table] in
                    guard self?.parent.focusRequest == request, self?.parent.sourceID == source else {return}
                    if let table {table.window?.makeFirstResponder(table)}
                }
            }
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
                if !changed.isEmpty, let titleColumn=table.tableColumns.firstIndex(where:{$0.identifier.rawValue == "title"}) {
                    table.reloadData(forRowIndexes:changed,columnIndexes:IndexSet(integer:titleColumn))
                }
            }
            let retained=Set(selectedIDs)
            let indexes: IndexSet
            if !sourceChanged, selection==nil || retained.contains(selection!) {
                indexes=IndexSet(next.tracks.indices.filter {retained.contains(next.tracks[$0].rowID)})
            } else if let index=next.tracks.firstIndex(where:{$0.rowID==selection}) {indexes=IndexSet(integer:index)}
            else {indexes=[]}
            if table.selectedRowIndexes != indexes {table.selectRowIndexes(indexes,byExtendingSelection:false)}
            if let selection, !next.tracks.contains(where:{$0.rowID==selection}) {
                let replacement=indexes.first.map {next.tracks[$0].rowID}
                let source=next.sourceID
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.parent.sourceID==source, self.parent.selection==selection else {return}
                    self.parent.selection=replacement
                }
            }
            if sourceChanged {table.sortDescriptors = next.sourceID == "library" ? librarySortDescriptors : []}
            for column in table.tableColumns where sourceChanged && column.identifier.rawValue != "art" {
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
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: id == "duration" ? -12 : 0),label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
                cell.textField = label
            }
            let label = cell.textField!
            switch id { case "title": label.stringValue = (track.rowID==parent.playingID ? "▶ " : "") + track.displayTitle + (track.missing ? " · Missing" : ""); case "artist": label.stringValue = track.artist ?? "—"; case "album": label.stringValue = track.album ?? "—"; case "bpm": label.stringValue = track.bpm.map { String(format: "%g", $0) } ?? "—"; case "key": label.stringValue = track.key ?? "—"; case "format": label.stringValue = track.format; case "duration": label.stringValue = timeLabel(track.duration); default: label.stringValue = "—" }
            label.font = InterfaceStyle.tableFont
            label.textColor = id == "title" ? .labelColor : .secondaryLabelColor
            if track.missing { label.textColor = .tertiaryLabelColor }
            label.alignment = ["bpm", "duration"].contains(id) ? .right : .left
            cell.toolTip = label.stringValue
            label.setAccessibilityLabel((tableColumn?.title.isEmpty == false ? tableColumn!.title : id.capitalized) + ": " + label.stringValue)
            label.lineBreakMode = .byTruncatingTail
            return cell
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            parent.sort(key, descriptor.ascending)
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table else { return }
            guard parent.tracks.indices.contains(table.selectedRow) else {parent.selection = nil; return}
            let path = parent.tracks[table.selectedRow].rowID
            if parent.selection != path { parent.selection = path }
        }
        var actionRows: [PlaybackSnapshot] {
            guard let table else {return []}
            let clicked=table.clickedRow
            let rows=clicked>=0 && !table.selectedRowIndexes.contains(clicked) ? IndexSet(integer:clicked) : table.selectedRowIndexes
            return rows.compactMap {parent.tracks.indices.contains($0) ? parent.tracks[$0] : nil}
        }
        func performRows(_ action: TrackRowAction, contextMenu: Bool = false) {
            let rows = contextMenu ? actionRows : (table?.selectedRowIndexes.compactMap {parent.tracks.indices.contains($0) ? parent.tracks[$0] : nil} ?? [])
            switch action {
            case .play: if let row=rows.first, !row.missing {parent.play(row.rowID)}
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
        @objc private func menuAction(_ item: NSMenuItem) {if let action=TrackRowAction(rawValue:item.tag) {performRows(action, contextMenu:true)}}
        @objc private func playlistAction(_ item: NSMenuItem) {if let id=item.representedObject as? Int64 {parent.addToPlaylist(actionRows,id)}}
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems(); let rows=actionRows
            func add(_ title:String,_ action:TrackRowAction,_ enabled:Bool=true) {
                let item=NSMenuItem(title:title,action:#selector(menuAction(_:)),keyEquivalent:""); item.target=self; item.tag=action.rawValue; item.isEnabled=enabled; menu.addItem(item)
            }
            menu.autoenablesItems=false
            add("Play",.play,rows.first.map {!$0.missing} ?? false)
            if parent.sourceID != "queue" {
                add("Play Next",.playNext,!rows.isEmpty); add("Add to Queue",.addQueue,!rows.isEmpty)
                let item=NSMenuItem(title:"Add to Playlist",action:nil,keyEquivalent:""); let submenu=NSMenu(); submenu.autoenablesItems=false
                for playlist in parent.playlists {
                    let child=NSMenuItem(title:playlist.name,action:#selector(playlistAction(_:)),keyEquivalent:"")
                    child.target=self; child.representedObject=playlist.id; child.isEnabled=parent.editingEnabled && !rows.isEmpty && rows.allSatisfy {$0.libraryID != nil}; submenu.addItem(child)
                }
                item.submenu=submenu; item.isEnabled = !submenu.items.isEmpty && parent.editingEnabled && !rows.isEmpty; menu.addItem(item); menu.addItem(.separator())
            }
            if parent.remove != nil {add(parent.sourceID=="queue" ? "Remove from Queue" : "Remove from Playlist",.remove,parent.editingEnabled && !rows.isEmpty)}
            if parent.move != nil {
                let ids=Set(rows.map(\.rowID))
                let indexes=IndexSet(parent.tracks.indices.filter {ids.contains(parent.tracks[$0].rowID)})
                add("Move Up (⌘⌥↑)",.moveUp,parent.editingEnabled && (indexes.first ?? 0)>0)
                add("Move Down (⌘⌥↓)",.moveDown,parent.editingEnabled && !indexes.isEmpty && (indexes.last ?? 0)+1<parent.tracks.count)
            }
            if parent.sourceID != "queue" {add("Show Queue",.showQueue)}
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
            guard parent.tracks.indices.contains(sender.clickedRow), !parent.tracks[sender.clickedRow].missing else { return }
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

private final class TimeColumnHeaderCell: NSTableHeaderCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var padded=cellFrame
        padded.size.width=max(0,cellFrame.width-12)
        super.drawInterior(withFrame:padded,in:controlView)
    }
}
