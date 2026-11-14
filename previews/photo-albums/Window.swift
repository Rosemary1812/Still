import AppKit
import WebKit
final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let appMenu = NSMenu()
        let item = NSMenuItem()
        appMenu.addItem(item)
        let menu = NSMenu()
        menu.addItem(withTitle: "退出相册预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        NSApp.mainMenu = appMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 837), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "相册 · 照片墙与双页阅读"
        window.minSize = NSSize(width: 760, height: 650)
        window.center()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView = webView
        let root = Bundle.main.resourceURL!
        webView.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
