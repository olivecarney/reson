import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: PlayerModel
    @FocusState private var searchFocused: Bool
    /// Height of the floating player + banners, so the list can scroll beneath them.
    @State private var chromeHeight: CGFloat = 0

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: InterfaceStyle.sidebarMinimum, ideal: 200, max: 280)
        } detail: {
            detail
                .frame(minWidth: InterfaceStyle.detailMinimum)
                .inspector(isPresented: $model.showInspector) {
                    InspectorView(track: model.selected, artworkRevision: model.artworkRevision)
                        .inspectorColumnWidth(min: InterfaceStyle.inspectorMinimum, ideal: 260, max: 340)
                }
        }
        .navigationTitle(model.listTitle)
        .navigationSubtitle(subtitle)
        .searchable(text: searchText, placement: .toolbar, prompt: "Search Library")
        .modifier(SearchFocus(focused: $searchFocused))
        .onSubmit(of: .search) { searchFocused = false; model.tableFocusRequest &+= 1 }
        .onChange(of: model.searchFocusRequest) { _, _ in searchFocused = true }
        .sheet(isPresented: $model.showQueue) {
            QueueView(model: model)
                .background { BackgroundDismissal { model.showQueue = false } }
        }
        .toolbar { toolbar }
    }

    // MARK: Detail

    private var detail: some View {
        playlistTable
            .overlay {
                if model.tracks.isEmpty {
                    libraryEmptyState
                        .padding(.bottom, chromeHeight)
                        .allowsHitTesting(model.selectedPlaylistID == nil && !model.libraryLoading)
                }
            }
            .overlay(alignment: .bottom) {
                floatingChrome
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
            }
    }

    /// IINA-style floating controller: status cards stack above one glass player panel.
    private var floatingChrome: some View {
        VStack(spacing: 8) {
            if model.importBusy || !model.importSummary.isEmpty {
                StatusBanner(symbol: "checkmark.circle", text: model.importSummary.isEmpty ? "Indexing folder…" : model.importSummary,
                             progress: model.importBusy) {
                    if model.importBusy {
                        Button("Cancel") { model.cancelImport() }
                    } else {
                        Button("Rescan") { model.rescanFolders() }
                        Button { model.importSummary = "" } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).help("Dismiss import summary").accessibilityLabel("Dismiss import summary")
                    }
                }
            }
            if let notice = model.notice {
                StatusBanner(symbol: "info.circle", text: notice) {
                    Button("Dismiss") { model.notice = nil }
                }
            }
            if let error = model.message ?? model.playback.operationError ?? model.playback.error {
                StatusBanner(symbol: "exclamationmark.triangle.fill", text: error, tint: .orange) {
                    if model.playback.failureKind == "output" {
                        Button("Retry Output") { model.selectOutput(model.playback.preferredDevice) }
                    } else if model.playback.failureKind == "file" {
                        Button("Open File…") { model.openFile() }
                    }
                }
            }
            if let outputNotice = model.playback.outputNotice {
                StatusBanner(symbol: "waveform", text: outputNotice) { EmptyView() }
            }
            TransportView(model: model)
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, InterfaceStyle.floatingMargin)
        .padding(.bottom, InterfaceStyle.floatingMargin)
        .animation(.smooth(duration: 0.25), value: bannerState)
    }

    private var bannerState: [Bool] {
        [model.importBusy || !model.importSummary.isEmpty, model.notice != nil,
         (model.message ?? model.playback.operationError ?? model.playback.error) != nil, model.playback.outputNotice != nil]
    }

    @ViewBuilder private var libraryEmptyState: some View {
        if model.libraryLoading {
            ProgressView("Loading Tracks…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.selectedPlaylistID != nil {
            EmptyState(symbol: "music.note.list", title: "This Playlist Is Empty",
                       detail: "Drag tracks onto this playlist, or use Add to Playlist from a track’s menu.")
        } else if !model.search.isEmpty {
            ContentUnavailableView.search(text: model.search)
        } else {
            EmptyState(symbol: "music.note.house", title: "Your Music, Right Here",
                       detail: "Import a folder to build your library, or open a file to start listening.") {
                HStack {
                    Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy)
                        .buttonStyle(.borderedProminent)
                    Button("Open File…") { model.openFile() }
                }
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
                          editingEnabled:!model.playlistBusy && !model.libraryLoading && !model.libraryManagementBusy && !model.importBusy,focusRequest:model.tableFocusRequest,
                          bottomInset:chromeHeight + InterfaceStyle.floatingMargin)
    }

    // MARK: Window chrome

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { model.showSidebar ? .all : .detailOnly },
                set: { model.showSidebar = $0 != .detailOnly })
    }

    /// Search is global, as in Music: typing while a playlist is open returns to the library.
    private var searchText: Binding<String> {
        Binding(get: { model.search }, set: { text in
            if !text.isEmpty, model.selectedPlaylistID != nil { model.selectPlaylist(nil) }
            model.search = text
        })
    }

    private var subtitle: String {
        if model.libraryLoading { return "Updating…" }
        let count = model.tracks.count
        let noun = model.search.isEmpty ? (count == 1 ? "track" : "tracks") : (count == 1 ? "result" : "results")
        return "\(count.formatted()) \(noun)"
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.importFolder() } label: { Label("Import Folder", systemImage: "folder.badge.plus") }
                .disabled(model.importBusy).help("Import Folder (⇧⌘O)")
            Button { model.openFile() } label: { Label("Open File", systemImage: "doc.badge.plus") }.help("Open File (⌘O)")
            if model.selectedPlaylistID != nil {
                Button { model.exportM3U8() } label: { Label("Export M3U8", systemImage: "square.and.arrow.up") }
                    .disabled(model.playlistBusy).help("Export Playlist as M3U8 (⇧⌘E)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showQueue = true } label: { Label("Show Queue", systemImage: "list.bullet") }.help("Show Queue (⌘J)")
            Button { model.showInspector.toggle() } label: { Label("Toggle Inspector", systemImage: "info.circle") }
                .accessibilityValue(model.showInspector ? "Shown" : "Hidden").help("Toggle Inspector (⌥⌘I)")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Library").padding(.top, 8)
            LibraryNavigationRow(selected: model.selectedPlaylistID == nil) { model.selectPlaylist(nil) }
                .frame(height: 36).padding(.horizontal, 10)
            HStack {
                sectionHeader("Playlists")
                Spacer()
                Button { model.promptPlaylist() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Create Playlist (⌘N)").accessibilityLabel("Create Playlist").disabled(model.playlistBusy)
                    .padding(.trailing, 18).padding(.top, 14)
            }
            if model.playlists.isEmpty {
                Text("No Playlists").font(.callout).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.vertical, 6)
            }
            PlaylistSidebar(playlists:model.playlists,selection:model.selectedPlaylistID,select:{model.selectPlaylist($0)},rename:{model.promptPlaylist($0)},delete:model.confirmDeletePlaylist,export:{model.exportM3U8($0)},add:{model.insertTrackIDs($0,to:$1)},editingEnabled:!model.playlistBusy)
                .padding(.horizontal, 10)
            Button { model.showQueue = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").foregroundStyle(.tint).frame(width: 16)
                    Text("Up Next").lineLimit(1)
                    Spacer(minLength: 4)
                    if !model.session.queue.isEmpty {
                        Text(model.session.queue.count.formatted()).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 10).help("Play Queue (⌘J)")
            .accessibilityLabel("Play Queue, \(model.session.queue.count) pending tracks")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `searchFocused` is macOS 15+; on macOS 14 ⌘F falls back to the toolbar's own focus handling.
private struct SearchFocus: ViewModifier {
    var focused: FocusState<Bool>.Binding
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) { content.searchFocused(focused) } else { content }
    }
}
