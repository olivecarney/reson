import AppKit

@MainActor
final class ArtworkCell: NSTableCellView {
    let artwork = NSImageView()
    private(set) var representedPath = ""
    private var request: UInt64 = 0
    private var task: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        artwork.imageScaling = .scaleProportionallyUpOrDown
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = 4
        artwork.layer?.masksToBounds = true
        artwork.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        addSubview(artwork); artwork.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            artwork.widthAnchor.constraint(equalToConstant: 28), artwork.heightAnchor.constraint(equalToConstant: 28),
            artwork.centerXAnchor.constraint(equalTo: centerXAnchor), artwork.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("ArtworkCell is created programmatically") }
    func configure(path: String, cache: ArtworkCache) {
        task?.cancel(); request += 1
        let current = request
        representedPath = path
        artwork.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "No album artwork")
        artwork.contentTintColor = .secondaryLabelColor
        artwork.imageScaling = .scaleProportionallyDown
        artwork.setAccessibilityLabel("No album artwork")
        task = Task { [weak self] in
            let image = await cache.thumbnail(path: path)
            guard !Task.isCancelled, let self, self.request == current, self.representedPath == path else { return }
            if let image {
                self.artwork.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                self.artwork.contentTintColor = nil
                self.artwork.imageScaling = .scaleProportionallyUpOrDown
                self.artwork.setAccessibilityLabel("Album artwork")
            }
        }
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { task?.cancel() }
    }
    deinit { task?.cancel() }
}
