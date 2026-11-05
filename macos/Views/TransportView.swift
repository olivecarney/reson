import SwiftUI

/// Floating Liquid Glass player, after IINA's on-screen controller: identity on the leading
/// edge, transport centred, output on the trailing edge, and a full-width scrubber beneath.
struct TransportView: View {
    @Bindable var model: PlayerModel
    @State private var details = false

    var body: some View {
        VStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                // Wide: three columns with the transport optically centred.
                HStack(spacing: 12) {
                    trackIdentity.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    playbackControls.fixedSize()
                    outputControls.fixedSize().frame(minWidth: 180, maxWidth: .infinity, alignment: .trailing)
                }
                // Compact: identity gets its own row so titles stay readable; below it, volume,
                // centred transport and output share a row, as in IINA's narrow controller.
                VStack(spacing: 6) {
                    trackIdentity.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        volumeControls(sliderWidth: 56).frame(maxWidth: .infinity, alignment: .leading)
                        playbackControls.fixedSize()
                        deviceControls.fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            HStack(spacing: 8) {
                Text(timeLabel(model.timeline.display(model.playback))).frame(width: 40, alignment: .trailing)
                TimelineSlider(value: model.timeline.display(model.playback), duration: model.playback.duration,
                               enabled: model.playback.canSeek, begin: model.beginScrub, update: model.scrub, finish: model.endScrub)
                    .disabled(!model.playback.canSeek).frame(height: 16)
                Text(timeLabel(model.playback.duration)).frame(width: 40, alignment: .leading)
            }
            .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .floatingGlass()
        .onAppear { model.refreshDevices() }
    }

    private var trackIdentity: some View {
        HStack(spacing: 10) {
            ArtworkView(path: model.playback.path, revision: model.artworkRevision)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.playback.path.isEmpty ? "Not Playing" : model.playback.displayTitle)
                    .font(.body.weight(.semibold)).lineLimit(1)
                    .help(model.playback.path.isEmpty ? "Not Playing" : model.playback.displayTitle)
                Text(identityDetail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.playback.state == 1 { ProgressView().controlSize(.small).accessibilityLabel("Loading audio") }
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    private var identityDetail: String {
        if model.playback.path.isEmpty {
            return model.canTogglePlayback ? "Double-click a track to play" : "Open a file or import a folder"
        }
        return [model.playback.artist, model.playback.album].compactMap { $0 }.joined(separator: " — ")
            .nonEmpty ?? model.playback.stateLabel
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            transportButton("backward.fill", "Previous Track", "Previous Track (⌥⌘P)", enabled: model.canPrevious, action: model.previousTrack)
                .font(.title3)
            transportButton(model.playback.state == 2 ? "pause.fill" : "play.fill", model.playback.state == 2 ? "Pause" : "Play",
                            "Play / Pause (Space)", enabled: model.canTogglePlayback, action: model.togglePlayback, size: 38)
                .font(.system(size: 24))
                .contentTransition(.symbolEffect(.replace))
            transportButton("forward.fill", "Next Track", "Next Track (⌥⌘N)", enabled: model.canNext, action: model.nextTrack)
                .font(.title3)
            transportButton("stop.fill", "Stop", "Stop playback", enabled: !model.playback.path.isEmpty, action: model.stop)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var outputControls: some View {
        HStack(spacing: 6) { volumeControls(sliderWidth: 80); deviceControls }
    }

    private func volumeControls(sliderWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            transportButton(volumeSymbol, isSilent ? "Unmute" : "Mute", "Mute / Unmute", enabled: true, action: model.toggleMute)
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityValue(isSilent ? "Muted" : "\(Int((model.volume * 100).rounded())) percent")
            Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...1)
                .frame(width: sliderWidth).controlSize(.mini).accessibilityLabel("App volume")
        }
    }

    private var deviceControls: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Output", selection: Binding(get: { model.playback.preferredDevice }, set: { model.selectOutput($0) })) {
                    Text("System Default").tag(String?.none)
                    ForEach(model.playback.devices) { device in Text(device.name).tag(Optional(device.id)) }
                }.pickerStyle(.inline)
                Divider()
                Button("Refresh Devices") { model.refreshDevices() }
                Button("Retry Selected Output") { model.selectOutput(model.playback.preferredDevice) }
            } label: {
                Image(systemName: "hifispeaker")
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).foregroundStyle(.secondary)
            .frame(width: InterfaceStyle.controlSize)
            .help(model.outputSelection.label).accessibilityLabel("Output device: \(model.outputSelection.label)")
            transportButton("info.circle", "Playback audio details", "Source and output audio details", enabled: true) {
                model.refreshDevices(); details.toggle()
            }
            .foregroundStyle(.secondary)
            .popover(isPresented: $details, arrowEdge: .top) { audioDetails.padding(16).frame(width: 320) }
        }
    }

    private var isSilent: Bool { model.muted || model.volume == 0 }
    private var volumeSymbol: String {
        if isSilent { return "speaker.slash.fill" }
        return model.volume < 0.34 ? "speaker.wave.1.fill" : (model.volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }

    private func transportButton(_ symbol: String, _ label: String, _ help: String, enabled: Bool,
                                 action: @escaping () -> Void, size: CGFloat = InterfaceStyle.controlSize) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: size, height: size).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).accessibilityLabel(label).help(help).disabled(!enabled)
    }

    private var audioDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.outputSelection.label).font(.headline)
            Text("Source: \(model.playback.format) · \(model.playback.rate) Hz · \(model.playback.channels) channels · \(model.playback.bits == 0 ? "unknown depth" : "\(model.playback.bits)-bit")")
            if let rate = model.playback.outputRate, let channels = model.playback.outputChannels {
                Text("Output stream: \(rate) Hz · \(channels) channels · \(model.playback.outputFormat ?? "unknown format")")
                Text(model.playback.convertsOutput ? "Rate or channel conversion is active. Floating-point mixing and CoreAudio conversion may also apply." : "Floating-point mixing and CoreAudio conversion may apply.")
                    .foregroundStyle(.secondary)
            } else {
                Text("No active output stream").foregroundStyle(.secondary)
            }
            Text(model.playback.stateLabel)
            if let error = model.playback.operationError { Text(error).foregroundStyle(.orange) }
            if let error = model.playback.error { Text(error).foregroundStyle(.orange) }
            if let notice = model.playback.outputNotice { Text(notice).foregroundStyle(.secondary) }
        }
        .font(.callout).textSelection(.enabled)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
