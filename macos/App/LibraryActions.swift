import AppKit

extension PlayerModel {
    func refreshSources() async {
        guard !closing else {return}
        do {
            let reply:LibrarySources=try await library.request(["op":"sources"])
            guard !closing else {return}
            libraryFolders=reply.folders;excludedPaths=reply.exclusions
        } catch {if !closing {message=error.localizedDescription}}
    }
    @discardableResult func manageLibrary(_ request:[String:Any]) async -> Bool {
        guard !closing,!importBusy,!libraryManagementBusy else {return false}
        libraryManagementBusy=true;defer {libraryManagementBusy=false}
        do {
            let _:LibraryReply=try await library.request(request)
            guard !closing else {return false}
            await refreshSources()
            let op=request["op"] as? String
            if op == "tracks_remove", let ids=request["ids"] as? [Int64] {
                let removed=Set(ids)
                removeLibraryRows {removed.contains($0.libraryID ?? -1)}
            } else if op == "folder_remove", let path=request["path"] as? String {
                let removed=URL(fileURLWithPath:path).standardizedFileURL.pathComponents
                removeLibraryRows {row in
                    let parts=URL(fileURLWithPath:row.path).standardizedFileURL.pathComponents
                    return parts.starts(with:removed) && !libraryFolders.contains {parts.starts(with:URL(fileURLWithPath:$0).standardizedFileURL.pathComponents)}
                }
            }
            message=nil;return true
        } catch {if !closing {message=error.localizedDescription};return false}
    }
    func confirmRemoveTracks(_ rows:[PlaybackSnapshot]) {
        let ids=rows.compactMap(\.libraryID)
        guard !ids.isEmpty,ids.count==rows.count,ids.count<=1000 else {message="Select up to 1,000 indexed tracks to remove.";return}
        let alert=NSAlert();alert.messageText="Remove \(ids.count == 1 ? "track" : "\(ids.count) tracks") from Library?"
        alert.informativeText="Original music files stay on disk. These tracks stay excluded during rescans, including after file changes. Restore them in Settings → Library. Playlist entries remain recoverable."
        alert.addButton(withTitle:"Remove from Library");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {return}
        Task {await manageLibrary(["op":"tracks_remove","ids":ids])}
    }
    func confirmRemoveFolder(_ path:String) {
        let alert=NSAlert();alert.messageText="Remove folder from Library?"
        alert.informativeText="\(path)\n\nOriginal music files stay on disk. Tracks covered by other registered folders stay in the library. Playlists are preserved. Exclusions no longer covered by a folder are reset; adding this folder again imports its tracks."
        alert.addButton(withTitle:"Remove Folder");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {return}
        Task {await manageLibrary(["op":"folder_remove","path":path])}
    }
    func restoreExcluded(_ path:String) {
        Task {if await manageLibrary(["op":"exclusion_restore","path":path]) {rescanFolders()}}
    }
}
