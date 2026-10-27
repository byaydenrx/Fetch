import AppKit
import SwiftUI

/// Clicks land on what they hit even when Fetch is behind another app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A menu item that runs a closure.
final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    lazy var store = Store(settings: settings)
    private let hover = HoverState()
    private var window: NSWindow!
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Fetch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // An empty unified toolbar makes the title bar tall enough to hold the link field beside the window buttons.
        window.toolbar = NSToolbar(identifier: "Fetch")
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 480, height: 300)
        window.isReleasedWhenClosed = false
        let hosting = FirstClickHostingView(rootView: RootView(store: store, settings: settings, hover: hover))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setFrameAutosaveName("FetchMain")
        if !window.setFrameUsingName("FetchMain") { window.center() }
        NSApp.mainMenu = buildMenu()

        store.start()
        store.requestNotifications()
        if !pending.isEmpty { open(pending); pending = [] }

        // Launched with `open -g` (the way UI checks run while you work), Fetch stays behind your current app.
        if NSApp.isActive { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }

        if let shot = Test.shotPath { Test.capture(window, to: shot, after: 2.5) }
        if let shot = Test.value(after: "--shot-settings") {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.backgroundColor = .windowBackgroundColor
            let view = NSHostingView(rootView: SettingsView(settings: settings))
            panel.setContentSize(view.fittingSize)
            panel.contentView = view
            panel.orderFront(nil)
            Test.capture(panel, to: shot, after: 1)
        }
        if let command = Test.getCommand { Test.download(command, store: store) }
    }

    /// Magnet links and .torrent / .metalink files opened with Fetch.
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { pending += urls } else { open(urls) }
    }

    private func open(_ urls: [URL]) {
        store.drop(urls)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = store.items.filter { $0.status == .active || $0.status == .metadata }.count
        guard running > 0, Test.getCommand == nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit while \(running == 1 ? "a download is" : "\(running) downloads are") running?"
        alert.informativeText = "They'll pick up where they left off the next time you open Fetch."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { store.quit() }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()
        let store = store, settings = settings

        let app = NSMenu()
        app.addItem(withTitle: "About Fetch", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(MenuAction("Settings…", ",") { [weak self] in
            self?.window.makeKeyAndOrderFront(nil)
            store.showSettings = true
        })
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Fetch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Fetch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, to: main, "Fetch")

        let file = NSMenu()
        file.addItem(MenuAction("Open Torrent or Metalink…", "o") { [weak self] in self?.chooseFiles() })
        file.addItem(MenuAction("Choose Download Folder…", "o", [.command, .shift]) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = settings.folder
            panel.prompt = "Save Here"
            if panel.runModal() == .OK, let url = panel.url { settings.folder = url }
        })
        file.addItem(MenuAction("Show Download Folder", "") { NSWorkspace.shared.open(settings.folder) })
        file.addItem(.separator())
        file.addItem(MenuAction("Pause All", "p", [.command, .option]) { store.pauseAll() })
        file.addItem(MenuAction("Resume All", "r", [.command, .option]) { store.resumeAll() })
        file.addItem(MenuAction("Clear Finished", "k") { store.clearFinished() })
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, to: main, "File")

        let edit = NSMenu()
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, to: main, "Edit")

        let windowMenu = NSMenu()
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(MenuAction("Fetch", "0") { [weak self] in self?.window.makeKeyAndOrderFront(nil) })
        add(windowMenu, to: main, "Window")
        NSApp.windowsMenu = windowMenu

        let help = NSMenu()
        help.addItem(MenuAction("aria2c Options", "") {
            NSWorkspace.shared.open(URL(string: "https://aria2.github.io/manual/en/html/aria2c.html#options")!)
        })
        help.addItem(MenuAction("Show Log", "") { NSWorkspace.shared.open(Paths.log) })
        add(help, to: main, "Help")
        return main
    }

    private func add(_ menu: NSMenu, to main: NSMenu, _ title: String) {
        menu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["torrent", "metalink", "meta4"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { store.drop(panel.urls) }
    }
}

import UniformTypeIdentifiers

/// Test modes: `--parse "<text>"`, `--get "<links/flags>"` (downloads, prints progress, quits), `--shot out.png`.
enum Test {
    static let args = CommandLine.arguments

    static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var shotPath: String? { value(after: "--shot") }
    static var getCommand: String? { value(after: "--get") }

    static func parse(_ text: String) {
        let parsed = Command.parse(text)
        for job in parsed.jobs {
            let source: String
            switch job.source {
            case .uris(let uris): source = "uris " + uris.joined(separator: " | ")
            case .torrent(let url): source = "torrent " + url.path
            case .metalink(let url): source = "metalink " + url.path
            }
            let options = job.options.keys.sorted().map { "\($0)=\(job.options[$0]!)" }.joined(separator: " ")
            print("job: \(source)  [\(options)]")
        }
        if !parsed.global.isEmpty { print("global: \(parsed.global)") }
        for problem in parsed.problems { print("problem: \(problem)") }
    }

    @MainActor
    static func download(_ command: String, store: Store) {
        var submitted = false
        var lastLine = ""
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if !submitted {
                    guard store.ready else { return }
                    store.add(text: command)
                    submitted = true
                    return
                }
                let line = store.items.map { "\($0.name) \($0.status.rawValue) \($0.done)/\($0.total) \($0.speed)B/s \($0.connections)conn \($0.error ?? "")" }
                    .joined(separator: " ; ")
                if line != lastLine { print(line); lastLine = line }
                if let problem = store.problem { print("problem: \(problem)") }
                if !store.items.isEmpty, store.items.allSatisfy({ $0.finished || $0.status == .seeding }) {
                    for item in store.items { print("RESULT \(item.status.rawValue) \(item.path ?? "-") \(item.error ?? "")") }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @MainActor
    static func capture(_ window: NSWindow, to path: String, after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Draws the window's own view (screencapture would need Screen Recording permission).
            guard let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("shot \(path)")
            if getCommand == nil { NSApp.terminate(nil) }
        }
    }
}

if let text = Test.value(after: "--parse") {
    Test.parse(text)
    exit(0)
}

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
