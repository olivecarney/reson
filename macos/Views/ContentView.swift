import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: PlayerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.showSidebar { sidebar.frame(width: 180); Divider() }
                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { libraryHeading; Spacer(); libraryActions }
                        VStack(alignment: .leading, spacing: 16) {
                            libraryHeading
                            libraryActions
                        }
                    }.padding(24)
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
                    if model.tracks.isEmpty, model.selectedPlaylistID==nil {
                        VStack(spacing: 16) {
                            Image(systemName: "waveform").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Color.accentColor.opacity(0.65))
                            Text(model.search.isEmpty ? "A little space for your music." : "No matching tracks.").font(.system(size: 20, weight: .medium))
                            Text(model.search.isEmpty ? "Import a folder of FLAC or WAV files to begin." : "Try another title, artist, album, genre or filename.").foregroundStyle(.secondary)
                            if model.search.isEmpty { Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy) }
                            else { Button("Clear search") { model.search = "" } }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack {
                            playlistTable
                            if model.tracks.isEmpty {
                                VStack(spacing:8) {Text(model.libraryLoading ? "Loading playlist…" : "This playlist is empty.").font(.title3); Text("Add tracks from the library’s context menu or drag them onto this playlist in the sidebar.").font(.caption).foregroundStyle(.secondary)}.padding(24).allowsHitTesting(false)
                            }
                        }
                    }
                    HStack {
                        Circle().fill(model.playback.state == 2 ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                        Text(model.playback.stateLabel.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                        Spacer()
                        Text((model.session.label.isEmpty ? "FLAC · WAV" : "Sequence: \(model.session.label)") + (model.session.queue.isEmpty ? "" : " · \(model.session.queue.count) queued")).font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                }.background(Color(red: 0.085, green: 0.09, blue: 0.105))
                if model.showInspector { Divider(); InspectorView(track: model.selected, artworkRevision: model.artworkRevision).frame(width: 250) }
            }
            if let notice=model.notice {
                HStack {Image(systemName:"info.circle");Text(notice).font(.system(size:12));Spacer();Button("Dismiss") {model.notice=nil}}.padding(12).foregroundStyle(.secondary)
            }
            if let error = model.message ?? model.playback.operationError ?? model.playback.error ?? model.playback.outputNotice {
                HStack { Image(systemName: "exclamationmark.circle"); Text(error).font(.system(size: 12)); Spacer(); Button("Open File…") { model.openFile() } }
                    .padding(12).background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
            }
            Divider()
            TransportView(model: model)
        }.tint(Color(red: 0.62, green: 0.76, blue: 0.69))
        .sheet(isPresented:$model.showQueue) {QueueView(model:model)}
        .toolbar {
            ToolbarItem(placement: .navigation) { Button { model.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle sidebar") }
        }
    }
    private var playlistTable: some View {
        let move: (([PlaybackSnapshot],Int)->Void)? = model.selectedPlaylistID==nil ? nil : {model.moveEntries($0,to:$1)}
        let insert: (([Int64],Int)->Void)? = model.selectedPlaylistID.map { id in {model.insertTrackIDs($0,to:id,position:$1)} }
        let remove: (([PlaybackSnapshot])->Void)? = model.selectedPlaylistID==nil ? nil : {model.removeEntries($0)}
        return TrackTable(tracks:model.tracks,selection:$model.selectedPath,play:model.playRow,sort:model.sortLibrary,artworkRevision:model.artworkRevision,
                          sourceID:model.selectedPlaylistID.map { "playlist:\($0)" } ?? "library",move:move,insert:insert,remove:remove,
                          playNext:{model.enqueue($0,next:true)},addQueue:{model.enqueue($0,next:false)},showQueue:{model.showQueue=true},
                          playlists:model.playlists,addToPlaylist:{model.addTracks($0,to:$1)},playingID:model.playingRowID,dataRevision:model.tableRevision,
                          editingEnabled:!model.playlistBusy && !model.libraryLoading)
    }
    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.listTitle).font(.system(size: 24, weight: .semibold)).lineLimit(1)
            Text(model.tracks.isEmpty ? "Your music, close at hand." : "\(model.tracks.count) \(model.tracks.count == 1 ? "track" : "tracks")")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var libraryActions: some View {
        HStack(spacing: 8) {
            if model.selectedPlaylistID==nil {
                TextField("Search library",text:$model.search).accessibilityLabel("Search library").textFieldStyle(.roundedBorder).frame(minWidth:100,idealWidth:180,maxWidth:180)
            } else {Button("Export M3U8…") {model.exportM3U8()}.disabled(model.playlistBusy)}
            Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy)
            Button { model.openFile() } label: { Image(systemName: "plus") }
                .accessibilityLabel("Open File").help("Open File (⌘O)")
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .accessibilityLabel("Toggle inspector").help("Toggle inspector")
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text("reson").font(.system(size: 21, weight: .semibold, design: .rounded))
            }.padding(.top, 26).padding(.bottom, 32).padding(.horizontal, 20)
            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 12)
            Button {model.selectPlaylist(nil)} label: {
                Label("All Tracks",systemImage:"music.note.list").font(.system(size:13,weight:.medium)).padding(10).frame(maxWidth:.infinity,alignment:.leading)
            }.buttonStyle(.plain).background(Color.white.opacity(model.selectedPlaylistID==nil ? 0.075 : 0),in:RoundedRectangle(cornerRadius:6)).padding(.horizontal,10)
            HStack {Text("PLAYLISTS").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary); Spacer(); Button {model.promptPlaylist()} label:{Image(systemName:"plus")}.buttonStyle(.plain).help("Create Playlist (⌘N)").accessibilityLabel("Create Playlist").disabled(model.playlistBusy)}.padding(.horizontal,20).padding(.top,24).padding(.bottom,8)
            if model.playlists.isEmpty {Text("Create a playlist to organise your music.").font(.caption).foregroundStyle(.tertiary).padding(.horizontal,20).padding(.vertical,8)}
            PlaylistSidebar(playlists:model.playlists,selection:model.selectedPlaylistID,select:{model.selectPlaylist($0)},rename:{model.promptPlaylist($0)},delete:model.confirmDeletePlaylist,export:{model.exportM3U8($0)},add:{model.insertTrackIDs($0,to:$1)},editingEnabled:!model.playlistBusy).padding(.horizontal,6)
            Button {model.showQueue=true} label:{Label("Play Queue (\(model.session.queue.count))",systemImage:"list.bullet")}.buttonStyle(.plain).padding(20)
            Spacer()
            Text("LOCAL MUSIC · v0.4").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).padding(20)
        }.frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
}
