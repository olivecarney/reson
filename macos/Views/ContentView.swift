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
                            searchField
                        }
                    }.padding(InterfaceStyle.panelPadding)
                    Divider()
                    if model.importBusy || !model.importSummary.isEmpty {
                        HStack {
                            if model.importBusy { ProgressView().controlSize(.small) }
                            Text(model.importSummary.isEmpty ? "Indexing folder…" : model.importSummary).font(.system(size: 12))
                            Spacer()
                            if model.importBusy { Button("Cancel") { model.cancelImport() } }
                            else {
                                Button("Rescan") { model.rescanFolders() }
                                Button { model.importSummary = "" } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.borderless).help("Dismiss import summary").accessibilityLabel("Dismiss import summary")
                            }
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                    playlistTable.overlay {
                        if model.tracks.isEmpty {
                            libraryEmptyState.allowsHitTesting(model.selectedPlaylistID == nil && !model.libraryLoading)
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
        .font(InterfaceStyle.body)
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .sheet(isPresented:$model.showQueue) {
            QueueView(model:model)
                .background { BackgroundDismissal { model.showQueue = false } }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .accessibilityLabel("Toggle sidebar").accessibilityValue(model.showSidebar ? "Shown" : "Hidden").help("Toggle sidebar (⌃⌘S)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.selectedPlaylistID != nil {
                    Button("Export M3U8…") { model.exportM3U8() }.disabled(model.playlistBusy)
                }
                Button { model.importFolder() } label: { Label("Import Folder", systemImage: "folder.badge.plus") }
                    .disabled(model.importBusy).help("Import Folder (⇧⌘O)")
                Button { model.openFile() } label: { Label("Open File", systemImage: "doc.badge.plus") }.help("Open File (⌘O)")
                Button { model.showQueue = true } label: { Label("Show Queue", systemImage: "list.bullet") }.help("Show Queue (⌘J)")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.showInspector.toggle() } label: { Label("Toggle inspector", systemImage: "sidebar.right") }
                    .accessibilityValue(model.showInspector ? "Shown" : "Hidden").help("Toggle inspector (⌥⌘I)")
            }
        }
    }
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search library", text: $model.search)
                .focused($searchFocused).textFieldStyle(.plain).accessibilityLabel("Search library")
                .onSubmit { searchFocused = false; model.tableFocusRequest &+= 1 }
                .onExitCommand {
                    if model.search.isEmpty { searchFocused = false }
                    else { model.search = "" }
                }
            if !model.search.isEmpty {
                Button { model.search = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
            }
        }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(searchFocused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1) }
            .frame(minWidth: 100, idealWidth: 180, maxWidth: 240)
    }

    @ViewBuilder private var libraryEmptyState: some View {
        if model.libraryLoading {
            VStack(spacing: 12) { ProgressView(); Text("Loading tracks…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                EmptyState(symbol: model.search.isEmpty ? "music.note.list" : "magnifyingglass",
                           title: model.selectedPlaylistID != nil ? "This playlist is empty" : (model.search.isEmpty ? "Your music, right here" : "No matching tracks"),
                           detail: model.selectedPlaylistID != nil ? "Drag tracks onto this playlist, or use Add to Playlist from a track’s menu." : (model.search.isEmpty ? "Import a folder to build your library, or open a file to start listening." : "Try a different title, artist, album or filename."))
                if model.selectedPlaylistID == nil {
                    if model.search.isEmpty {
                        HStack { Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy); Button("Open File…") { model.openFile() } }
                    } else { Button("Clear Search") { model.search = ""; searchFocused = true } }
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
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
            HStack(spacing: 6) {
                if model.libraryLoading { ProgressView().controlSize(.mini).accessibilityLabel("Updating tracks") }
                Text(model.libraryLoading ? "Updating…" : "\(model.tracks.count) \(model.search.isEmpty ? (model.tracks.count == 1 ? "track" : "tracks") : (model.tracks.count == 1 ? "result" : "results"))")
                    .monospacedDigit()
            }.font(.system(size: 12)).foregroundStyle(.secondary)
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
            Divider().padding(.horizontal, 12)
            Button { model.showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                    Text("Queue").lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(model.session.queue.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(6).help("Play Queue (⌘J)")
                .accessibilityLabel("Play Queue, \(model.session.queue.count) pending tracks")

        }.frame(maxHeight: .infinity).background { NativeBarMaterial(material: .sidebar) }
    }
}
