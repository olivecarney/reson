import SwiftUI
struct TransportView: View {
    @Bindable var model: PlayerModel
    var body: some View {
        HStack(spacing: 16) {
            ArtworkView(path: model.playback.path, revision: model.artworkRevision).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.playback.path.isEmpty ? "Nothing playing" : model.playback.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(model.playback.artist ?? (model.playback.path.isEmpty ? "Open a local audio file" : model.playback.stateLabel)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth: 100, idealWidth: 200, maxWidth: 240, alignment: .leading)
            Spacer(minLength: 0)
            Button {model.previousTrack()} label:{Image(systemName:"backward.end.fill")}.buttonStyle(.plain).accessibilityLabel("Previous Track").help("Previous Track (⌘⌥P)").disabled(!model.canPrevious)
            Button { model.togglePlayback() } label: { Image(systemName: model.playback.state == 2 ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 38, height: 38) }.buttonStyle(.plain).accessibilityLabel(model.playback.state == 2 ? "Pause" : "Play").disabled(model.playback.path.isEmpty || model.playback.state == 1)
            Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 12)) }.buttonStyle(.plain).accessibilityLabel("Stop").disabled(model.playback.path.isEmpty)
            Button {model.nextTrack()} label:{Image(systemName:"forward.end.fill")}.buttonStyle(.plain).accessibilityLabel("Next Track").help("Next Track (⌘⌥N)").disabled(!model.canNext)
            Text("\(timeLabel(model.playback.position)) / \(timeLabel(model.playback.duration))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 100)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text(model.playback.format.isEmpty ? "LOCAL AUDIO" : model.playback.format).font(.system(size: 10, weight: .semibold, design: .monospaced))
                Text(model.playback.rate == 0 ? "" : String(format: "Source · %.1f kHz", Double(model.playback.rate) / 1000)).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: 105, alignment: .trailing)
        }.padding(.horizontal, 24).padding(.vertical, 16).background(Color(red: 0.075, green: 0.08, blue: 0.095))
    }
}
