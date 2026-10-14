import SwiftUI
import AppKit

struct PlaylistSidebar: NSViewRepresentable {
    let playlists: [PlaylistRecord]
    let selection: Int64?
    let select: (Int64)->Void
    let rename: (PlaylistRecord)->Void
    let delete: (PlaylistRecord)->Void
    let export: (PlaylistRecord)->Void
    let add: ([Int64],Int64)->Void
    var editingEnabled=true
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView(); let table=NSTableView()
        table.headerView=nil; table.style = .sourceList; table.rowHeight=30; table.backgroundColor = .clear
        table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("playlist")))
        table.delegate=context.coordinator; table.dataSource=context.coordinator; table.registerForDraggedTypes([TrackDrag.type])
        let menu=NSMenu(); menu.delegate=context.coordinator; table.menu=menu
        scroll.documentView=table; scroll.hasVerticalScroller=true; scroll.drawsBackground=false; context.coordinator.table=table
        return scroll
    }
    func updateNSView(_ view:NSScrollView,context:Context) {context.coordinator.update(self)}
    final class Coordinator:NSObject,NSTableViewDataSource,NSTableViewDelegate,NSMenuDelegate {
        var parent:PlaylistSidebar; weak var table:NSTableView?; private var updating=false
        init(_ parent:PlaylistSidebar){self.parent=parent}
        func update(_ next:PlaylistSidebar) {
            updating=true; defer {updating=false}
            let changed=parent.playlists.map(\.id) != next.playlists.map(\.id) || parent.playlists.map(\.name) != next.playlists.map(\.name)
            parent=next; guard let table else {return}
            if changed || table.numberOfRows != next.playlists.count {table.reloadData()}
            if let row=next.playlists.firstIndex(where:{$0.id==next.selection}) {table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)} else {table.deselectAll(nil)}
        }
        func numberOfRows(in tableView:NSTableView)->Int {parent.playlists.count}
        func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
            let id=NSUserInterfaceItemIdentifier("playlist")
            let cell=tableView.makeView(withIdentifier:id,owner:self) as? NSTableCellView ?? NSTableCellView()
            cell.identifier=id
            if cell.textField==nil {
                let label=NSTextField(labelWithString:""); label.translatesAutoresizingMaskIntoConstraints=false; cell.addSubview(label); cell.textField=label
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:8),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-4),label.centerYAnchor.constraint(equalTo:cell.centerYAnchor)])
                label.font = .systemFont(ofSize:13); label.lineBreakMode = .byTruncatingTail
            }
            cell.textField?.stringValue=parent.playlists[row].name; return cell
        }
        func tableViewSelectionDidChange(_ notification:Notification) {
            guard !updating, let table, parent.playlists.indices.contains(table.selectedRow) else {return}
            let id=parent.playlists[table.selectedRow].id
            if id != parent.selection {parent.select(id)}
        }
        private var contextPlaylist:PlaylistRecord? {guard let table else {return nil}; let row=table.clickedRow>=0 ? table.clickedRow : table.selectedRow; return parent.playlists.indices.contains(row) ? parent.playlists[row] : nil}
        func menuNeedsUpdate(_ menu:NSMenu) {
            menu.removeAllItems(); menu.autoenablesItems=false
            for (title,tag) in [("Rename Playlist…",0),("Delete Playlist…",1),("Export M3U8…",2)] {
                let item=NSMenuItem(title:title,action:#selector(action(_:)),keyEquivalent:""); item.target=self; item.tag=tag; item.isEnabled=contextPlaylist != nil && parent.editingEnabled; menu.addItem(item)
            }
        }
        @objc private func action(_ item:NSMenuItem) {guard let playlist=contextPlaylist else {return}; switch item.tag {case 0:parent.rename(playlist);case 1:parent.delete(playlist);default:parent.export(playlist)}}
        func acceptPayload(_ board:NSPasteboard,row:Int)->Bool {
            guard parent.editingEnabled,parent.playlists.indices.contains(row),let payload=TrackDrag.read(board),payload.trackIDs.count==payload.rowIDs.count else {return false}
            parent.add(payload.trackIDs,parent.playlists[row].id); return true
        }
        func hoveredRow(_ table:NSTableView,location:NSPoint)->Int? {
            let row=table.row(at:location)
            return parent.playlists.indices.contains(row) ? row : nil
        }
        func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
            guard parent.editingEnabled,let row=hoveredRow(tableView,location:tableView.convert(info.draggingLocation,from:nil)),let payload=TrackDrag.read(info.draggingPasteboard),payload.trackIDs.count==payload.rowIDs.count else {return []}
            tableView.setDropRow(row,dropOperation:.on); return .copy
        }
        func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation:NSTableView.DropOperation)->Bool {acceptPayload(info.draggingPasteboard,row:row)}
    }
}
