import SwiftUI
struct InspectorView: View {
    let track: PlaybackSnapshot?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("TRACK DETAILS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ZStack { RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.035)); Image(systemName: "waveform").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.secondary) }.frame(height: 190)
                if let track {
                    VStack(alignment: .leading, spacing: 6) { Text(track.displayTitle).font(.system(size: 18, weight: .semibold)); Text(track.artist ?? "—").foregroundStyle(.secondary) }
                    Divider()
                    row("Album", track.album ?? "—")
                    row("Format", track.format)
                    row("Bit depth", track.bits == 0 ? "—" : "\(track.bits)-bit")
                    row("Sample rate", track.rate == 0 ? "—" : String(format: "%.1f kHz", Double(track.rate)/1000))
                    row("Channels", track.channels == 0 ? "—" : "\(track.channels)")
                    row("Duration", timeLabel(track.duration))
                    row("Genre", track.genre ?? "—")
                    row("BPM", track.bpm.map { String(format: "%g", $0) } ?? "—")
                    row("Key", track.key ?? "—")
                    if track.missing { Text("File missing. Reconnect the drive or rescan after restoring it.").font(.system(size: 12)).foregroundStyle(.orange) }
                    Divider()
                    Text("FILE LOCATION").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(track.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                } else { Text("Select a track to see its details.").foregroundStyle(.secondary) }
            }.padding(20)
        }.background(Color.white.opacity(0.02))
    }
    private func row(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }.font(.system(size: 12)) }
}
