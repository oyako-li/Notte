import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    var controllers: [UUID: StickyController] = [:]
    var manager: MainController?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        Store.shared.load()
        buildMenu()
        buildStatusItem()
        if Store.shared.notes.isEmpty { Store.shared.notes.append(welcomeNote()) }
        for n in Store.shared.notes where n.isOpen { open(n) }
        showManager()
    }

    func applicationWillTerminate(_ n: Notification) { Store.shared.saveNow() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows f: Bool) -> Bool {
        showManager()
        return true
    }

    // MARK: notes
    func open(_ note: Note) {
        note.isOpen = true
        if let c = controllers[note.id] { c.window?.makeKeyAndOrderFront(nil); return }
        let c = StickyController(note: note)
        controllers[note.id] = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
        Store.shared.changed()
    }

    func newNote(project: UUID?, near: NSWindow?) {
        let n = Note()
        var origin = NSPoint(x: 200, y: 400)
        if let f = near?.frame { origin = NSPoint(x: f.origin.x + 28, y: f.origin.y - 28) }
        else if let f = NSScreen.main?.visibleFrame { origin = NSPoint(x: f.midX - 150 + CGFloat(controllers.count % 6) * 24, y: f.midY - CGFloat(controllers.count % 6) * 24) }
        n.x = origin.x; n.y = origin.y
        n.projectID = project
        if let p = Store.shared.project(project) { n.theme = p.theme } else { n.theme = Store.shared.notes.count % 6 }
        Store.shared.notes.append(n)
        open(n)
        controllers[n.id]?.window?.makeFirstResponder(controllers[n.id]?.window?.contentView?.subviews.compactMap { ($0 as? NSScrollView)?.documentView }.first)
    }

    func delete(_ note: Note, closeWindow: Bool = true) {
        let c = controllers[note.id]
        controllers[note.id] = nil
        Store.shared.notes.removeAll { $0 === note }
        Store.shared.changed()
        if closeWindow, let w = c?.window { w.delegate = nil; w.close() }
    }

    func promptNewProject() -> Project? {
        guard let name = promptText("New Project", "Project name") else { return nil }
        let p = Project(name: name, theme: Store.shared.projects.count % 6)
        Store.shared.projects.append(p)
        Store.shared.changed()
        return p
    }

    func welcomeNote() -> Note {
        let n = Note()
        n.isOpen = false
        n.text = """
        # Welcome to MarkSticky
        Write **bold**, *italic*, ~~strike~~ and `code`.

        - [ ] Click a checkbox to toggle it
        - [x] Markdown renders as you type
        - [ ] Press ⌘E for clean preview
        - [ ] Group notes with the folder button

        > Open Project Manager with ⇧⌘M
        """
        if let f = NSScreen.main?.visibleFrame { n.x = f.midX - 150; n.y = f.midY - 130 }
        return n
    }

    @objc func newNoteAction() {
        if NSApp.keyWindow?.windowController === manager || NSApp.keyWindow == nil { showManager(); manager?.newNote(); return }
        let proj = (NSApp.keyWindow?.windowController as? StickyController)?.note.projectID
        newNote(project: proj, near: NSApp.keyWindow)
    }

    @objc func showManager() {
        if manager == nil { manager = MainController() }
        manager?.showWindow(nil)
        manager?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func newProjectAction() { _ = promptNewProject(); showManager() }

    @objc func showAllNotes() {
        for n in Store.shared.notes { open(n) }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hideAllNotes() { controllers.values.forEach { $0.window?.orderOut(nil) } }

    @objc func deleteCurrent() { (NSApp.keyWindow?.windowController as? StickyController)?.deleteNote() }
    @objc func togglePreviewCurrent() { (NSApp.keyWindow?.windowController as? StickyController)?.togglePreview() }
    @objc func toggleFloatCurrent() { (NSApp.keyWindow?.windowController as? StickyController)?.toggleFloat() }
    @objc func openNoteItem(_ s: NSMenuItem) { if let n = s.representedObject as? Note { open(n) } }

    // MARK: status item
    func buildStatusItem() {
        let it = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        it.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "MarkSticky")
        let m = NSMenu(); m.delegate = self
        it.menu = m
        statusItem = it
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()
        menu.addItem(withTitle: "New Note", action: #selector(newNoteAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Main Window", action: #selector(showManager), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show All Notes", action: #selector(showAllNotes), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide All Notes", action: #selector(hideAllNotes), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let s = Store.shared
        for p in [nil] + s.projects.map({ Optional($0) }) {
            let ns = s.notes.filter { $0.projectID == p?.id }.sorted { $0.modified > $1.modified }.prefix(12)
            guard !ns.isEmpty else { continue }
            let h = NSMenuItem(title: p?.name ?? "No Project", action: nil, keyEquivalent: ""); h.isEnabled = false
            menu.addItem(h)
            for n in ns {
                let it = NSMenuItem(title: String(n.title.prefix(40)), action: #selector(openNoteItem(_:)), keyEquivalent: "")
                it.representedObject = n; it.target = self; it.image = swatch(theme(n.theme).bg)
                menu.addItem(it)
            }
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MarkSticky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    // MARK: main menu
    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let mi = NSMenuItem(); main.addItem(mi)
            let m = NSMenu(title: title); mi.submenu = m
            items.forEach { m.addItem($0) }
        }
        func it(_ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        let me = self
        add("MarkSticky", [
            it("About MarkSticky", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            it("Hide MarkSticky", #selector(NSApplication.hide(_:)), "h"),
            it("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            it("Quit MarkSticky", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            it("New Note", #selector(newNoteAction), "n", target: me),
            it("New Project…", #selector(newProjectAction), "N", [.command, .shift], target: me),
            it("Show Main Window", #selector(showManager), "M", [.command, .shift], target: me),
            .separator(),
            it("Open All as Sticky Windows", #selector(showAllNotes), "", target: me),
            it("Hide All Notes", #selector(hideAllNotes), "", target: me),
            .separator(),
            it("Close Note", #selector(NSWindow.performClose(_:)), "w"),
            it("Delete Note…", #selector(deleteCurrent), "\u{8}", [.command], target: me),
        ])
        add("Edit", [
            it("Undo", Selector(("undo:")), "z"),
            it("Redo", Selector(("redo:")), "Z", [.command, .shift]),
            .separator(),
            it("Cut", #selector(NSText.cut(_:)), "x"),
            it("Copy", #selector(NSText.copy(_:)), "c"),
            it("Paste", #selector(NSText.paste(_:)), "v"),
            it("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            it("Find…", #selector(NSResponder.performTextFinderAction(_:)), "f"),
        ])
        (main.items.last!.submenu!.items.last!).tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        add("Format", [
            it("Bold", #selector(NoteTextView.mdBold(_:)), "b"),
            it("Italic", #selector(NoteTextView.mdItalic(_:)), "i"),
            it("Strikethrough", #selector(NoteTextView.mdStrike(_:)), "x", [.command, .shift]),
            it("Inline Code", #selector(NoteTextView.mdCode(_:)), "e", [.command, .shift]),
            it("Link", #selector(NoteTextView.mdLink(_:)), "k"),
            .separator(),
            it("Heading (cycle)", #selector(NoteTextView.mdHeading(_:)), "h", [.command, .shift]),
            it("Bullet List", #selector(NoteTextView.mdBullet(_:)), "8", [.command, .shift]),
            it("Task Item", #selector(NoteTextView.mdTask(_:)), "l", [.command, .shift]),
            it("Quote", #selector(NoteTextView.mdQuote(_:)), "'", [.command]),
            .separator(),
            it("Toggle Markdown Preview", #selector(togglePreviewCurrent), "e", target: me),
        ])
        add("Window", [
            it("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            it("Keep on Top", #selector(toggleFloatCurrent), "t", [.command, .option], target: me),
            it("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }
}
