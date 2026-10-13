import SwiftUI
struct QueueView: View {
    @Bindable var model:PlayerModel
    var body: some View {
        VStack(spacing:0) {
            HStack {VStack(alignment:.leading,spacing:4) {Text("Play Queue").font(.title2); Text("Queued tracks play first, then "+(model.session.label.isEmpty ? "the active sequence." : model.session.label+".")).font(.caption).foregroundStyle(.secondary)}; Spacer(); Button("Clear Queue") {model.session.clearQueue()}.disabled(model.session.queue.isEmpty); Button("Done") {model.showQueue=false}.keyboardShortcut(.cancelAction)}.padding(20)
            Divider()
            ZStack {
                TrackTable(tracks:model.queueTracks,selection:$model.queueSelection,play:model.playQueued,artworkRevision:model.artworkRevision,sourceID:"queue",move:model.moveQueued,remove:model.removeQueued,showQueue:{})
                if model.session.queue.isEmpty {Text("The queue is empty. Use Play Next or Add to Queue in a track’s context menu.").foregroundStyle(.secondary).padding(24).allowsHitTesting(false)}
            }
            Text("Drag to reorder · Delete to remove · ⌘⌥↑ / ⌘⌥↓ to move selected rows").font(.caption).foregroundStyle(.secondary).padding(12)
        }.frame(minWidth:680,minHeight:360).preferredColorScheme(.dark)
    }
}
