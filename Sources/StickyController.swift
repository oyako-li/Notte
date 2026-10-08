import AppKit

final class StickyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class StickyController: NSWindowController, NSWindowDelegate {
    let note: Note
    private let root = NSView()
    private let bar = NSView()
    private let footer = NSTextField(labelWithString: "")
    private let editor = EditorView(frame: .zero)
    private var buttons: [NSButton] = []
    private var projectButton = NSButton()
    private var pinButton = NSButton()
    private var previewButton = NSButton()

    init(note: Note) {
        self.note = note
        let w = StickyWindow(contentRect: NSRect(x: note.x, y: note.y, width: note.w, height: note.h),
                             styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 160, height: 100)
        super.init(window: w)
        w.delegate = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.toolTip = tip
        b.target = self
        b.action = action
        buttons.append(b)
        return b
    }

    private func build() {
        let w = window!
        root.frame = NSRect(origin: .zero, size: w.frame.size)
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        w.contentView = root

        let barH: CGFloat = 26, footH: CGFloat = 18
        bar.frame = NSRect(x: 0, y: root.bounds.height - barH, width: root.bounds.width, height: barH)
        bar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(bar)

        let plus = iconButton("plus", "New note (⌘N)", #selector(newNote))
        plus.frame.origin = NSPoint(x: 6, y: 2)
        projectButton = iconButton("folder", "Project", #selector(pickProject(_:)))
        projectButton.frame.origin = NSPoint(x: 30, y: 2)
        let close = iconButton("xmark", "Close", #selector(closeNote))
        close.autoresizingMask = [.minXMargin]
        close.frame.origin = NSPoint(x: bar.bounds.width - 28, y: 2)
        previewButton = iconButton("eye", "Preview markdown (⌘E)", #selector(togglePreview))
        previewButton.autoresizingMask = [.minXMargin]
        previewButton.frame.origin = NSPoint(x: bar.bounds.width - 52, y: 2)
        pinButton = iconButton("pin", "Keep on top", #selector(toggleFloat))
        pinButton.autoresizingMask = [.minXMargin]
        pinButton.frame.origin = NSPoint(x: bar.bounds.width - 76, y: 2)
        let pal = iconButton("paintpalette", "Color", #selector(pickColor(_:)))
        pal.autoresizingMask = [.minXMargin]
        pal.frame.origin = NSPoint(x: bar.bounds.width - 100, y: 2)
        [plus, projectButton, pal, pinButton, previewButton, close].forEach { bar.addSubview($0) }

        footer.frame = NSRect(x: 10, y: 1, width: root.bounds.width - 20, height: footH - 3)
        footer.autoresizingMask = [.width, .maxYMargin]
        footer.font = .systemFont(ofSize: 10, weight: .medium)
        footer.lineBreakMode = .byTruncatingTail
        root.addSubview(footer)

        editor.frame = NSRect(x: 0, y: footH, width: root.bounds.width, height: root.bounds.height - barH - footH)
        editor.autoresizingMask = [.width, .height]
        root.addSubview(editor)
        editor.load(note)

        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        root.addTrackingArea(area)
        bar.alphaValue = 0
        refresh(force: true)
    }

    func focusEditor() { editor.focus() }

    override func mouseEntered(with event: NSEvent) { bar.animator().alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { if !(window?.isKeyWindow ?? false) { bar.animator().alphaValue = 0 } }

    // MARK: appearance
    @objc private func storeChanged() { refresh(force: false) }

    func refresh(force: Bool) {
        let t = theme(note.theme)
        root.layer?.backgroundColor = t.bg.cgColor
        buttons.forEach { $0.contentTintColor = t.fg.withAlphaComponent(0.6) }
        pinButton.image = NSImage(systemSymbolName: note.floating ? "pin.fill" : "pin", accessibilityDescription: nil)
        previewButton.image = NSImage(systemSymbolName: note.preview ? "eye.fill" : "eye", accessibilityDescription: nil)
        window?.level = note.floating ? .floating : .normal

        if let p = Store.shared.project(note.projectID) {
            projectButton.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
            let c = Store.shared.tasks(in: p)
            let prog = c.total > 0 ? "  ·  \(c.done)/\(c.total) tasks" : ""
            footer.stringValue = "● \(p.name)\(prog)"
            footer.textColor = theme(p.theme).accent
            if t.name == "Charcoal" { footer.textColor = theme(p.theme).bg }
        } else {
            projectButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let c = note.tasks
            footer.stringValue = c.total > 0 ? "\(c.done)/\(c.total) tasks" : ""
            footer.textColor = t.fg.withAlphaComponent(0.5)
        }
    }

    // MARK: actions
    @objc func newNote() { AppDelegate.shared.newNote(project: note.projectID, near: window) }

    @objc func closeNote() { window?.close() }

    @objc func togglePreview() {
        note.preview.toggle()
        Store.shared.changed()
    }

    @objc func toggleFloat() {
        note.floating.toggle()
        Store.shared.changed()
    }

    @objc func pickColor(_ sender: NSButton) {
        let m = NSMenu()
        for (i, t) in themes.enumerated() {
            let it = NSMenuItem(title: t.name, action: #selector(setColor(_:)), keyEquivalent: "")
            it.tag = i; it.target = self
            it.image = swatch(t.bg)
            it.state = i == note.theme ? .on : .off
            m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func setColor(_ s: NSMenuItem) { note.theme = s.tag; Store.shared.changed() }

    @objc func pickProject(_ sender: NSButton) {
        let m = NSMenu()
        let none = NSMenuItem(title: "No Project", action: #selector(setProject(_:)), keyEquivalent: "")
        none.target = self; none.state = note.projectID == nil ? .on : .off
        m.addItem(none)
        for p in Store.shared.projects where !p.completed || p.id == note.projectID {
            let it = NSMenuItem(title: p.name, action: #selector(setProject(_:)), keyEquivalent: "")
            it.representedObject = p.id; it.target = self
            it.image = swatch(theme(p.theme).accent)
            it.state = p.id == note.projectID ? .on : .off
            m.addItem(it)
        }
        m.addItem(.separator())
        let np = NSMenuItem(title: "New Project…", action: #selector(newProjectForNote), keyEquivalent: "")
        np.target = self; m.addItem(np)
        let mg = NSMenuItem(title: "Main Window…", action: #selector(AppDelegate.showManager), keyEquivalent: "")
        mg.target = AppDelegate.shared; m.addItem(mg)
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func setProject(_ s: NSMenuItem) {
        note.projectID = s.representedObject as? UUID
        Store.shared.changed()
    }

    @objc private func newProjectForNote() {
        if let p = AppDelegate.shared.promptNewProject() {
            note.projectID = p.id
            Store.shared.changed()
        }
    }

    @objc func deleteNote() {
        if !note.text.isEmpty {
            let a = NSAlert()
            a.messageText = "Delete this note?"
            a.informativeText = "This cannot be undone."
            a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
            a.alertStyle = .warning
            if a.runModal() != .alertFirstButtonReturn { return }
        }
        AppDelegate.shared.delete(note)
    }

    // MARK: window delegate
    func windowDidMove(_ n: Notification) { saveFrame() }
    func windowDidResize(_ n: Notification) { saveFrame() }
    private func saveFrame() {
        guard let f = window?.frame else { return }
        note.x = f.origin.x; note.y = f.origin.y; note.w = f.width; note.h = f.height
        Store.shared.changed(notify: false)
    }
    func windowDidBecomeKey(_ n: Notification) { bar.animator().alphaValue = 1 }
    func windowDidResignKey(_ n: Notification) { bar.animator().alphaValue = 0 }
    func windowWillClose(_ n: Notification) {
        if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppDelegate.shared.delete(note, closeWindow: false)
        } else {
            note.isOpen = false
            Store.shared.changed()
        }
        AppDelegate.shared.controllers[note.id] = nil
    }
}

func swatch(_ c: NSColor) -> NSImage {
    let img = NSImage(size: NSSize(width: 12, height: 12))
    img.lockFocus()
    c.setFill()
    NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
    NSColor.black.withAlphaComponent(0.25).setStroke()
    NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 9, height: 9)).stroke()
    img.unlockFocus()
    return img
}
