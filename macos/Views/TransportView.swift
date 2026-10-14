import SwiftUI
struct TransportView: View {
    @Bindable var model: PlayerModel
    @State private var details = false
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ArtworkView(path: model.playback.path, revision: model.artworkRevision).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.playback.path.isEmpty ? "Nothing playing" : model.playback.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(model.playback.artist ?? model.playback.stateLabel).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                Button {model.previousTrack()} label:{Image(systemName:"backward.end.fill")}.accessibilityLabel("Previous Track").disabled(!model.canPrevious)
                Button {model.togglePlayback()} label:{Image(systemName:model.playback.state == 2 ? "pause.fill":"play.fill").font(.system(size:18)).frame(width:30,height:30)}.accessibilityLabel(model.playback.state == 2 ? "Pause":"Play").disabled(model.playback.path.isEmpty || model.playback.state == 1)
                Button {model.stop()} label:{Image(systemName:"stop.fill")}.accessibilityLabel("Stop").disabled(model.playback.path.isEmpty)
                Button {model.nextTrack()} label:{Image(systemName:"forward.end.fill")}.accessibilityLabel("Next Track").disabled(!model.canNext)
                Button {model.toggleMute()} label:{Image(systemName:model.muted || model.volume == 0 ? "speaker.slash.fill":"speaker.wave.2.fill")}.accessibilityLabel(model.muted || model.volume == 0 ? "Unmute":"Mute").accessibilityValue(model.muted || model.volume == 0 ? "Muted":"\(Int((model.volume*100).rounded())) percent")
                Slider(value:Binding(get:{model.volume},set:{model.setVolume($0)}),in:0...1).frame(width:85).controlSize(.small).accessibilityLabel("App volume")
                Menu {
                    Button(model.playback.preferredDevice == nil ? "✓ System Default":"System Default") {model.selectOutput(nil)}
                    ForEach(model.playback.devices) {device in Button {model.selectOutput(device.id)} label:{Text((model.playback.preferredDevice == device.id ? "✓ ":"")+device.name)}}
                    Divider()
                    Button("Refresh Devices") {model.refreshDevices()}
                    Button("Retry Selected Output") {model.selectOutput(model.playback.preferredDevice)}
                } label:{Image(systemName:"hifispeaker")}.menuStyle(.borderlessButton).frame(width:24).help(model.outputSelection.label).accessibilityLabel("Output device: \(model.outputSelection.label)")
                Button {model.refreshDevices(); details.toggle()} label:{Image(systemName:"info.circle")}.accessibilityLabel("Playback audio details").popover(isPresented:$details) {audioDetails.padding(16).frame(width:320)}
            }.buttonStyle(.plain)
            HStack(spacing: 10) {
                Text(timeLabel(model.timeline.display(model.playback))).frame(width:42,alignment:.trailing)
                TimelineSlider(value:model.timeline.display(model.playback),duration:model.playback.duration,enabled:model.playback.canSeek,begin:model.beginScrub,update:model.scrub,finish:model.endScrub).frame(height:16)
                Text(timeLabel(model.playback.duration)).frame(width:42,alignment:.leading)
            }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
        }.onAppear {model.refreshDevices()}.padding(.horizontal,20).padding(.vertical,10).background(Color(red:0.075,green:0.08,blue:0.095))
    }
    private var audioDetails: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(model.outputSelection.label).font(.headline)
            Text("Source: \(model.playback.format) · \(model.playback.rate) Hz · \(model.playback.channels) channels · \(model.playback.bits == 0 ? "unknown depth":"\(model.playback.bits)-bit")")
            if let rate=model.playback.outputRate, let channels=model.playback.outputChannels {
                Text("Output stream: \(rate) Hz · \(channels) channels · \(model.playback.outputFormat ?? "unknown format")")
                Text(model.playback.convertsOutput ? "Rate or channel conversion is active. Floating-point mixing and CoreAudio conversion may also apply.":"Floating-point mixing and CoreAudio conversion may apply.").foregroundStyle(.secondary)
            } else {Text("No active output stream").foregroundStyle(.secondary)}
            Text(model.playback.stateLabel)
            if let error=model.playback.operationError {Text(error).foregroundStyle(.orange)}
            if let error=model.playback.error {Text(error).foregroundStyle(.orange)}
            if let notice=model.playback.outputNotice {Text(notice).foregroundStyle(.secondary)}
        }.font(.system(size:12)).textSelection(.enabled)
    }
}
