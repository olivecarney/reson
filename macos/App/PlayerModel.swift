import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class PlayerModel {
    var playback = PlaybackSnapshot()
    var tracks: [PlaybackSnapshot] = []
    var selectedPath: String?
    var showSidebar = true
    var showInspector = false
    var message: String?
    private let bridge = EngineBridge()
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
                            if let index = tracks.firstIndex(where: { $0.path == snapshot.path }) {
                                if tracks[index].title != snapshot.title || tracks[index].format != snapshot.format || tracks[index].rate != snapshot.rate { tracks[index] = snapshot }
                            } else { tracks.append(snapshot) }
                        }
                        if !snapshot.needsRefresh(expected: expected) { return }
                    }
                } catch { if !Task.isCancelled { message = error.localizedDescription }; return }
                try? await Task.sleep(for: .milliseconds(playback.state == 3 ? 1000 : 250))
            } while !Task.isCancelled
        }
    }
    func shutdown() async { closing = true; refreshTask?.cancel(); await bridge.shutdown() }
}
