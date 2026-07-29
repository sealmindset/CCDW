// =============================================================================
// CCDWTerminal — native macOS terminal for the CCDW (Claude Code) container.
// -----------------------------------------------------------------------------
// A real terminal emulator (SwiftTerm) hosted in a native AppKit window. It
// drives a `docker exec -it` PTY straight into the claude-code container, so
// there is NO web layer (no ttyd, no xterm.js, no WKWebView, no OSC-52). The
// consequence: selection, copy, paste, ⌘C/⌘V, right-click, and Select-All are
// all *genuinely* native — identical to Terminal.app — because the terminal IS
// a native NSView writing to / reading from NSPasteboard.general directly.
//
// Copy model (all four, as specified):
//   • drag-select then ⌘C   — Edit-menu Copy → SwiftTerm copy(_:) → pasteboard
//   • auto-copy on release   — selectionChanged override copies live selection
//   • right-click menu       — Copy / Paste / Select All context menu
//   • ⌘V / right-click paste — pasteboard → PTY (insertText isPaste)
//
// Selection vs. mouse-driven TUIs: SwiftTerm reports the mouse to full-screen
// apps (claude, vim, less) so they stay interactive; holding SHIFT bypasses
// mouse reporting and forces a manual text selection — the same muscle memory
// as Terminal.app + tmux/ssh.
//
// Env overrides:
//   CCDW_CONTAINER   container name           (default "claude-code")
//   CCDW_EXEC_USER   exec as this user        (default "coder")
//   CCDW_EXEC_DIR    working dir in container (default "/home/coder/Documents")
// =============================================================================

import Cocoa
import SwiftTerm

// -----------------------------------------------------------------------------
// Config resolved from the environment (with CCDW defaults).
// -----------------------------------------------------------------------------
let ENV        = ProcessInfo.processInfo.environment
let HOME_DIR   = ENV["HOME"] ?? NSHomeDirectory()
let CONTAINER  = ENV["CCDW_CONTAINER"] ?? "claude-code"
let EXEC_USER  = ENV["CCDW_EXEC_USER"] ?? "coder"
let EXEC_DIR   = ENV["CCDW_EXEC_DIR"]  ?? "/home/coder/Documents"
let SHELL_INIT = "/opt/claude-code-docker/scripts/shell-init.sh"

let FONT_DEFAULT: CGFloat = 13
let FONT_MIN:     CGFloat = 8
let FONT_MAX:     CGFloat = 32

// macOS-dark palette matching the CCDW web UI.
let BG_COLOR     = NSColor(srgbRed: 0x0b/255, green: 0x0e/255, blue: 0x14/255, alpha: 1)
let FG_COLOR     = NSColor(srgbRed: 0xc9/255, green: 0xd1/255, blue: 0xd9/255, alpha: 1)
let CARET_COLOR  = NSColor(srgbRed: 0xc9/255, green: 0xd1/255, blue: 0xd9/255, alpha: 1)

// -----------------------------------------------------------------------------
// Docker discovery. The .app launches with a minimal LaunchServices PATH, so we
// probe the usual Rancher/Docker/Homebrew locations rather than trusting $PATH.
// -----------------------------------------------------------------------------
func resolveDockerPath() -> String? {
    let candidates = [
        "\(HOME_DIR)/.rd/bin/docker",
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
    ]
    let fm = FileManager.default
    for c in candidates where fm.isExecutableFile(atPath: c) { return c }
    // Last resort: whatever is on the inherited PATH.
    for dir in (ENV["PATH"] ?? "").split(separator: ":") {
        let p = "\(dir)/docker"
        if fm.isExecutableFile(atPath: p) { return p }
    }
    return nil
}

let DOCKER = resolveDockerPath()

// Child-process environment: inherit the host env (so docker finds ~/.docker
// config + the active context via $HOME), force a capable TERM, and make sure
// the docker dirs are on PATH for any helper docker itself shells out to.
func childEnvironment() -> [String] {
    var env = ENV
    env["TERM"] = "xterm-256color"
    if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
    let extra = [
        "\(HOME_DIR)/.rd/bin", "/usr/local/bin", "/opt/homebrew/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
    ]
    env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
    return env.map { "\($0.key)=\($0.value)" }
}

