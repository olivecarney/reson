import SwiftUI
import AppKit

struct TrackTable: NSViewRepresentable {
    let tracks: [PlaybackSnapshot]
    @Binding var selection: String?
    let play: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); let table = NSTableView()
        table.style = .plain; table.rowHeight = 48; table.intercellSpacing = NSSize(width: 10, height: 0)
        table.backgroundColor = .clear; table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id,title,width) in [("art","",36.0),("title","Title",210),("artist","Artist",130),("album","Album",130),("bpm","BPM",48),("key","Key",48),("format","Format",65),("duration","Time",64)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "title" ? 120 : 32
            table.addTableColumn(column)
        }
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.doubleClick(_:))
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false; context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: TrackTable
        weak var table: NSTableView?
        init(_ parent: TrackTable) { self.parent = parent }
        private var updating = false
        func update(_ next: TrackTable) {
            let old = parent.tracks
            let selection = next.selection
            parent = next
            guard let table else { return }
            updating = true
            defer { updating = false }
            let sameOrder = old.count == next.tracks.count && zip(old, next.tracks).allSatisfy { $0.path == $1.path }
            if !sameOrder || table.numberOfRows != next.tracks.count {
                table.reloadData()
            } else {
                var changed = IndexSet()
                for row in old.indices where old[row].tableContent != next.tracks[row].tableContent { changed.insert(row) }
                if !changed.isEmpty { table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)) }
            }
            if let index = next.tracks.firstIndex(where: { $0.path == selection }), table.selectedRow != index {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.tracks.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let track = parent.tracks[row]; let id = tableColumn?.identifier.rawValue ?? ""
            let identifier = NSUserInterfaceItemIdentifier(id)
            if id == "art" {
                let image = tableView.makeView(withIdentifier: identifier, owner: self) as? NSImageView ?? NSImageView()
                image.identifier = identifier
                image.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio file")
                image.contentTintColor = NSColor(calibratedRed: 0.62, green: 0.76, blue: 0.69, alpha: 0.6)
                return image
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
            switch id { case "title": label.stringValue = track.displayTitle; case "artist": label.stringValue = track.artist ?? "—"; case "album": label.stringValue = track.album ?? "—"; case "format": label.stringValue = track.format; case "duration": label.stringValue = timeLabel(track.duration); default: label.stringValue = "—" }
            label.font = .systemFont(ofSize: 12, weight: id == "title" ? .medium : .regular)
            label.textColor = id == "title" ? .labelColor : .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table, parent.tracks.indices.contains(table.selectedRow) else { return }
            let path = parent.tracks[table.selectedRow].path
            if parent.selection != path { parent.selection = path }
        }
        @objc func doubleClick(_ sender: NSTableView) {
            guard parent.tracks.indices.contains(sender.clickedRow) else { return }
            parent.play(parent.tracks[sender.clickedRow].path)
        }
    }
}
func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let value = Int(seconds); return String(format: "%d:%02d", value / 60, value % 60)
}

// Compare only values actually displayed by the table, not transport or inspector state.
private extension PlaybackSnapshot {
    var tableContent: (String, String, String, String, String) {
        (displayTitle, artist ?? "—", album ?? "—", format, timeLabel(duration))
    }
}
