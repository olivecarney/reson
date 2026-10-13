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
    var selectedPath: String?
    var showSidebar = true
    var showInspector = false
    var message: String?
    private let bridge = EngineBridge()
    private let library = LibraryBridge()
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
    var selected: PlaybackSnapshot? { tracks.first { $0.path == selectedPath } }
    func openFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a lossless audio file"
        panel.allowedContentTypes = [UTType(filenameExtension: "flac"), UTType.wav].compactMap { $0 }
        panel.canChooseDirectories = false
        panel.begin { [weak self] result in
            if result == .OK, let url = panel.url { self?.load(url.path) }
        }
    }
    func load(_ path: String) {
        guard !closing else { return }
        requestID += 1
        let id = requestID
        selectedPath = path; message = nil
        // Establish the generation fence before any in-flight refresh can return.
        requestedGeneration += 1
        Task {
            do {
                let sequence = try await bridge.command(path: path)
                expected = max(expected, sequence)
                startRefresh()
            } catch {
                if id == requestID { requestedGeneration = playback.generation; message = error.localizedDescription }
            }
        }
    }
    func togglePlayback() { control(playback.state == 2 ? 2 : 1) }
    func stop() { control(0) }
    private func control(_ action: UInt32) {
        guard !closing, !playback.path.isEmpty else { return }
        Task {
            do { expected = max(expected, try await bridge.command(action: action)); message = nil; startRefresh() }
            catch { message = error.localizedDescription }
        }
    }
    private func startRefresh() {
        guard !closing else { return }
        refreshTask?.cancel()
        refreshTask = Task {
            repeat {
                do {
                    let snapshot = try await bridge.snapshot()
                    guard !Task.isCancelled, !closing else { return }
                    if snapshot.acceptable(after: requestedGeneration) {
                        playback = snapshot
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
        reloadLibrary()
    }
    private func updateTracks() {
        let savedPaths = Set(savedTracks.map(\.path))
        let extra = sessionTracks.filter { !savedPaths.contains($0.path) && (search.isEmpty || [$0.title, $0.artist ?? "", $0.album ?? "", $0.path].contains { $0.localizedCaseInsensitiveContains(search) }) }
        tracks = savedTracks + extra
    }
    func sortLibrary(column: String, ascending: Bool) {
        let columns: [String: UInt32] = ["title": 0, "artist": 1, "album": 2, "bpm": 3, "key": 4, "duration": 5, "format": 6]
        guard let code = columns[column] else { return }
        sortColumn = code; sortDescending = !ascending
        reloadLibrary()
    }
    private func reloadLibrary(debounce: Bool = false) {
        guard !closing else { return }
        queryID += 1; let id = queryID
        libraryTask?.cancel()
        let query = search, sort = sortColumn, descending = sortDescending
        libraryTask = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled, !closing else { return }
            libraryLoading = true
            defer { if id == queryID { libraryLoading = false } }
            do {
                var loaded: [PlaybackSnapshot] = []
                var revision: UInt64?
                repeat {
                    let page: LibraryPage = try await library.request(["op": "query", "search": query, "sort": sort, "descending": descending, "offset": loaded.count, "limit": 500])
                    guard !Task.isCancelled, !closing, id == queryID else { return }
                    if let revision, revision != page.revision { return } // Import changed; its completion will refresh.
                    revision = page.revision
                    loaded.append(contentsOf: page.tracks.map(\.snapshot))
                    if page.tracks.count < 500 { break }
                } while !Task.isCancelled
                savedTracks = loaded; updateTracks()
            } catch { if !Task.isCancelled, !closing, id == queryID { message = error.localizedDescription } }
        }
    }
    func importFolder() {
        let panel = NSOpenPanel()
        panel.title = "Import a music folder"
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
        closing = true; refreshTask?.cancel(); libraryTask?.cancel(); importTask?.cancel()
        async let audio: Void = bridge.shutdown()
        async let database: Void = library.shutdown()
        _ = await (audio, database)
    }
}