// docker exec argument vector. New (⌘N) windows suppress the Claude auto-launch
// so they open on a plain shell, matching the old "New Terminal" behavior.
func dockerExecArgs(newWindow: Bool) -> [String] {
    var a = ["exec", "-it"]
    if newWindow { a += ["-e", "CLAUDE_AUTO_LAUNCH=0"] }
    a += ["-u", EXEC_USER, "-w", EXEC_DIR, CONTAINER,
          "bash", "--init-file", SHELL_INIT]
    return a
}

// Best-effort synchronous check that the container is running, so we can show a
// helpful banner instead of a bare "Error: No such container" from docker.
func containerRunning() -> Bool {
    guard let docker = DOCKER else { return false }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: docker)
    p.arguments = ["ps", "--filter", "name=^\(CONTAINER)$", "--format", "{{.Names}}"]
    p.environment = ENV.merging(["PATH": childEnvArrayPATH()]) { _, new in new }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do {
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == CONTAINER })
    } catch {
        return false
    }
}

// PATH string used by the preflight Process (mirrors childEnvironment()).
func childEnvArrayPATH() -> String {
    let extra = [
        "\(HOME_DIR)/.rd/bin", "/usr/local/bin", "/opt/homebrew/bin",
        "/Applications/Docker.app/Contents/Resources/bin",
    ]
    return (extra + [ENV["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
}

// -----------------------------------------------------------------------------
// CCDWTerminalView — SwiftTerm terminal with native copy niceties layered on:
//   • auto-copy on selection release
//   • a right-click Copy / Paste / Select All context menu
// Everything else (drag-select, ⌘C via Edit menu, ⌘V) is SwiftTerm's own
// native responder-chain behavior.
// -----------------------------------------------------------------------------
final class CCDWTerminalView: LocalProcessTerminalView {
    // Auto-copy: as soon as a selection exists (mouse released with a range),
    // push it to the pasteboard. Guarded by selectionActive so clearing the
    // selection never wipes the clipboard.
    override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        if selectionActive, let text = getSelection(), !text.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }
    }

    // Right-click context menu — Copy (only when something is selected), Paste,
    // Select All. Selectors resolve on this view via SwiftTerm's copy:/paste:/
    // selectAll: (the same ones the Edit menu drives).
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.isEnabled = selectionActive
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        menu.addItem(.separator())
        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        selectAllItem.target = self
        menu.addItem(selectAllItem)
        return menu
    }
}

// -----------------------------------------------------------------------------
// One terminal window: a window owning a CCDWTerminalView bound to a PTY.
// -----------------------------------------------------------------------------
final class TerminalWindowController: NSWindowController, LocalProcessTerminalViewDelegate {
    let term: CCDWTerminalView
    let newWindow: Bool
    private var fontSize: CGFloat = FONT_DEFAULT

