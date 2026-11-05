import SwiftUI
import AppKit

/// Trailing inspector in the style of Finder's Get Info: artwork and identity on top, then
/// grouped cards that wrap long values and scroll within compact windows.
struct InspectorView: View {
    let track: PlaybackSnapshot?
    var artworkRevision: UInt64 = 0

    var body: some View {
        if let track {
            ScrollView {
                VStack(spacing: 16) {
                    identity(track)
                    section(nil, rows: [
                        ("Album", track.album ?? "Not Tagged"),
                        ("Genre", track.genre ?? "Not Tagged"),
                        ("BPM", track.bpm.map { String(format: "%g", $0) } ?? "Not Tagged"),
                        ("Key", track.key ?? "Not Tagged"),
                    ])
                    section("Audio", rows: [
                        ("Format", track.format.isEmpty ? "Unknown" : track.format),
                        ("Duration", timeLabel(track.duration)),
                        ("Sample Rate", track.rate == 0 ? "Unknown" : String(format: "%.1f kHz", Double(track.rate) / 1000)),
                        ("Bit Depth", track.bits == 0 ? "Unknown" : "\(track.bits)-bit"),
                        ("Channels", track.channels == 0 ? "Unknown" : channelLabel(track.channels)),
                    ])
                    file(track)
                }
                .padding(16)
            }
        } else {
            EmptyState(symbol: "info.circle", title: "No Selection",
                       detail: "Select a track to see its artwork, tags and audio details.")
        }
    }

    /// A grouped card like System Settings / Get Info, with hairline separators between rows.
    private func section<Footer: View>(_ title: String?, rows: [(String, String)], help: String? = nil,
                                       @ViewBuilder footer: () -> Footer = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Divider().padding(.horizontal, 4) }
                        row(item.0, item.1).help(help ?? item.1)
                    }
                    footer()
                }
            }
        }
    }

    private func identity(_ track: PlaybackSnapshot) -> some View {
        VStack(spacing: 12) {
            ArtworkView(path: track.path, pixels: 384, revision: artworkRevision)
                .frame(width: 176, height: 176)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            VStack(spacing: 3) {
                Text(track.displayTitle).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(3).help(track.displayTitle)
                Text(track.artist ?? "Unknown Artist").font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .textSelection(.enabled)
            if track.missing {
                Label("File unavailable. Reconnect its drive or restore it, then rescan.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func file(_ track: PlaybackSnapshot) -> some View {
        let url = URL(fileURLWithPath: track.path)
        return section("File", rows: [
            ("Name", url.lastPathComponent),
            ("Where", (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath),
        ], help: track.path) {
            Divider().padding(.horizontal, 4)
            HStack {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .disabled(track.missing).help("Reveal in Finder")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(track.path, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("Copy file path").help("Copy file path")
            }
            .controlSize(.small).padding(.horizontal, 4).padding(.vertical, 8)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).lineLimit(3).textSelection(.enabled)
        }
        .font(.callout)
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    private func channelLabel(_ channels: UInt32) -> String {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        default: "\(channels)"
        }
    }
}

