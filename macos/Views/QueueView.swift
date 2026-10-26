import SwiftUI

struct QueueView: View {
    @Bindable var model: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Play Queue").font(.system(size: 20, weight: .semibold))
                    Text(model.session.queue.isEmpty ? "Queued tracks play before the active list." : "\(model.session.queue.count) pending \(model.session.queue.count == 1 ? "track" : "tracks") · plays before the active list")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !model.session.queue.isEmpty {
                    Button("Clear Queue") { model.session.clearQueue() }
                }
                Button("Done") { model.showQueue = false }.keyboardShortcut(.cancelAction)
            }.padding(20)
            if !model.playback.path.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: model.playback.state == 2 ? "speaker.wave.2" : "music.note").foregroundStyle(.secondary)
                    Text("Now playing").foregroundStyle(.secondary)
                    Text(model.playback.displayTitle).lineLimit(1).help(model.playback.displayTitle)
                    Spacer()
                }.font(.system(size: 12)).padding(.horizontal, 20).padding(.bottom, 14)
            }
            Divider()
            if model.session.queue.isEmpty {
                EmptyState(symbol: "list.bullet", title: "Your queue is empty", detail: "Right-click a track and choose Play Next or Add to Queue. Your active list continues when the queue ends.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TrackTable(tracks: model.queueTracks, selection: $model.queueSelection, play: model.playQueued,
                           artworkRevision: model.artworkRevision, sourceID: "queue", move: model.moveQueued,
                           remove: model.removeQueued, showQueue: {})
                Divider()
                Text("Drag to reorder · Delete to remove · ⌥⌘↑ / ⌥⌘↓ to move")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }.frame(width: 720, height: 440).background(InterfaceStyle.background).font(InterfaceStyle.body).preferredColorScheme(.dark)
    }
}
