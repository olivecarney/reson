import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class PlayerModel {
    var playback = PlaybackSnapshot()
    var tracks: [PlaybackSnapshot] = []
    var search = "" { didSet { if search != oldValue { reloadLibrary(debounce: true) } } }
    var importBusy = false
    var importSummary = ""
    var libraryLoading = false
    var artworkRevision: UInt64 = 0
    var selectedPath: String?
    var showSidebar = true
    var showInspector = false
    var message: String?
    private let bridge = EngineBridge()
    private let library: LibraryBridge
    init(databaseURL: URL? = nil) { library=LibraryBridge(databaseURL:databaseURL) }
    var playlists: [PlaylistRecord] = []
    private(set) var selectedPlaylistID: Int64?
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
    var playingRowID: String? { session.current?.rowID }
    var queueTracks: [PlaybackSnapshot] { session.queue.map(\.row) }
    func selectPlaylist(_ id: Int64?) {
        guard !closing else { return }
        selectedPlaylistID=id; selectedPath=nil; search=""; savedTracks=[]; tracks=[]; tableRevision &+= 1; reloadLibrary()
    }
    func refreshPlaylists() async throws {
        let reply: PlaylistList = try await library.request(["op":"playlists"])
        guard !closing else {return}
        playlists=reply.playlists
        if let id=selectedPlaylistID, !playlists.contains(where:{$0.id==id}) {selectPlaylist(nil)}
    }
    func createPlaylist(name: String) async -> Int64? {
        guard !closing, !playlistBusy else {return nil}
        playlistBusy=true; defer {playlistBusy=false}
        do {
            let reply: PlaylistCreated = try await library.request(["op":"playlist_create","name":name])
            try await refreshPlaylists(); return closing ? nil : reply.playlist.id
        } catch {if !closing {message=error.localizedDescription}; return nil}
    }
    @discardableResult func mutatePlaylist(_ request: [String: Any]) async -> Bool {
        guard !closing, !playlistBusy else {return false}
        playlistBusy=true; defer {playlistBusy=false}
        do {
            let _: LibraryReply = try await library.request(request)
            try await refreshPlaylists()
            if !closing {reloadLibrary()}
            return !closing
        } catch {if !closing {message=error.localizedDescription; reloadLibrary()}; return false}
    }
    func importPlaylist(path:String,name:String) async {
        guard !closing,!playlistBusy else {return}
        playlistBusy=true; defer {playlistBusy=false}
        do {
            let reply:PlaylistCreated=try await library.request(["op":"m3u8_import","path":path,"name":name])
            try await refreshPlaylists()
            guard !closing else {return}
            selectPlaylist(reply.playlist.id)
            message="Imported playlist. Unindexed paths remain unavailable until their folder is imported." + ((reply.skipped ?? 0)>0 ? " \(reply.skipped!) unsupported entries skipped." : "")
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
        let ids=rows.compactMap(\.entryID)
        Task {await mutatePlaylist(["op":"playlist_remove","playlist_id":id,"ids":ids,"revision":playlistRevision])}
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
        guard let index=tracks.firstIndex(where:{$0.rowID==identity}), !closing else {return}
        if let track=session.start(tracks,at:index,label:listTitle) {
            if track.missing {message="Skipping an unavailable track."; nextTrack()} else {playTrack(track)}
        }
    }
    private var libraryTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var queryID: UInt64 = 0
    private var sortColumn: UInt32 = 0
    private var sortDescending = false
    private var libraryStarted = false
    private var savedTracks: [PlaybackSnapshot] = []
    private var sessionTracks: [PlaybackSnapshot] = []
    private var refreshTask: Task<Void, Never>?
    private var expected: UInt64 = 0
    private var requestedGeneration: UInt64 = 0
    private var requestID: UInt64 = 0
    private var closing = false
    var selected: PlaybackSnapshot? { tracks.first { $0.rowID == selectedPath } }
    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a lossless audio file"
        panel.allowedContentTypes = [UTType(filenameExtension: "flac"), UTType.wav].compactMap { $0 }
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
        requestID += 1
        let id=requestID
        message=nil; completion.disarm(); skippingFiles=true
        Task {
            do {
                let sequence=try await bridge.command(path:track.path)
                expected=max(expected,sequence.sequence)
                guard !closing, id==requestID else {return}
                requestedGeneration=sequence.generation; completion.arm(); startRefresh()
            } catch {
                if !closing, id==requestID {requestedGeneration=playback.generation; message=error.localizedDescription; skippingFiles=false}
            }
        }
    }
    func togglePlayback() { control(playback.state == 2 ? 2 : 1) }
    func stop() { completion.disarm(); skippingFiles=false; control(0) }
    private func control(_ action: UInt32) {
        guard !closing, action==0 || !playback.path.isEmpty else { return }
        requestID += 1; let id=requestID
        if action != 2 {completion.disarm()}
        Task {
            do {
                let receipt=try await bridge.command(action:action)
                expected=max(expected,receipt.sequence)
                guard !closing, id==requestID else {return}
                requestedGeneration=receipt.generation
                if action==1 {completion.arm()}
                message = nil; startRefresh()
            }
            catch { message = error.localizedDescription }
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
                        playback = snapshot
                        if snapshot.state==2 || snapshot.state==5 {session.began(); skippingFiles=false}
                        if completion.consume(snapshot,generation:requestedGeneration,expected:expected) {
                            nextTrack(); return
                        }
                        if snapshot.state==6, snapshot.failureKind=="file", skippingFiles {
                            skippingFiles=false
                            if let next=session.next() {playTrack(next)} else {message="No more available tracks."}
                            return
                        }
                        if !snapshot.path.isEmpty, !snapshot.title.isEmpty {
                            if !savedTracks.contains(where: { $0.path == snapshot.path }) {
                                if let index = sessionTracks.firstIndex(where: { $0.path == snapshot.path }) { sessionTracks[index] = snapshot }
                                else { sessionTracks.append(snapshot) }
                                updateTracks()
                            }
                        }
                        if !snapshot.needsRefresh(expected: expected) { return }
                    }
                } catch { if !Task.isCancelled { message = error.localizedDescription }; return }
                try? await Task.sleep(for: .milliseconds(playback.state == 3 ? 1000 : 250))
            } while !Task.isCancelled
        }
    }
    func startLibrary() {
        guard !libraryStarted, !closing else { return }
        libraryStarted = true
        Task {do {try await refreshPlaylists()} catch {if !closing {message=error.localizedDescription}}}
        reloadLibrary()
    }
    private func updateTracks() {
        if selectedPlaylistID != nil {tracks=savedTracks; tableRevision &+= 1; return}
        let savedPaths = Set(savedTracks.map(\.path))
        let extra = sessionTracks.filter { !savedPaths.contains($0.path) && (search.isEmpty || [$0.title, $0.artist ?? "", $0.album ?? "", $0.path].contains { $0.localizedCaseInsensitiveContains(search) }) }
        tracks = savedTracks + extra; tableRevision &+= 1
    }
    func sortLibrary(column: String, ascending: Bool) {
        guard selectedPlaylistID==nil else {return}
        let columns: [String: UInt32] = ["title": 0, "artist": 1, "album": 2, "bpm": 3, "key": 4, "duration": 5, "format": 6]
        guard let code = columns[column] else { return }
        sortColumn = code; sortDescending = !ascending
        reloadLibrary()
    }
    private func reloadLibrary(debounce: Bool = false) {
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
                repeat {
                    let batch: [PlaybackSnapshot], currentRevision: UInt64
                    if let playlist {
                        let page: PlaylistPage=try await library.request(["op":"playlist_entries","playlist_id":playlist,"offset":loaded.count,"limit":500])
                        batch=page.entries.map(\.snapshot); currentRevision=page.library_revision
                        if loaded.isEmpty {playlistRevision=page.revision}
                        else if playlistRevision != page.revision {reloadLibrary(); return}
                    } else {
                        let page: LibraryPage=try await library.request(["op":"query","search":query,"sort":sort,"descending":descending,"offset":loaded.count,"limit":500])
                        batch=page.tracks.map(\.snapshot); currentRevision=page.revision
                    }
                    guard !Task.isCancelled, !closing, id==queryID else {return}
                    if let revision, revision != currentRevision {reloadLibrary(); return}
                    revision=currentRevision; loaded.append(contentsOf:batch)
                    if batch.count<500 {break}
                } while !Task.isCancelled
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
        guard !closing, !importBusy else { return }
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
                        reloadLibrary(); return
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
