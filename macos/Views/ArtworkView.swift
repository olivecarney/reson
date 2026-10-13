import SwiftUI

struct ArtworkView: View {
    let path: String
    var pixels = 80
    var revision: UInt64 = 0
    @State private var loader = ArtworkLoader()
    private struct Request: Hashable { let path: String; let revision: UInt64 }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: pixels == 80 ? 5 : 8).fill(.white.opacity(0.045))
            if loader.path == path, let image = loader.image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "music.note").font(.system(size: pixels == 80 ? 18 : 48, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: pixels == 80 ? 5 : 8))
        .accessibilityLabel("Album artwork")
        .task(id: Request(path: path, revision: revision)) { await loader.load(path: path, pixels: pixels) }
    }
}
