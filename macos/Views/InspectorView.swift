import SwiftUI
import AppKit

struct InspectorView: View {
    let track: PlaybackSnapshot?
    var artworkRevision: UInt64 = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Track Details").font(.system(size: 12, weight: .medium))
                Spacer()
            }.padding(InterfaceStyle.panelPadding)
            Divider()
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ArtworkView(path: track.path, pixels: 384, revision: artworkRevision)
                            .frame(width: 160, height: 160).frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.displayTitle).font(.system(size: 16, weight: .medium))
                                .lineLimit(3).textSelection(.enabled).help(track.displayTitle)
                            Text(track.artist ?? "Unknown artist").font(InterfaceStyle.body)
                                .foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        }
                        if track.missing {
                            Label("File unavailable. Reconnect its drive or restore it, then rescan.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        metadataSection("Music") {
                            row("Album", track.album ?? "Not tagged")
                            row("Genre", track.genre ?? "Not tagged")
                            row("BPM", track.bpm.map { String(format: "%g", $0) } ?? "Not tagged")
                            row("Key", track.key ?? "Not tagged")
                        }
                        metadataSection("Audio") {
                            row("Format", track.format.isEmpty ? "Unknown" : track.format)
                            row("Duration", timeLabel(track.duration))
                            row("Sample rate", track.rate == 0 ? "Unknown" : String(format: "%.1f kHz", Double(track.rate) / 1000))
                            row("Bit depth", track.bits == 0 ? "Unknown" : "\(track.bits)-bit")
                            row("Channels", track.channels == 0 ? "Unknown" : "\(track.channels)")
                        }
                        metadataSection("File") {
                            let url = URL(fileURLWithPath: track.path)
                            Text(url.lastPathComponent).font(.system(size: 12)).lineLimit(2)
                                .textSelection(.enabled).help(track.path)
                            Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                .textSelection(.enabled).help(track.path)
                            HStack(spacing: 10) {
                                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                                    Label("Reveal", systemImage: "folder")
                                }.disabled(track.missing).help("Reveal in Finder")
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(track.path, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                    .accessibilityLabel("Copy file path").help("Copy file path")
                            }.controlSize(.small)
                        }
                    }.padding(InterfaceStyle.panelPadding)
                }
            } else {
                Spacer()
                EmptyState(symbol: "info.circle", title: "Track details", detail: "Select a track to see its artwork, tags and audio information.")
                Spacer()
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func metadataSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).multilineTextAlignment(.trailing).lineLimit(3).textSelection(.enabled).help(value)
        }.font(.system(size: 12))
    }
}
