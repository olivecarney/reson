import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var folder: String?
    @State private var excluded: String?
    private var busy: Bool {model.importBusy || model.libraryManagementBusy}
    var body: some View {
        TabView {
            Form {
                Section("Playback") {
                    Slider(value:Binding(get:{model.volume},set:{model.setVolume($0)}),in:0...1) {Text("Volume")}
                    Toggle("Mute",isOn:Binding(get:{model.muted},set:{if $0 != model.muted {model.toggleMute()}}))
                }
                Section("Application") {
                    LabeledContent("Version",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development")
                    Text("Local FLAC, PCM WAV and MP3 playback.").foregroundStyle(.secondary)
                    if RuntimeStorage.current.isolated {Text("Isolated development storage").foregroundStyle(.secondary)}
                }
            }.formStyle(.grouped).tabItem {Label("General",systemImage:"gearshape")}
            VStack(alignment:.leading,spacing:12) {
                Text("Imported music folders").font(.headline)
                List(model.libraryFolders,id:\.self,selection:$folder) {path in
                    Text(path).lineLimit(2).help(path)
                }.frame(minHeight:100)
                HStack {
                    Button("Add Folder…") {model.importFolder()}
                    Button("Remove Folder…") {if let folder {model.confirmRemoveFolder(folder)}}.disabled(!model.libraryFolders.contains(folder ?? ""))
                    Spacer()
                    Button("Rescan Folders") {model.rescanFolders()}.disabled(model.libraryFolders.isEmpty)
                }.disabled(busy)
                Text("Removing tracks or folders only changes Reson's library. Original files are never deleted; playlists remain recoverable.").font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Excluded tracks (\(model.excludedPaths.count))").font(.headline)
                List(model.excludedPaths,id:\.self,selection:$excluded) {path in Text(path).lineLimit(2).help(path)}.frame(minHeight:90)
                HStack {
                    Text("Exclusions survive rescans, restarts and file changes.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Track") {if let excluded {model.restoreExcluded(excluded)}}.disabled(!model.excludedPaths.contains(excluded ?? "") || busy)
                }
                HStack {
                    if model.importBusy {ProgressView().controlSize(.small)}
                    Text(model.importSummary.isEmpty ? "Ready" : model.importSummary).font(.callout)
                    Spacer()
                    if model.importBusy {Button("Cancel Scan") {model.cancelImport()}}
                }
                if let error=model.message {Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)}
            }.padding(20).tabItem {Label("Library",systemImage:"music.note.list")}
        }.frame(width:640,height:480)
        .background { BackgroundDismissal { dismiss() } }
        .task {model.startLibrary();await model.refreshSources()}
    }
}
