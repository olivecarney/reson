import AppKit
import UniformTypeIdentifiers

extension PlayerModel {
    func promptPlaylist(_ playlist:PlaylistRecord? = nil) {
        let alert=NSAlert(); alert.messageText=playlist==nil ? "Create Playlist" : "Rename Playlist"
        let input=NSTextField(string:playlist?.name ?? "Untitled Playlist"); input.frame=NSRect(x:0,y:0,width:280,height:24)
        alert.accessoryView=input; alert.addButton(withTitle:playlist==nil ? "Create" : "Rename"); alert.addButton(withTitle:"Cancel")
        alert.window.initialFirstResponder=input
        func complete(_ result:NSApplication.ModalResponse) {
            guard result == .alertFirstButtonReturn else {return}
            let name=input.stringValue
            Task {
                if let playlist {await mutatePlaylist(["op":"playlist_rename","playlist_id":playlist.id,"name":name])}
                else if let id=await createPlaylist(name:name) {selectPlaylist(id)}
            }
        }
        if let window=NSApp.keyWindow {alert.beginSheetModal(for:window,completionHandler:complete)} else {complete(alert.runModal())}
    }
    func confirmDeletePlaylist(_ playlist:PlaylistRecord) {
        let alert=NSAlert(); alert.messageText="Delete “\(playlist.name)”?"; alert.informativeText="The playlist will be deleted. Your music files stay in the library."; alert.alertStyle = .warning
        alert.addButton(withTitle:"Delete Playlist"); alert.addButton(withTitle:"Cancel")
        func complete(_ result:NSApplication.ModalResponse) {if result == .alertFirstButtonReturn {Task {await mutatePlaylist(["op":"playlist_delete","playlist_id":playlist.id])}}}
        if let window=NSApp.keyWindow {alert.beginSheetModal(for:window,completionHandler:complete)} else {complete(alert.runModal())}
    }
    func importM3U8() {
        let panel=NSOpenPanel(); panel.title="Import M3U8 Playlist"; panel.allowedContentTypes=[UTType(filenameExtension:"m3u8") ?? .plainText]; panel.canChooseDirectories=false
        panel.begin { [weak self] result in
            guard result == .OK, let url=panel.url, let self else {return}
            Task {await self.importPlaylist(path:url.path,name:url.deletingPathExtension().lastPathComponent)}
        }
    }
    func exportM3U8(_ playlist:PlaylistRecord? = nil) {
        guard let playlist=playlist ?? playlists.first(where:{$0.id==selectedPlaylistID}) else {return}
        let panel=NSSavePanel(); panel.title="Export M3U8 Playlist"; panel.allowedContentTypes=[UTType(filenameExtension:"m3u8") ?? .plainText]; panel.nameFieldStringValue=playlist.name+".m3u8"
        panel.begin { [weak self] result in
            guard result == .OK, let url=panel.url, let self else {return}
            Task {await self.mutatePlaylist(["op":"m3u8_export","playlist_id":playlist.id,"path":url.path])}
        }
    }
}
