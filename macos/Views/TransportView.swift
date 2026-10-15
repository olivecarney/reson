import SwiftUI
struct TransportView: View {
    @Bindable var model: PlayerModel
    @State private var details = false
    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { trackIdentity; playbackControls; outputControls }
                VStack(spacing: 8) {
                    HStack { trackIdentity; outputControls }
                    playbackControls
                }
            }
            HStack(spacing: 10) {
                Text(timeLabel(model.timeline.display(model.playback))).frame(width:42,alignment:.trailing)
                TimelineSlider(value:model.timeline.display(model.playback),duration:model.playback.duration,enabled:model.playback.canSeek,begin:model.beginScrub,update:model.scrub,finish:model.endScrub).frame(height:16)
                Text(timeLabel(model.playback.duration)).frame(width:42,alignment:.leading)
            }.font(.system(size:11)).monospacedDigit().foregroundStyle(.secondary)
        }.modifier(ChromeGlassGroup()).onAppear {model.refreshDevices()}.padding(.horizontal,16).padding(.vertical,10).background(.bar)
    }
    private var trackIdentity: some View {
        HStack(spacing: 10) {
            ArtworkView(path:model.playback.path, revision:model.artworkRevision).frame(width:36,height:36)
            VStack(alignment:.leading,spacing:3) {
                Text(model.playback.path.isEmpty ? "Nothing playing" : model.playback.displayTitle).font(.system(size:12,weight:.medium)).lineLimit(1).help(model.playback.path.isEmpty ? "Nothing playing" : model.playback.displayTitle)
                Text(model.playback.artist ?? model.playback.stateLabel).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(minWidth:100,maxWidth:.infinity,alignment:.leading)
            if model.playback.state == 1 {ProgressView().controlSize(.small).accessibilityLabel("Loading audio")}
        }
    }
    private var playbackControls: some View {
        HStack(spacing: 4) {
            transportButton("backward.end.fill", "Previous Track", "Previous Track (⌥⌘P)", enabled:model.canPrevious, action:model.previousTrack)
            transportButton(model.playback.state == 2 ? "pause.fill" : "play.fill", model.playback.state == 2 ? "Pause" : "Play", "Play / Pause (Space)", enabled:!model.playback.path.isEmpty && model.playback.state != 1, action:model.togglePlayback)
            transportButton("stop.fill", "Stop", "Stop playback", enabled:!model.playback.path.isEmpty, action:model.stop)
            transportButton("forward.end.fill", "Next Track", "Next Track (⌥⌘N)", enabled:model.canNext, action:model.nextTrack)
        }.padding(.horizontal,6).padding(.vertical,2).modifier(ControlGlass())
    }
    private var outputControls: some View {
        HStack(spacing: 8) {
            transportButton(model.muted || model.volume == 0 ? "speaker.slash.fill":"speaker.wave.2.fill",model.muted || model.volume == 0 ? "Unmute":"Mute","Mute / Unmute",enabled:true,action:model.toggleMute)
                .accessibilityValue(model.muted || model.volume == 0 ? "Muted":"\(Int((model.volume*100).rounded())) percent")
            Slider(value:Binding(get:{model.volume},set:{model.setVolume($0)}),in:0...1).frame(width:85).controlSize(.small).accessibilityLabel("App volume")
            Menu {
                Button(model.playback.preferredDevice == nil ? "✓ System Default":"System Default") {model.selectOutput(nil)}
                ForEach(model.playback.devices) {device in Button {model.selectOutput(device.id)} label:{Text((model.playback.preferredDevice == device.id ? "✓ ":"")+device.name)}}
                Divider()
                Button("Refresh Devices") {model.refreshDevices()}
                Button("Retry Selected Output") {model.selectOutput(model.playback.preferredDevice)}
            } label:{Image(systemName:"hifispeaker")}.menuStyle(.borderlessButton).frame(width:28).help(model.outputSelection.label).accessibilityLabel("Output device: \(model.outputSelection.label)")
            transportButton("info.circle","Playback audio details","Source and output audio details",enabled:true) {model.refreshDevices();details.toggle()}
                .popover(isPresented:$details) {audioDetails.padding(16).frame(width:320)}
        }.padding(.horizontal, 8).padding(.vertical, 2).modifier(ControlGlass())
    }
    private func transportButton(_ symbol:String, _ label:String, _ help:String, enabled:Bool, action:@escaping ()->Void)->some View {
        Button(action:action) {Image(systemName:symbol).frame(width:InterfaceStyle.controlSize,height:InterfaceStyle.controlSize).contentShape(Rectangle())}
            .buttonStyle(.borderless).accessibilityLabel(label).help(help).disabled(!enabled)
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
