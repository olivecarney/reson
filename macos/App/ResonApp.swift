import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: PlayerModel?
    private var keyMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 49, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               !(NSApp.keyWindow?.firstResponder is NSTextView), let model = self?.model {
                model.togglePlayback(); return nil
            }
            return event
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) { if let path = urls.first?.path { model?.load(path) } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}
@main
struct ResonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = PlayerModel()
    var body: some Scene {
        Window("Reson", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { delegate.model = model; model.startLibrary() }
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Open File…") { model.openFile() }.keyboardShortcut("o")
                Button("Import Folder…") { model.importFolder() }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.importBusy)
                Button("Rescan Folders") { model.rescanFolders() }.disabled(model.importBusy)
                Button("Cancel Import") { model.cancelImport() }.disabled(!model.importBusy) }
            CommandMenu("Playback") {
                Button(model.playback.state == 2 ? "Pause" : "Play") { model.togglePlayback() }.disabled(model.playback.path.isEmpty)
                Button("Stop") { model.stop() }.disabled(model.playback.path.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.showSidebar.toggle() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Toggle Inspector") { model.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
