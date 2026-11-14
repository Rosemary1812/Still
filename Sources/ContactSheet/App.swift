import SwiftUI
import AppKit
@main
struct ContactSheetApp: App {
    @StateObject private var app = AppController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Still", id: "library") {
            Group {
                if let store = app.store {
                    LibraryView().environmentObject(app).environmentObject(store).environmentObject(app.photos).environmentObject(app.player)
                } else { ContentUnavailableView("Could not open your library", systemImage: "externaldrive.badge.exclamationmark", description: Text(app.startupError ?? "Restart Still. Your saved library has not been replaced.")).padding(40) }
            }.frame(minWidth: 780, minHeight: 620)
        }.defaultSize(width: 1000, height: 837)
        .commands { CommandGroup(after: .newItem) { Button("Show Photo Display") { app.showDisplay() }.keyboardShortcut("d", modifiers: [.command,.shift]) } }
        MenuBarExtra("Still", systemImage: "rectangle.stack") { MenuContents().environmentObject(app).environmentObject(app.player) }
        Settings { PreferencesView().environmentObject(app.player).frame(width: 370).padding(24) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@MainActor final class AppController: ObservableObject {
    let photos = PhotoRepository()
    let player = PlaybackController()
    @Published var store: LibraryStore?
    @Published var startupError: String?
    private var display: NSWindow?
    init() {
        do { store = try LibraryStore() } catch { startupError = error.localizedDescription }

    }
    func play(_ album: ContactAlbum) {
        guard let store else { return }
        UserDefaults.standard.set(album.id.uuidString, forKey: "currentAlbum")
        player.select(album: album, ids: store.orderedIDs(album: album), autoplay: UserDefaults.standard.object(forKey:"autoPlay") as? Bool ?? true)
        showDisplay()
    }
    func syncPlayback() {
        guard let store, let album = store.albums.first(where: { $0.id == player.albumID }) else { player.update(ids: []); return }
        player.update(ids: store.orderedIDs(album: album))
    }
    func showDisplay() {
        guard let store else { return }
        if display == nil {
            let window = NSWindow(contentRect: NSRect(x:100,y:100,width:360,height:440), styleMask: [.titled,.closable,.resizable,.miniaturizable,.fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Still Display"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true
            window.minSize = NSSize(width:220,height:240); window.level = .normal
            window.setFrameAutosaveName("ContactSheetDisplay")
            window.contentView = NSHostingView(rootView: DisplayView().environmentObject(self).environmentObject(store).environmentObject(photos).environmentObject(player))
            display = window
        }
        display?.orderFront(nil)
    }
    func hideDisplay() { display?.orderOut(nil) }
}
struct MenuContents: View {
    @EnvironmentObject var app: AppController
    @EnvironmentObject var player: PlaybackController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Show Display") { app.showDisplay() }
        Button("Hide Display") { app.hideDisplay() }
        Divider()
        Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }.disabled(player.ids.isEmpty)
        Button("Next Photo") { player.next() }.disabled(player.ids.isEmpty)
        Menu("Choose Album") { ForEach(app.store?.albums ?? []) { album in Button(album.name) { app.play(album) } } }
        Divider()
        Button("Open Library") { openWindow(id:"library"); NSApp.activate(ignoringOtherApps:true) }
        SettingsLink()
        Button("Quit Still") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
