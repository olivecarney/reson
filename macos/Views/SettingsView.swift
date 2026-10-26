import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var folder: String?
    @State private var excluded: String?
    @State private var showExcluded = false
    private var busy: Bool { model.importBusy || model.libraryManagementBusy }

    var body: some View {
        TabView {
            Form {
                Section("Playback") {
                    Slider(value: Binding(get: { model.volume }, set: { model.setVolume($0) }), in: 0...1) { Text("App volume") }
                        .accessibilityValue("\(Int((model.volume * 100).rounded())) percent")
                    Toggle("Mute", isOn: Binding(get: { model.muted }, set: { if $0 != model.muted { model.toggleMute() } }))
                    Text("Volume changes affect reson only.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About reson") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                    Text("A lightweight player for local FLAC, WAV and MP3 music.").foregroundStyle(.secondary)
                    if RuntimeStorage.current.isolated { Text("Isolated development storage").font(.caption).foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            librarySettings.tabItem { Label("Library", systemImage: "music.note.list") }
        }.frame(width: 640, height: 480).font(InterfaceStyle.body)
            .background { BackgroundDismissal { dismiss() } }
            .task { model.startLibrary(); await model.refreshSources() }
    }

    private var librarySettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your music library").font(.system(size: 18, weight: .medium))
                    Text("Music stays in its original folders. Rescan after adding or changing files.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.libraryFolders.isEmpty {
                            Label("No music folders added yet", systemImage: "folder")
                                .foregroundStyle(.secondary).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            List(model.libraryFolders, id: \.self, selection: $folder) { path in pathRow(path) }
                                .frame(height: min(140, max(60, CGFloat(model.libraryFolders.count) * 48)))
                        }
                        HStack {
                            Button("Add Folder…") { model.importFolder() }
                            Button("Remove…") { if let folder { model.confirmRemoveFolder(folder) } }
                                .disabled(!model.libraryFolders.contains(folder ?? ""))
                            Spacer()
                            Button("Rescan") { model.rescanFolders() }.disabled(model.libraryFolders.isEmpty)
                        }.disabled(busy)
                    }.padding(8)
                } label: { Text("Music folders").font(.headline) }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if model.excludedPaths.isEmpty {
                            Label("No excluded tracks", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary).padding(.vertical, 6)
                        } else {
                            DisclosureGroup("\(model.excludedPaths.count) excluded \(model.excludedPaths.count == 1 ? "track" : "tracks")", isExpanded: $showExcluded) {
                                List(model.excludedPaths, id: \.self, selection: $excluded) { path in pathRow(path) }
                                    .frame(height: min(140, max(60, CGFloat(model.excludedPaths.count) * 48))).padding(.top, 8)
                                HStack {
                                    Spacer()
                                    Button("Restore Track") { if let excluded { model.restoreExcluded(excluded) } }
                                        .disabled(!model.excludedPaths.contains(excluded ?? "") || busy)
                                }
                            }
                        }
                        Text("Excluded tracks stay out of rescans. Restore a track to add it back.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                } label: { Text("Excluded tracks").font(.headline) }

                if busy || !model.importSummary.isEmpty {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) }
                        Text(model.importSummary.isEmpty ? "Updating library…" : model.importSummary)
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if model.importBusy { Button("Cancel Scan") { model.cancelImport() } }
                    }
                }
                if let error = model.message {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Text("Removing folders or tracks only changes reson's library. Original files are never deleted.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
    }

    private func pathRow(_ path: String) -> some View {
        let url = URL(fileURLWithPath: path)
        return VStack(alignment: .leading, spacing: 3) {
            Text(url.lastPathComponent).lineLimit(1)
            Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }.padding(.vertical, 3).help(path).accessibilityElement(children: .ignore).accessibilityLabel(path)
    }
}
