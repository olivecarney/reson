import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: PlayerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.showSidebar { sidebar.frame(width: 180); Divider() }
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("All Tracks").font(.system(size: 24, weight: .semibold))
                            Text(model.tracks.isEmpty ? "Your music, close at hand." : "\(model.tracks.count) \(model.tracks.count == 1 ? "track" : "tracks") in this session")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.openFile() } label: { Label("Open File", systemImage: "plus") }
                        Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Toggle inspector")
                    }.padding(24)
                    Divider()
                    if model.tracks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "waveform").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Color.accentColor.opacity(0.65))
                            Text("A little space for your music.").font(.system(size: 20, weight: .medium))
                            Text("Open a FLAC or WAV file to begin.").foregroundStyle(.secondary)
                            Button("Choose a File…") { model.openFile() }.keyboardShortcut("o", modifiers: .command)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TrackTable(tracks: model.tracks, selection: $model.selectedPath, play: model.load)
                    }
                    HStack {
                        Circle().fill(model.playback.state == 2 ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                        Text(model.playback.stateLabel.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("FLAC · WAV").font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                }.background(Color(red: 0.085, green: 0.09, blue: 0.105))
                if model.showInspector { Divider(); InspectorView(track: model.selected).frame(width: 250) }
            }
            if let error = model.message ?? model.playback.error {
                HStack { Image(systemName: "exclamationmark.circle"); Text(error).font(.system(size: 12)); Spacer(); Button("Open File…") { model.openFile() } }
                    .padding(12).background(Color.orange.opacity(0.12)).foregroundStyle(.orange)
            }
            Divider()
            TransportView(model: model)
        }.tint(Color(red: 0.62, green: 0.76, blue: 0.69))
        .toolbar {
            ToolbarItem(placement: .navigation) { Button { model.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Toggle sidebar") }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform").foregroundStyle(Color.accentColor)
                Text("reson").font(.system(size: 21, weight: .semibold, design: .rounded))
            }.padding(.top, 26).padding(.bottom, 32).padding(.horizontal, 20)
            Text("LIBRARY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 12)
            Label("All Tracks", systemImage: "music.note.list")
                .font(.system(size: 13, weight: .medium)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 10)
            ForEach([("Artists", "person.2"), ("Albums", "square.stack"), ("Genres", "guitars")], id: \.0) { item in
                Label(item.0, systemImage: item.1).font(.system(size: 13)).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.vertical, 10).help("Planned for a later version")
            }
            Text("PLAYLISTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 30)
            Text("Coming later").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.top, 12)
            Spacer()
            Text("LOCAL MUSIC · v0.1.1").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).padding(20)
        }.frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
}
