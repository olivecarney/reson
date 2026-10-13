import SwiftUI
import AppKit

struct ContentView: View {
    @Bindable var model: PlayerModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.showSidebar { sidebar.frame(width: 180); Divider() }
                VStack(spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { libraryHeading; Spacer(); libraryActions }
                        VStack(alignment: .leading, spacing: 16) {
                            libraryHeading
                            libraryActions
                        }
                    }.padding(24)
                    Divider()
                    if model.importBusy || !model.importSummary.isEmpty {
                        HStack {
                            if model.importBusy { ProgressView().controlSize(.small) }
                            Text(model.importSummary.isEmpty ? "Indexing folder…" : model.importSummary).font(.system(size: 12))
                            Spacer()
                            if model.importBusy { Button("Cancel") { model.cancelImport() } }
                            else { Button("Rescan") { model.rescanFolders() } }
                        }.padding(.horizontal, 24).padding(.vertical, 8)
                    }
                    if model.tracks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "waveform").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Color.accentColor.opacity(0.65))
                            Text(model.search.isEmpty ? "A little space for your music." : "No matching tracks.").font(.system(size: 20, weight: .medium))
                            Text(model.search.isEmpty ? "Import a folder of FLAC or WAV files to begin." : "Try another title, artist, album, genre or filename.").foregroundStyle(.secondary)
                            if model.search.isEmpty { Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy) }
                            else { Button("Clear search") { model.search = "" } }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TrackTable(tracks: model.tracks, selection: $model.selectedPath, play: model.load, sort: model.sortLibrary, artworkRevision: model.artworkRevision)
                    }
                    HStack {
                        Circle().fill(model.playback.state == 2 ? Color.accentColor : Color.secondary.opacity(0.5)).frame(width: 5, height: 5)
                        Text(model.playback.stateLabel.uppercased()).font(.system(size: 10, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("FLAC · WAV").font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                }.background(Color(red: 0.085, green: 0.09, blue: 0.105))
                if model.showInspector { Divider(); InspectorView(track: model.selected, artworkRevision: model.artworkRevision).frame(width: 250) }
            }
            if let error = model.message ?? model.playback.error ?? model.playback.outputNotice {
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
    private var libraryHeading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("All Tracks").font(.system(size: 24, weight: .semibold))
            Text(model.tracks.isEmpty ? "Your music, close at hand." : "\(model.tracks.count) \(model.tracks.count == 1 ? "track" : "tracks") in your library")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
    private var libraryActions: some View {
        HStack(spacing: 8) {
            TextField("Search library", text: $model.search).accessibilityLabel("Search library")
                .textFieldStyle(.roundedBorder).frame(minWidth: 100, idealWidth: 180, maxWidth: 180)
            Button("Import Folder…") { model.importFolder() }.disabled(model.importBusy)
            Button { model.openFile() } label: { Image(systemName: "plus") }
                .accessibilityLabel("Open File").help("Open File (⌘O)")
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .accessibilityLabel("Toggle inspector").help("Toggle inspector")
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
            Text("LOCAL MUSIC · v0.2.1").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).padding(20)
        }.frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }
}
