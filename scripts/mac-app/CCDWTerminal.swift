// =============================================================================
// CCDWTerminal.swift — native macOS wrapper around the CCDW web terminal (ttyd).
// -----------------------------------------------------------------------------
// A thin AppKit + WebKit app that hosts the containerized terminal in a real
// macOS window: no browser chrome (no tabs/URL bar), a native menu bar with
// working Cmd-key shortcuts, native clipboard (WKWebView, no browser paste
// gate), page zoom, and independent terminal windows.
//
// This is a COMPILED Mach-O app bundle (ad-hoc signable), not a script .app —
// so it launches cleanly under Gatekeeper for local use, unlike the AppleScript
// launcher approach the repo abandoned.
//
// Ports (override via env when launched from a shell):
//   CCDW_TTYD_PORT      main tmux session   (default 7681)
//   CCDW_TTYD_NEW_PORT  new tmux window each (default 7682)
// =============================================================================

import Cocoa
import WebKit

let env = ProcessInfo.processInfo.environment
let MAIN_PORT = env["CCDW_TTYD_PORT"] ?? "7681"
let NEW_PORT  = env["CCDW_TTYD_NEW_PORT"] ?? "7682"
let MAIN_URL  = "http://localhost:\(MAIN_PORT)"
let NEW_URL   = "http://localhost:\(NEW_PORT)"

let ZOOM_STEP: CGFloat = 0.1
let ZOOM_MIN:  CGFloat = 0.5
let ZOOM_MAX:  CGFloat = 3.0

func connectErrorHTML(_ url: String) -> String {
    return """
    <!doctype html><html><head><meta charset="utf-8"><style>
      html,body{height:100%;margin:0}
      body{background:#0b0e14;color:#c9d1d9;font:15px -apple-system,BlinkMacSystemFont,sans-serif;
           display:flex;align-items:center;justify-content:center}
      .card{max-width:460px;text-align:center;padding:32px}
      h1{font-size:18px;margin:0 0 12px}
      p{color:#8b949e;line-height:1.5}
      code{background:#161b22;padding:2px 6px;border-radius:4px;color:#79c0ff}
      button{margin-top:20px;background:#238636;border:0;color:#fff;padding:10px 18px;
             border-radius:6px;font-size:14px;cursor:pointer}
    </style></head><body><div class="card">
      <h1>CCDW terminal not reachable</h1>
      <p>Could not connect to <code>\(url)</code>.<br>
         Start the container, then retry:</p>
      <p><code>docker compose up -d</code></p>
      <button onclick="location.reload()">Retry</button>
    </div></body></html>
    """
}

// -----------------------------------------------------------------------------
// One terminal window (its own WKWebView).
// -----------------------------------------------------------------------------
final class TerminalWindowController: NSWindowController, WKNavigationDelegate {
    let webView: WKWebView
    let targetURL: String

    init(url: String, title: String, autosave: String?) {
        self.targetURL = url
        let cfg = WKWebViewConfiguration()
        // Non-persistent store: nothing (bundle, cache, localStorage) survives a
        // relaunch, so a rebuilt ttyd/xterm bundle is always fetched fresh. The
        // terminal has no client state worth persisting — tmux holds the session
        // server-side — so this only kills stale-cache bugs, costs nothing.
        cfg.websiteDataStore = .nonPersistent()
        // Let the container's terminal drive the clipboard without a user gesture.
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 680),
                                 configuration: cfg)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.tabbingMode = .disallowed
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.contentView = webView
        window.center()

        super.init(window: window)
        webView.navigationDelegate = self
        if let name = autosave { window.setFrameAutosaveName(name) }
        load()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func load() {
        guard let u = URL(string: targetURL) else { return }
        // Ignore any cache on every load — always hit ttyd for the live bundle.
        webView.load(URLRequest(url: u,
                                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                timeoutInterval: 30))
    }

    // Purge all WebKit data then reload from origin — nukes any stale cache.
    func clearCacheAndReload() {
        let store = webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            self?.load()
        }
    }

    func setZoom(_ z: CGFloat) {
        webView.pageZoom = max(ZOOM_MIN, min(ZOOM_MAX, z))
    }
    func zoomIn()  { setZoom(webView.pageZoom + ZOOM_STEP) }
    func zoomOut() { setZoom(webView.pageZoom - ZOOM_STEP) }
    func zoomReset() { setZoom(1.0) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        webView.loadHTMLString(connectErrorHTML(targetURL), baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.loadHTMLString(connectErrorHTML(targetURL), baseURL: nil)
    }
}

// -----------------------------------------------------------------------------
// App delegate: owns windows + menu actions.
// -----------------------------------------------------------------------------
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No process-wide URL cache — another guard against serving a stale bundle.
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        openMain()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func frontController() -> TerminalWindowController? {
        if let key = NSApp.keyWindow {
            return controllers.first { $0.window === key }
        }
        return controllers.last
    }

    func openMain() {
        let c = TerminalWindowController(url: MAIN_URL, title: "CCDW Terminal",
                                         autosave: "CCDWTerminalMain")
        controllers.append(c)
        c.showWindow(nil)
    }

    @objc func newTerminalWindow(_ sender: Any?) {
        let c = TerminalWindowController(url: NEW_URL, title: "CCDW Terminal",
                                         autosave: nil)
        // cascade so it doesn't cover the previous one
        if let prev = controllers.last?.window {
            let p = prev.frame.origin
            c.window?.setFrameOrigin(NSPoint(x: p.x + 28, y: p.y - 28))
        }
        controllers.append(c)
        c.showWindow(nil)
    }

    @objc func reloadPage(_ sender: Any?) { frontController()?.webView.reloadFromOrigin() }
    @objc func hardReload(_ sender: Any?) { frontController()?.clearCacheAndReload() }
    @objc func zoomIn(_ sender: Any?)     { frontController()?.zoomIn() }
    @objc func zoomOut(_ sender: Any?)    { frontController()?.zoomOut() }
    @objc func zoomReset(_ sender: Any?)  { frontController()?.zoomReset() }

    // -------------------------------------------------------------------------
    // Menu
    // -------------------------------------------------------------------------
    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About CCDW Terminal",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide CCDW Terminal",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                        action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CCDW Terminal",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Terminal Window",
                         action: #selector(newTerminalWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu — standard responder-chain selectors reach the WKWebView,
        // giving native copy/paste (no browser paste gate) and select-all.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut",  action: Selector(("cut:")),  keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadPage(_:)), keyEquivalent: "r")
        let hard = viewMenu.addItem(withTitle: "Reload (Clear Cache)",
                     action: #selector(hardReload(_:)), keyEquivalent: "r")
        hard.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In",  action: #selector(zoomIn(_:)),  keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        let fs = viewMenu.addItem(withTitle: "Enter Full Screen",
                     action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]

        // Window menu
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winItem.submenu = winMenu
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