    init(title: String, autosave: String?, newWindow: Bool) {
        self.newWindow = newWindow
        let frame = NSRect(x: 0, y: 0, width: 1000, height: 680)
        self.term = CCDWTerminalView(frame: frame)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = title
        window.tabbingMode = .disallowed
        window.contentView = term
        window.center()

        super.init(window: window)

        term.processDelegate = self
        term.autoresizingMask = [.width, .height]
        term.optionAsMetaKey = true           // Option ⇒ Meta/Alt (word-nav, meta binds)
        term.allowMouseReporting = true        // TUIs get the mouse; Shift bypasses to select
        applyTheme()
        if let name = autosave { window.setFrameAutosaveName(name) }

        startSession()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyTheme() {
        term.nativeBackgroundColor = BG_COLOR
        term.nativeForegroundColor = FG_COLOR
        term.caretColor = CARET_COLOR
        setFont(fontSize)
    }

    private func setFont(_ size: CGFloat) {
        fontSize = max(FONT_MIN, min(FONT_MAX, size))
        term.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    // Spawn (or re-spawn) the docker exec PTY into the terminal view.
    func startSession() {
        guard let docker = DOCKER else {
            banner("Docker was not found.\r\n\r\nInstall Rancher Desktop or Docker Desktop, then choose View ▸ Reconnect (⌘R).")
            window?.title = "CCDW Terminal — Docker not found"
            return
        }
        if !containerRunning() {
            banner("The CCDW container “\(CONTAINER)” isn’t running.\r\n\r\nStart it, then choose View ▸ Reconnect (⌘R):\r\n\r\n    docker compose up -d\r\n")
            window?.title = "CCDW Terminal — container not running"
            return
        }
        window?.title = "CCDW Terminal"
        term.startProcess(executable: docker,
                          args: dockerExecArgs(newWindow: newWindow),
                          environment: childEnvironment(),
                          execName: nil)
    }

    // Tear down + rebuild the PTY session in place (⌘R).
    func reconnect() {
        // A fresh view avoids any lingering state from a terminated PTY.
        term.startProcess(executable: DOCKER ?? "/bin/false",
                          args: dockerExecArgs(newWindow: newWindow),
                          environment: childEnvironment(),
                          execName: nil)
        if DOCKER == nil || !containerRunning() { startSession() }
    }

    private func banner(_ text: String) {
        term.feed(text: "\r\n  \(text)\r\n")
    }

    func zoomIn()    { setFont(fontSize + 1) }
    func zoomOut()   { setFont(fontSize - 1) }
    func zoomReset() { setFont(FONT_DEFAULT) }

    // --- LocalProcessTerminalViewDelegate ---
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        if !title.isEmpty { window?.title = title }
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode.map { " (exit \($0))" } ?? ""
        banner("Session ended\(code). Choose View ▸ Reconnect (⌘R) to start a new one.")
        window?.title = "CCDW Terminal — disconnected"
    }
}

// -----------------------------------------------------------------------------
// App delegate: owns windows + menu actions.
// -----------------------------------------------------------------------------
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controllers: [TerminalWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        openMain()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func frontController() -> TerminalWindowController? {
        if let key = NSApp.keyWindow {
            return controllers.first { $0.window === key }
        }
        return controllers.last
    }

    func openMain() {
        let c = TerminalWindowController(title: "CCDW Terminal",
                                         autosave: "CCDWTerminalMain", newWindow: false)
        controllers.append(c)
        c.showWindow(nil)
        c.window?.makeFirstResponder(c.term)
    }

    @objc func newTerminalWindow(_ sender: Any?) {
        let c = TerminalWindowController(title: "CCDW Terminal", autosave: nil, newWindow: true)
        if let prev = controllers.last?.window {
            let p = prev.frame.origin
            c.window?.setFrameOrigin(NSPoint(x: p.x + 28, y: p.y - 28))
        }
        controllers.append(c)
        c.showWindow(nil)
        c.window?.makeFirstResponder(c.term)
    }

    @objc func reconnect(_ sender: Any?) { frontController()?.reconnect() }
    @objc func zoomIn(_ sender: Any?)    { frontController()?.zoomIn() }
    @objc func zoomOut(_ sender: Any?)   { frontController()?.zoomOut() }
    @objc func zoomReset(_ sender: Any?) { frontController()?.zoomReset() }

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
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
        let fileItem = NSMenuItem(); mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Terminal Window",
                         action: #selector(newTerminalWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu — copy:/paste:/selectAll: resolve on the SwiftTerm view via
        // the responder chain, giving native clipboard behavior.
        let editItem = NSMenuItem(); mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")

        // View menu
        let viewItem = NSMenuItem(); mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View"); viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reconnect", action: #selector(reconnect(_:)), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Zoom In",  action: #selector(zoomIn(_:)),  keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        let fs = viewMenu.addItem(withTitle: "Enter Full Screen",
                     action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]

        // Window menu
        let winItem = NSMenuItem(); mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Window"); winItem.submenu = winMenu
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
