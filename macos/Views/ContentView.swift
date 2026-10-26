import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: PlayerModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                if model.showSidebar { sidebar.frame(minWidth: InterfaceStyle.sidebarMinimum, idealWidth: 180, maxWidth: 200) }
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        libraryHeading
                        Spacer(minLength: 8)
                        if model.selectedPlaylistID == nil {
                            TextField("Search library", text: $model.search)
                                .focused($searchFocused).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Search library")
                                .frame(minWidth: 100, idealWidth: 180, maxWidth: 220)
                        }
                    }.padding(InterfaceStyle.panelPadding)
                    Divider()
                    if model.importBusy || !model.importSummary.isEmpty {
                        HStack {
                            if model.importBusy { ProgressView().controlSize(.small) }
                            Text(model.importSummary.isEmpty ? "Indexing folder…" : model.importSummary).font(.system(size: 12))
                            Spacer()
                            if model.importBusy { Button("Cancel") { model.cancelImport() } }
                            else { Button("Rescan") { model.rescanFolders() } }
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                    playlistTable.overlay {
                        if model.tracks.isEmpty, model.selectedPlaylistID==nil {
                            VStack(spacing: 16) {
                                Image(systemName: "waveform").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Color.accentColor.opacity(0.65))
                                Text(model.libraryLoading ? "Loading library…" : (model.search.isEmpty ? "Your library is empty." : "No matching tracks.")).font(.system(size: 20, weight: .medium))
                                Text(model.search.isEmpty ? "Import a folder of FLAC, WAV or MP3 files to begin." : "Try another title, artist, album, genre or filename.").foregroundStyle(.secondary)
                                if model.search.isEmpty { Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy) }
                                else { Button("Clear search") { model.search = "" } }
                            }.padding(16).multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.tracks.isEmpty {
                            VStack(spacing:8) {Text(model.libraryLoading ? "Loading playlist…" : "This playlist is empty.").font(.title3); Text("Add tracks from the library’s context menu or drag them onto this playlist in the sidebar.").font(.caption).foregroundStyle(.secondary)}.padding(24).allowsHitTesting(false)
                        }
                    }
                }.frame(minWidth: 280).background(InterfaceStyle.background)
                if model.showInspector { InspectorView(track: model.selected, artworkRevision: model.artworkRevision).frame(minWidth: InterfaceStyle.inspectorMinimum, idealWidth: 240, maxWidth: 280) }
            }
            if let notice=model.notice {
                HStack {Image(systemName:"info.circle");Text(notice).font(.system(size:12));Spacer();Button("Dismiss") {model.notice=nil}}.padding(12).foregroundStyle(.secondary)
            }
            if let error = model.message ?? model.playback.operationError ?? model.playback.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.system(size: 12)).textSelection(.enabled)
                    Spacer()
                    if model.playback.failureKind == "output" {Button("Retry Output") {model.selectOutput(model.playback.preferredDevice)}}
                    else if model.playback.failureKind == "file" {Button("Open File…") {model.openFile()}}
                }
                    .padding(12).background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
            }
            if let outputNotice = model.playback.outputNotice {
                HStack(alignment: .top) {Image(systemName: "info.circle"); Text(outputNotice).font(.system(size: 12)).textSelection(.enabled); Spacer()}
                    .padding(12).foregroundStyle(.secondary)
            }
            Divider()
            TransportView(model: model)
        }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .sheet(isPresented:$model.showQueue) {
            QueueView(model:model)
                .background { BackgroundDismissal { model.showQueue = false } }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("Toggle sidebar").help("Toggle sidebar (⌃⌘S)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.selectedPlaylistID != nil {
                    Button("Export M3U8…") { model.exportM3U8() }.disabled(model.playlistBusy)
                }
                Button { model.importFolder() } label: { Label("Import Folder", systemImage: "folder.badge.plus") }
                    .disabled(model.importBusy).help("Import Folder (⇧⌘O)")
                Button { model.openFile() } label: { Label("Open File", systemImage: "plus") }.help("Open File (⌘O)")
                Button { model.showQueue = true } label: { Label("Show Queue", systemImage: "list.bullet") }.help("Show Queue (⌘J)")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.showInspector.toggle() } label: { Label("Toggle inspector", systemImage: "sidebar.right") }
                    .help("Toggle inspector (⌥⌘I)")
            }
        }
    }
    private var playlistTable: some View {
        let move: (([PlaybackSnapshot],Int)->Void)? = model.selectedPlaylistID==nil ? nil : {model.moveEntries($0,to:$1)}
        let insert: (([Int64],Int)->Void)? = model.selectedPlaylistID.map { id in {model.insertTrackIDs($0,to:id,position:$1)} }
        let remove: (([PlaybackSnapshot])->Void)? = model.selectedPlaylistID==nil ? {model.confirmRemoveTracks($0)} : {model.removeEntries($0)}
        return TrackTable(tracks:model.tracks,selection:$model.selectedPath,play:model.playRow,sort:model.sortLibrary,artworkRevision:model.artworkRevision,
                          sourceID:model.selectedPlaylistID.map { "playlist:\($0)" } ?? "library",move:move,insert:insert,remove:remove,
                          playNext:{model.enqueue($0,next:true)},addQueue:{model.enqueue($0,next:false)},showQueue:{model.showQueue=true},
                          playlists:model.playlists,addToPlaylist:{model.addTracks($0,to:$1)},playingID:model.playingRowID,dataRevision:model.tableRevision,
                          editingEnabled:!model.playlistBusy && !model.libraryLoading && !model.libraryManagementBusy && !model.importBusy,focusRequest:model.tableFocusRequest)
    }
    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.listTitle).font(InterfaceStyle.heading).lineLimit(1)
            Text("\(model.tracks.count) \(model.tracks.count == 1 ? "track" : "tracks")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Library").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
            LibraryNavigationRow(selected: model.selectedPlaylistID == nil) { model.selectPlaylist(nil) }
                .frame(height: 44).padding(.horizontal, 6)
            HStack {Text("Playlists").font(.caption).foregroundStyle(.secondary); Spacer(); Button {model.promptPlaylist()} label:{Image(systemName:"plus").frame(width:16,height:18)}.buttonStyle(.borderless).help("Create Playlist (⌘N)").accessibilityLabel("Create Playlist").disabled(model.playlistBusy)}.padding(.horizontal,20).padding(.top,18).padding(.bottom,8)
            if model.playlists.isEmpty {Text("No playlists").font(.caption).foregroundStyle(.secondary).padding(.horizontal,20).padding(.vertical,8)}
            PlaylistSidebar(playlists:model.playlists,selection:model.selectedPlaylistID,select:{model.selectPlaylist($0)},rename:{model.promptPlaylist($0)},delete:model.confirmDeletePlaylist,export:{model.exportM3U8($0)},add:{model.insertTrackIDs($0,to:$1)},editingEnabled:!model.playlistBusy).padding(.horizontal,6)
            Button {model.showQueue=true} label:{Label("Play Queue (\(model.session.queue.count))",systemImage:"list.bullet")}.buttonStyle(.plain).padding(20)

        }.frame(maxHeight: .infinity).background { NativeBarMaterial(material: .sidebar) }
    }
}
