import AppKit
import Observation

@MainActor @Observable
final class ArtworkLoader {
    private(set) var path = ""
    private(set) var image: NSImage?
    private var generation: UInt64 = 0
    func load(path: String, pixels: Int = 80, cache: ArtworkCache = .shared) async {
        guard !Task.isCancelled else { return }
        generation += 1; let request = generation
        self.path = path; image = nil
        let thumbnail = await cache.thumbnail(path: path, pixels: pixels)
        guard !Task.isCancelled, generation == request, self.path == path else { return }
        image = thumbnail.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}
