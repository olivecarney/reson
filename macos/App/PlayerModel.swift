import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class PlayerModel {
    var playback = PlaybackSnapshot()
    var timeline = PlaybackTimeline()
    private let settings: UserDefaults
    var volume: Double = 1
    var muted = false
    private var rememberedVolume: Double = 1
    private var gainPending = 0
    var tracks: [PlaybackSnapshot] = []
    var search = "" { didSet { if search != oldValue { reloadLibrary(debounce: true) } } }
    var importBusy = false
    var importSummary = ""
    var libraryFolders: [String] = []
    var excludedPaths: [String] = []
    var libraryManagementBusy = false
    var libraryLoading = false
    var artworkRevision: UInt64 = 0
    var selectedPath: String?
    var searchFocusRequest: UInt64 = 0
    func focusSearch() {
        if selectedPlaylistID != nil {selectPlaylist(nil)}
        searchFocusRequest &+= 1
    }
    var showSidebar = true
    var showInspector = false
    var message: String?
    var notice: String?
    private let bridge: EngineBridge
    let library: LibraryBridge
    init(databaseURL: URL? = nil, settings: UserDefaults = RuntimeStorage.current.preferences) {
        library=LibraryBridge(databaseURL:databaseURL); self.settings=settings
        let saved=settings.object(forKey:"playbackVolume") as? Double ?? 1
        let initialVolume=saved.isFinite ? min(max(saved,0),1) : 1
        volume=initialVolume
        let previous=settings.object(forKey:"playbackPreviousVolume") as? Double ?? 1
        let initialPrevious=previous.isFinite && previous > 0 ? min(previous,1) : 1
        rememberedVolume=initialPrevious
        let initialMuted=settings.bool(forKey:"playbackMuted")
        muted=initialMuted
        bridge=EngineBridge(initialVolume:initialVolume,initialMuted:initialMuted,initialPreviousVolume:initialPrevious)
    }
    var outputSelection: OutputSelection { OutputSelection(devices: playback.devices, preferred: playback.preferredDevice) }
    func beginScrub() { timeline.begin(playback) }
    func scrub(_ seconds: Double) { timeline.update(seconds, snapshot: playback) }
    func endScrub() { if let seconds=timeline.finish(playback) { seek(seconds) } }
    func seek(_ seconds: Double) {
        guard !closing, playback.canSeek, seconds.isFinite, playback.generation == requestedGeneration else {return}
        sendAudio(["op":"seek", "seconds":seconds, "generation":playback.generation])
    }
    func setVolume(_ value: Double) {
        guard !closing, value.isFinite else {return}
        volume=min(max(value,0),1)
        if volume>0 {rememberedVolume=volume; muted=false}
        settings.set(volume,forKey:"playbackVolume"); settings.set(rememberedVolume,forKey:"playbackPreviousVolume"); settings.set(muted,forKey:"playbackMuted")
        sendAudio(["op":"volume","value":volume])
    }
    func toggleMute() {
        guard !closing else {return}
        muted = !(muted || volume==0)
        if !muted && volume==0 {volume=rememberedVolume; sendAudio(["op":"volume","value":volume])}
        settings.set(volume,forKey:"playbackVolume"); settings.set(muted,forKey:"playbackMuted")
        sendAudio(["op":"mute","value":muted])
    }
    func refreshDevices() { sendAudio(["op":"devices"]) }
    func selectOutput(_ id: String?) { sendAudio(["op":"device","id":id as Any? ?? NSNull()]) }
    func reconcileGain(_ snapshot: PlaybackSnapshot) {
        guard gainPending==0 else {return}
        if abs(volume-snapshot.volume)>0.000001 {
            volume=snapshot.volume;settings.set(volume,forKey:"playbackVolume")
            if volume>0 {rememberedVolume=volume;settings.set(volume,forKey:"playbackPreviousVolume")}
        }
        if muted != snapshot.muted {muted=snapshot.muted;settings.set(muted,forKey:"playbackMuted")}
    }
    private func sendAudio(_ command: [String: Any]) {
        guard !closing else {return}
        let playbackRequest=requestID
        let gainChange=["volume","mute"].contains(command["op"] as? String ?? "")
        if gainChange {gainPending+=1}
        Task {
            defer {if gainChange {gainPending-=1}}
            guard !closing else {return}
            do {
                let receipt=try await bridge.command(control:command)
                expected=max(expected,receipt.sequence)
                guard !closing, playbackRequest==requestID else {return}
                requestedGeneration=max(requestedGeneration,receipt.generation)
                message=nil; startRefresh()
            } catch {if !closing, playbackRequest==requestID {message=error.localizedDescription; startRefresh()}}
        }
    }
    var playlists: [PlaylistRecord] = []
    private(set) var selectedPlaylistID: Int64?
    var tableFocusRequest: UInt64 = 0
    var tableRevision: UInt64 = 0
    private(set) var playlistRevision: Int64 = 0
    var playlistBusy = false
    var showQueue = false
    var queueSelection: String?
    var session = PlaybackSession()
    private var completion = PlaybackCompletion()
    private var skippingFiles = false
    var listTitle: String { selectedPlaylistID.flatMap { id in playlists.first { $0.id==id }?.name } ?? "All Tracks" }
    var canNext: Bool { session.canNext && !closing }
    var canPrevious: Bool { session.canPrevious && !closing }
    var playingRowID: String? { selectedPlaylistID==nil ? session.current?.path : session.current?.rowID }
    var queueTracks: [PlaybackSnapshot] { session.queue.map(\.row) }
    func selectPlaylist(_ id: Int64?) {
        guard !closing else { return }
        selectedPlaylistID=id; selectedPath=nil; search=""; savedTracks=[]; tracks=[]; tableRevision &+= 1; reloadLibrary()
    }
    func refreshPlaylists() async throws {
        let reply: PlaylistList = try await library.request(["op":"playlists"])
        guard !closing else {return}
        playlists=reply.playlists
        if let id=selectedPlaylistID, !playlists.contains(where:{$0.id==id}) {selectPlaylist(nil); tableFocusRequest &+= 1}
    }
    func createPlaylist(name: String) async -> Int64? {
        guard !closing, !playlistBusy else {return nil}
        playlistBusy=true; message=nil; defer {playlistBusy=false}
        do {
            let reply: PlaylistCreated = try await library.request(["op":"playlist_create","name":name])
            try await refreshPlaylists(); return closing ? nil : reply.playlist.id
        } catch {if !closing {message=error.localizedDescription}; return nil}
    }
    @discardableResult func mutatePlaylist(_ request: [String: Any]) async -> Bool {
        guard !closing, !playlistBusy else {return false}
        playlistBusy=true; message=nil; defer {playlistBusy=false}
        do {
            let _: LibraryReply = try await library.request(request)
            try await refreshPlaylists()
            let op=request["op"] as? String ?? ""
            if !closing, ["playlist_add","playlist_remove","playlist_move"].contains(op), request["playlist_id"] as? Int64 == selectedPlaylistID {reloadLibrary()}
            return !closing
        } catch {if !closing {message=error.localizedDescription; if request["playlist_id"] as? Int64 == selectedPlaylistID {reloadLibrary()}}; return false}
    }
    func importPlaylist(path:String,name:String) async {
        guard !closing,!playlistBusy else {return}
        playlistBusy=true; message=nil; defer {playlistBusy=false}
        do {
            let reply:PlaylistCreated=try await library.request(["op":"m3u8_import","path":path,"name":name])
            try await refreshPlaylists()
            guard !closing else {return}
            selectPlaylist(reply.playlist.id)
            notice="Imported playlist. Tracks outside your library stay unavailable until you import their folder." + ((reply.skipped ?? 0)>0 ? " \(reply.skipped!) unsupported entries skipped." : "")
        } catch {if !closing {message=error.localizedDescription}}
    }
    func insertTrackIDs(_ ids:[Int64],to id:Int64,position:Int?=nil) {
        var request:[String:Any] = ["op":"playlist_add","playlist_id":id,"ids":ids]
        if let position {request["position"]=position;request["revision"]=playlistRevision}
        Task {await mutatePlaylist(request)}
    }
    func playQueued(_ identity:String) {
        guard let entry=session.queue.first(where:{$0.row.rowID==identity}) else {return}
        _=session.moveQueue(ids:[entry.id],to:0); nextTrack()
    }
    func addTracks(_ rows: [PlaybackSnapshot], to id: Int64, position: Int? = nil) {
        let ids=rows.compactMap(\.libraryID)
        guard !ids.isEmpty, ids.count==rows.count, ids.count<=1000 else {message="Select up to 1,000 indexed tracks to add."; return}
        var request: [String:Any] = ["op":"playlist_add","playlist_id":id,"ids":ids]
        if let position {request["position"]=position; request["revision"]=playlistRevision}
        Task {await mutatePlaylist(request)}
    }
    func removeEntries(_ rows: [PlaybackSnapshot]) {
        guard let id=selectedPlaylistID else {return}
        let ids=rows.compactMap(\.entryID), revision=playlistRevision
        Task {await mutatePlaylist(["op":"playlist_remove","playlist_id":id,"ids":ids,"revision":revision])}
    }
    func moveEntries(_ rows: [PlaybackSnapshot], to position: Int) {
        guard let id=selectedPlaylistID else {return}
        let ids=rows.compactMap(\.entryID), revision=playlistRevision
        Task {await mutatePlaylist(["op":"playlist_move","playlist_id":id,"ids":ids,"position":position,"revision":revision])}
    }
    func enqueue(_ rows: [PlaybackSnapshot], next: Bool) {guard !closing else {return}; session.enqueue(rows,next:next)}
    func removeQueued(_ rows: [PlaybackSnapshot]) { session.removeQueue(ids:rows.compactMap(\.queueID)) }
    func moveQueued(_ rows: [PlaybackSnapshot], to position: Int) { _=session.moveQueue(ids:rows.compactMap(\.queueID),to:position) }
    func nextTrack() {guard !closing else {return}; if let track=session.next() {playTrack(track)} }
    func previousTrack() {guard !closing else {return}; if let track=session.previous() {playTrack(track)} }
    func playRow(_ identity: String) {
        guard let selectedIndex=tracks.firstIndex(where:{$0.rowID==identity}), !closing else {return}
        guard let index=tracks.indices.dropFirst(selectedIndex).first(where:{!tracks[$0].missing}) else {message="No available tracks remain in this list.";return}
        if let track=session.start(tracks,at:index,label:listTitle) {playTrack(track)}
    }
    private var libraryTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var queryID: UInt64 = 0
    private var sortColumn: UInt32 = 0
    private var sortDescending = false
    private var libraryStarted = false
    private var savedTracks: [PlaybackSnapshot] = []
    var sessionTracks: [PlaybackSnapshot] = []
    var hiddenSessionPaths: Set<String> = []
    private var refreshTask: Task<Void, Never>?
    private var expected: UInt64 = 0
    private var requestedGeneration: UInt64 = 0
    private var requestID: UInt64 = 0
    private(set) var closing = false
    var selected: PlaybackSnapshot? { tracks.first { $0.rowID == selectedPath } }
    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open an audio file"
        panel.allowedContentTypes = [UTType(filenameExtension: "flac"), UTType.wav, UTType.mp3].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.load(url.path) }
        }
    }
    func load(_ path: String) {
        guard !closing else {return}
        if let track=session.start([tracks.first { $0.path==path } ?? {var s=PlaybackSnapshot(); s.path=path; return s}()],at:0,label:"Open File") {playTrack(track)}
    }
    private func playTrack(_ track: PlaybackSnapshot) {
        guard !closing else {return}
        timeline.cancel()
        requestID += 1
        let id=requestID
        message=nil; notice=nil; completion.disarm(); skippingFiles=true
        Task {
            guard !closing, id==requestID else {return}
            do {
                let sequence=try await bridge.command(path:track.path,request:id)
                expected=max(expected,sequence.sequence)
                guard !closing, id==requestID else {return}
                requestedGeneration=sequence.generation; completion.arm(); startRefresh()
            } catch {
                if !closing, id==requestID {requestedGeneration=playback.generation; message=error.localizedDescription; skippingFiles=false}
            }
        }
    }
    private var playbackStartRow: PlaybackSnapshot? {
        if let selected, !selected.missing { return selected }
        return tracks.first { !$0.missing }
    }
    var canTogglePlayback: Bool {
        !closing && playback.state != 1 && (!playback.path.isEmpty || playbackStartRow != nil)
    }
    func togglePlayback() {
        guard canTogglePlayback else { return }
        if playback.path.isEmpty {
            if let row = playbackStartRow { playRow(row.rowID) }
        } else { control(playback.state == 2 ? 2 : 1) }
    }
    func stop() { timeline.cancel(); completion.disarm(); skippingFiles=false; control(0) }
    private func control(_ action: UInt32) {
        guard !closing, action==0 || !playback.path.isEmpty else { return }
        requestID += 1; let id=requestID
        if action != 2 {completion.disarm()}
        Task {
            guard !closing, id==requestID else {return}
            do {
                let receipt=try await bridge.command(action:action,request:id)
                expected=max(expected,receipt.sequence)
                guard !closing, id==requestID else {return}
                requestedGeneration=receipt.generation
                if action==1 {completion.arm()}
                message = nil; startRefresh()
            }
            catch {if !closing,id==requestID {message=error.localizedDescription}}
        }
    }
    private func startRefresh() {
        guard !closing else { return }
        refreshTask?.cancel()
        let refreshID=requestID
        refreshTask = Task {
            repeat {
                do {
                    let snapshot = try await bridge.snapshot()
                    guard !Task.isCancelled, !closing, refreshID==requestID else { return }
                    if snapshot.acceptable(after: requestedGeneration), snapshot.acknowledged >= expected {
                        var snapshot=snapshot
                        if let current=session.current, current.path==snapshot.path {
                            snapshot.libraryID=current.libraryID; snapshot.entryID=current.entryID
                            snapshot.genre=current.genre; snapshot.bpm=current.bpm; snapshot.key=current.key
                        }
                        if playback.generation != snapshot.generation || !snapshot.canSeek {timeline.cancel()}
                        reconcileGain(snapshot)
                        if playback != snapshot {playback=snapshot}
                        if snapshot.state==2 || snapshot.state==5 {if session.needsBeginConfirmation {session.began()}; skippingFiles=false}
                        if completion.consume(snapshot,generation:requestedGeneration,expected:expected) {
                            nextTrack(); return
                        }
                        if snapshot.state==6, snapshot.failureKind=="file", skippingFiles {
                            skippingFiles=false
                            if let next=session.next() {playTrack(next)} else {message="No more available tracks."}
                            return
                        }
                        if !snapshot.path.isEmpty, !snapshot.title.isEmpty {
                            if !hiddenSessionPaths.contains(snapshot.path), !excludedPaths.contains(snapshot.path), !savedTracks.contains(where: { $0.path == snapshot.path }) {
                                if let index = sessionTracks.firstIndex(where: { $0.path == snapshot.path }) { sessionTracks[index] = snapshot }
                                else { sessionTracks.append(snapshot) }
                                updateTracks()
                            }
                        }
                        if !snapshot.needsRefresh(expected: expected) { return }
                    }
                } catch { if !Task.isCancelled { message = error.localizedDescription }; return }
                try? await Task.sleep(for: .milliseconds(playback.refreshMilliseconds(expected: expected)))
            } while !Task.isCancelled
        }
    }
    func startLibrary() {
        guard !libraryStarted, !closing else { return }
        libraryStarted = true
        Task {do {try await refreshPlaylists()} catch {if !closing {message=error.localizedDescription}}}
        Task {await refreshSources()}
        reloadLibrary()
    }
    private func updateTracks() {
        if selectedPlaylistID != nil {tracks=savedTracks; tableRevision &+= 1; return}
        let savedPaths = Set(savedTracks.map(\.path))
        hiddenSessionPaths.subtract(savedPaths)
        let excluded=Set(excludedPaths).union(hiddenSessionPaths)
        let extra = sessionTracks.filter { !excluded.contains($0.path) && !savedPaths.contains($0.path) && (search.isEmpty || [$0.title, $0.artist ?? "", $0.album ?? "", $0.path].contains { $0.localizedCaseInsensitiveContains(search) }) }
        tracks = savedTracks + extra; tableRevision &+= 1
    }
    func removeLibraryRows(matching predicate: (PlaybackSnapshot) -> Bool) {
        hiddenSessionPaths.formUnion((tracks + sessionTracks + [playback]).filter(predicate).map(\.path))
        sessionTracks.removeAll(where:predicate)
        // Preserve native sort/search and update only the visible library snapshot.
        // An in-flight query or a playlist needs a fresh worker view instead.
        if selectedPlaylistID != nil || libraryLoading {reloadLibrary();return}
        savedTracks.removeAll(where:predicate)
        updateTracks()
    }
    func sortLibrary(column: String, ascending: Bool) {
        guard selectedPlaylistID==nil else {return}
        let columns: [String: UInt32] = ["title": 0, "artist": 1, "album": 2, "bpm": 3, "key": 4, "duration": 5, "format": 6]
        guard let code = columns[column] else { return }
        sortColumn = code; sortDescending = !ascending
        reloadLibrary()
    }
    func reloadLibrary(debounce: Bool = false) {
        guard !closing else { return }
        queryID += 1; let id = queryID
        libraryTask?.cancel()
        let query = search, sort = sortColumn, descending = sortDescending, playlist=selectedPlaylistID
        libraryLoading=true
        libraryTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled, !closing else { return }
            libraryLoading = true
            defer { if id == queryID { libraryLoading = false } }
            do {
                var loaded: [PlaybackSnapshot] = []
                var revision: UInt64?
                var entryRevision: Int64?
                repeat {
                    let batch: [PlaybackSnapshot], currentRevision: UInt64
                    if let playlist {
                        let page: PlaylistPage=try await library.request(["op":"playlist_entries","playlist_id":playlist,"offset":loaded.count,"limit":500])
                        batch=page.entries.map(\.snapshot); currentRevision=page.library_revision
                        guard !Task.isCancelled,!closing,id==queryID else {return}
                        if let entryRevision,entryRevision != page.revision {reloadLibrary();return}
                        entryRevision=page.revision
                    } else {
                        let page: LibraryPage=try await library.request(["op":"query","search":query,"sort":sort,"descending":descending,"offset":loaded.count,"limit":500])
                        batch=page.tracks.map(\.snapshot); currentRevision=page.revision
                    }
                    guard !Task.isCancelled, !closing, id==queryID else {return}
                    if let revision, revision != currentRevision {reloadLibrary(); return}
                    revision=currentRevision; loaded.append(contentsOf:batch)
                    if batch.count<500 {break}
                } while !Task.isCancelled
                guard !Task.isCancelled,!closing,id==queryID else {return}
                if let entryRevision {playlistRevision=entryRevision}
                savedTracks = loaded; updateTracks()
            } catch { if !Task.isCancelled, !closing, id == queryID { message = error.localizedDescription } }
        }
    }
    func importFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import a music folder"
        panel.allowedContentTypes = []
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.beginImport(path: url.path) }
        }
    }
    func rescanFolders() { beginImport(path: nil) }
    private func beginImport(path: String?) {
        guard !closing, !importBusy, !libraryManagementBusy else { return }
        importBusy = true; message = nil
        importTask = Task {
            defer { importBusy = false }
            do {
                var request: [String: Any] = ["op": path == nil ? "rescan" : "import"]
                if let path { request["path"] = path }
                let _: LibraryReply = try await library.request(request)
                repeat {
                    let status: LibraryStatus = try await library.request(["op": "status"])
                    guard !Task.isCancelled, !closing else { return }
                    let summary = status.summary
                    importSummary = "\(summary.indexed) indexed · \(summary.failed) skipped" + (summary.cancelled ? " · Cancelled" : "")
                    if !status.busy {
                        if let error = summary.error { message = error }
                        artworkRevision &+= 1
                        await refreshSources(); reloadLibrary(); return
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                } while !Task.isCancelled
            } catch { if !closing { message = error.localizedDescription }; reloadLibrary() }
        }
    }
    func cancelImport() {
        Task { do { let _: LibraryReply = try await library.request(["op": "cancel"]) } catch { message = error.localizedDescription } }
    }
    func shutdown() async {
        closing = true; session.shutdown(); completion.disarm(); refreshTask?.cancel(); libraryTask?.cancel(); importTask?.cancel()
        async let audio: Void = bridge.shutdown()
        async let database: Void = library.shutdown()
        async let artwork: Void = ArtworkCache.shared.shutdown()
        _ = await (audio, database, artwork)
    }
}
