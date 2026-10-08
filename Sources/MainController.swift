import AppKit

enum Filter: Equatable { case all, none, project(UUID) }
enum SortMode: String { case modified = "Last Edited", title = "Title", project = "Project" }

final class NoteRowView: NSTableRowView {
    var color: NSColor = .systemYellow
    override func drawSelection(in dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 6, dy: 3)
        color.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
    }
    override var isEmphasized: Bool { get { true } set {} }
}

final class NoteCellView: NSTableCellView {
    let popout = NSButton()
    var onPopout: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        popout.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "ポップアウト ノート")
        popout.isBordered = false; popout.imagePosition = .imageOnly
        popout.toolTip = "ポップアウト ノート"
        popout.target = self; popout.action = #selector(fire)
        popout.translatesAutoresizingMaskIntoConstraints = false
        popout.isHidden = true
        addSubview(popout)
        NSLayoutConstraint.activate([
            popout.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            popout.centerYAnchor.constraint(equalTo: centerYAnchor),
            popout.widthAnchor.constraint(equalToConstant: 26), popout.heightAnchor.constraint(equalToConstant: 24),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { onPopout?() }
    override func mouseEntered(with event: NSEvent) { popout.isHidden = false }
    override func mouseExited(with event: NSEvent) { popout.isHidden = true }
}

final class HoverTable: NSTableView {
    var onHover: ((Int) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) { onHover?(row(at: convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { onHover?(-1) }
}

final class MainController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate {
    private let list = HoverTable()
    private var hoverRow = -1
    private let editor = EditorView(frame: .zero)
    private let rightBG = NSView()
    private let emptyLabel = NSTextField(labelWithString: "ノートがありません  ⌘N で作成")
    private let filterBtn = NSButton()
    private let infoLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let projBtn = NSButton()
    private let taskLabel = NSTextField(labelWithString: "")
    private var topButtons: [NSButton] = []
    private var rows: [Note] = []
    private var filter: Filter = .all
    private var sort: SortMode = .modified
    private var selectedID: UUID?
    private var reloading = false

    init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "MarkSticky"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 640, height: 360)
        w.setFrameAutosaveName("MarkStickyMain")
        if !w.setFrameUsingName("MarkStickyMain") { w.center() }
        super.init(window: w)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
        reload()
        if selectedID == nil { select(rows.first?.id) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func symbolButton(_ name: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)
        b.isBordered = false; b.imagePosition = .imageOnly; b.toolTip = tip
        b.target = self; b.action = action
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    // MARK: layout
    private func build() {
        let content = window!.contentView!
        let split = NSSplitView(frame: content.bounds)
        split.isVertical = true; split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        split.delegate = self

        // ---- left
        let left = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 260, height: content.bounds.height))
        left.material = .sidebar; left.blendingMode = .behindWindow; left.state = .active
        left.autoresizingMask = [.width, .height]
        let top: CGFloat = 78
        let sortB = symbolButton("arrow.up.arrow.down", "Sort", #selector(showSort(_:)))
        sortB.frame = NSRect(x: 12, y: left.bounds.height - 44, width: 26, height: 24); sortB.autoresizingMask = [.minYMargin]
        let newB = symbolButton("square.and.pencil", "New note (⌘N)", #selector(newNote))
        newB.frame = NSRect(x: 260 - 40, y: left.bounds.height - 44, width: 26, height: 24); newB.autoresizingMask = [.minYMargin, .minXMargin]
        filterBtn.isBordered = false
        filterBtn.target = self; filterBtn.action = #selector(showFilter(_:))
        filterBtn.frame = NSRect(x: 44, y: left.bounds.height - 44, width: 260 - 90, height: 24)
        filterBtn.autoresizingMask = [.minYMargin, .width]
        filterBtn.alignment = .center
        filterBtn.font = .systemFont(ofSize: 13, weight: .semibold)
        infoLabel.font = .systemFont(ofSize: 11); infoLabel.textColor = .secondaryLabelColor
        infoLabel.alignment = .center
        infoLabel.frame = NSRect(x: 12, y: left.bounds.height - 62, width: 236, height: 14)
        infoLabel.autoresizingMask = [.minYMargin, .width]
        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.controlSize = .small
        progress.frame = NSRect(x: 40, y: left.bounds.height - 74, width: 180, height: 6)
        progress.autoresizingMask = [.minYMargin, .width]

        let col = NSTableColumn(identifier: .init("c")); col.resizingMask = .autoresizingMask
        col.width = 260; col.minWidth = 100; col.maxWidth = 2000
        list.addTableColumn(col)
        list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        list.headerView = nil; list.rowHeight = 58
        list.backgroundColor = .clear
        list.intercellSpacing = NSSize(width: 0, height: 0)
        list.selectionHighlightStyle = .regular
        list.dataSource = self; list.delegate = self
        list.onHover = { [weak self] r in self?.setHover(r) }
        let menu = NSMenu(); menu.delegate = self; list.menu = menu
        let ls = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: left.bounds.height - top))
        ls.autoresizingMask = [.width, .height]
        ls.documentView = list; ls.hasVerticalScroller = true; ls.drawsBackground = false
        [ls, sortB, newB, filterBtn, infoLabel, progress].forEach { left.addSubview($0) }

        // ---- right
        let right = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: content.bounds.height))
        right.autoresizingMask = [.width, .height]
        rightBG.frame = right.bounds; rightBG.autoresizingMask = [.width, .height]
        rightBG.wantsLayer = true
        right.addSubview(rightBG)

        let bar = NSView(frame: NSRect(x: 0, y: right.bounds.height - 40, width: right.bounds.width, height: 40))
        bar.autoresizingMask = [.width, .minYMargin]
        projBtn.isBordered = false; projBtn.target = self; projBtn.action = #selector(showProject(_:))
        projBtn.imagePosition = .imageLeft; projBtn.alignment = .left; projBtn.font = .systemFont(ofSize: 12, weight: .medium)
        projBtn.frame = NSRect(x: 12, y: 8, width: 220, height: 24)
        taskLabel.font = .systemFont(ofSize: 11); taskLabel.alignment = .left
        taskLabel.frame = NSRect(x: 240, y: 11, width: 180, height: 16)
        let more = symbolButton("ellipsis", "More", #selector(showMore(_:)))
        more.frame = NSRect(x: right.bounds.width - 40, y: 8, width: 28, height: 24); more.autoresizingMask = [.minXMargin]
        let shirt = symbolButton("tshirt", "Color", #selector(showColor(_:)))
        shirt.frame = NSRect(x: right.bounds.width - 76, y: 8, width: 28, height: 24); shirt.autoresizingMask = [.minXMargin]
        topButtons = [more, shirt]
        [projBtn, taskLabel, shirt, more].forEach { bar.addSubview($0) }
        right.addSubview(bar)

        editor.frame = NSRect(x: 24, y: 0, width: right.bounds.width - 48, height: right.bounds.height - 44)
        editor.autoresizingMask = [.width, .height]
        editor.fontSize = 15
        right.addSubview(editor)
        emptyLabel.font = .systemFont(ofSize: 14); emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(x: 0, y: right.bounds.height / 2 - 10, width: right.bounds.width, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        right.addSubview(emptyLabel)

        split.addSubview(left); split.addSubview(right)
        content.addSubview(split)
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 1)
        split.adjustSubviews()
        DispatchQueue.main.async { split.setPosition(260, ofDividerAt: 0) }
    }

    func splitViewDidResizeSubviews(_ n: Notification) { list.sizeLastColumnToFit() }

    func splitView(_ s: NSSplitView, constrainMinCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { 200 }
    func splitView(_ s: NSSplitView, constrainMaxCoordinate p: CGFloat, ofSubviewAt i: Int) -> CGFloat { 420 }

    // MARK: data
    private var currentProject: Project? {
        if case .project(let id) = filter { return Store.shared.project(id) }
        return nil
    }
    private var selectedNote: Note? { Store.shared.notes.first { $0.id == selectedID } }

    @objc private func storeChanged() { reload() }

    func reload() {
        let s = Store.shared
        if case .project(let id) = filter, s.project(id) == nil { filter = .all }
        var r: [Note]
        switch filter {
        case .all: r = s.notes
        case .none: r = s.notes.filter { $0.projectID == nil }
        case .project(let id): r = s.notes.filter { $0.projectID == id }
        }
        switch sort {
        case .modified: r.sort { $0.modified > $1.modified }
        case .title: r.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .project:
            r.sort { (s.project($0.projectID)?.name ?? "~") < (s.project($1.projectID)?.name ?? "~") }
        }
        rows = r
        reloading = true
        list.reloadData()
        if let id = selectedID, let i = rows.firstIndex(where: { $0.id == id }) {
            list.selectRowIndexes([i], byExtendingSelection: false)
        } else if selectedID != nil {
            list.deselectAll(nil)
        }
        reloading = false
        setHover(hoverRow)
        updateHeader()
        updateRight()
    }

    private func updateHeader() {
        let p = currentProject
        let name: String
        switch filter { case .all: name = "すべてのノート"; case .none: name = "未分類"; case .project: name = (p?.completed == true ? "✓ " : "") + (p?.name ?? "") }
        let a = NSMutableAttributedString()
        if let p = p { a.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: theme(p.theme).accent])) }
        a.append(NSAttributedString(string: name + " ▾", attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]))
        filterBtn.attributedTitle = a

        var c = (done: 0, total: 0)
        for n in rows { let t = n.tasks; c.done += t.done; c.total += t.total }
        var info = "\(rows.count) 件"
        if c.total > 0 { info += " ・ タスク \(c.done)/\(c.total)" }
        if let due = p?.due {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: due)).day ?? 0
            info += " ・ 期限 " + (days < 0 ? "\(-days)日超過" : days == 0 ? "今日" : "あと\(days)日")
        }
        infoLabel.stringValue = info
        progress.isHidden = !(p != nil && c.total > 0)
        progress.doubleValue = c.total > 0 ? Double(c.done) / Double(c.total) : 0
    }

    private func updateRight() {
        guard let n = selectedNote else {
            rightBG.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            editor.load(nil); editor.isHidden = true; emptyLabel.isHidden = false
            projBtn.isHidden = true; taskLabel.stringValue = ""
            return
        }
        editor.isHidden = false; emptyLabel.isHidden = true; projBtn.isHidden = false
        let t = theme(n.theme)
        rightBG.layer?.backgroundColor = t.bg.cgColor
        topButtons.forEach { $0.contentTintColor = t.fg.withAlphaComponent(0.6) }
        if editor.note !== n { editor.load(n) }
        let p = Store.shared.project(n.projectID)
        projBtn.image = NSImage(systemSymbolName: p == nil ? "folder" : "folder.fill", accessibilityDescription: nil)
        projBtn.contentTintColor = p == nil ? t.fg.withAlphaComponent(0.6) : (t.name == "Charcoal" ? theme(p!.theme).bg : theme(p!.theme).accent)
        projBtn.attributedTitle = NSAttributedString(string: " " + (p?.name ?? "プロジェクトなし"),
            attributes: [.foregroundColor: t.fg.withAlphaComponent(0.7), .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
        let c = n.tasks
        taskLabel.stringValue = c.total > 0 ? "タスク \(c.done)/\(c.total)" : ""
        taskLabel.textColor = t.fg.withAlphaComponent(0.55)
    }

    func select(_ id: UUID?) {
        // drop an abandoned empty note
        if let old = selectedNote, old.id != id, old.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !old.isOpen {
            Store.shared.notes.removeAll { $0 === old }
        }
        selectedID = id
        reload()
        if let id = id, let i = rows.firstIndex(where: { $0.id == id }) { list.scrollRowToVisible(i) }
    }

    func show(_ note: Note) {
        if case .project(let id) = filter, note.projectID != id { filter = .all }
        select(note.id)
    }

    // MARK: table
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let v = NoteRowView(); v.color = theme(rows[row].theme).bg; return v
    }

    private static let dayFmt: DateFormatter = {
        let d = DateFormatter(); d.locale = Locale(identifier: "ja_JP"); return d
    }()

    private func dateString(_ d: Date) -> String {
        let cal = Calendar.current, f = MainController.dayFmt
        if cal.isDateInToday(d) { f.dateFormat = "H:mm"; return f.string(from: d) }
        if cal.isDateInYesterday(d) { return "昨日" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 99
        if days < 7 { f.dateFormat = "EEEE"; return f.string(from: d) }
        f.dateFormat = "yyyy/MM/dd"; return f.string(from: d)
    }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let n = rows[row]
        let cell = NoteCellView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        cell.popout.contentTintColor = theme(n.theme).fg.withAlphaComponent(0.6)
        cell.onPopout = { AppDelegate.shared.open(n) }
        cell.popout.isHidden = row != hoverRow
        let bar = NSView(frame: NSRect(x: 8, y: 9, width: 6, height: 40))
        bar.wantsLayer = true; bar.layer?.cornerRadius = 3
        bar.layer?.backgroundColor = theme(n.theme).bg.blended(withFraction: 0.12, of: .black)?.cgColor
        let title = NSTextField(labelWithString: n.title)
        title.font = .systemFont(ofSize: 13, weight: .bold); title.lineBreakMode = .byTruncatingTail
                title.textColor = row == tv.selectedRow ? theme(n.theme).fg : .labelColor
        var sub = dateString(n.modified)
        if let p = Store.shared.project(n.projectID) { sub += "  ・  " + p.name }
        let c = n.tasks
        if c.total > 0 { sub += "  ・  \(c.done)/\(c.total)" }
        let subL = NSTextField(labelWithString: sub)
        subL.font = .systemFont(ofSize: 11); subL.lineBreakMode = .byTruncatingTail
        subL.textColor = row == tv.selectedRow ? theme(n.theme).fg.withAlphaComponent(0.7) : .secondaryLabelColor
                [bar, title, subL].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        [title, subL].forEach { $0.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            bar.widthAnchor.constraint(equalToConstant: 6),
            bar.topAnchor.constraint(equalTo: cell.topAnchor, constant: 9),
            bar.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -9),
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -40),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 10),
            subL.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 24),
            subL.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -40),
            subL.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -10),
        ])
        return cell
    }

    private func setHover(_ r: Int) {
        hoverRow = r
        for i in 0..<rows.count {
            (list.view(atColumn: 0, row: i, makeIfNecessary: false) as? NoteCellView)?.popout.isHidden = (i != r)
        }
    }

    func tableViewSelectionDidChange(_ n: Notification) {
        guard !reloading else { return }
        let r = list.selectedRow
        guard r >= 0, r < rows.count else { return }
        select(rows[r].id)
    }

    // MARK: actions — notes
    @objc func newNote() {
        let n = Note()
        n.isOpen = false
        n.projectID = currentProject?.id
        n.theme = currentProject?.theme ?? (Store.shared.notes.count % 6)
        if let f = NSScreen.main?.visibleFrame { n.x = f.midX - 150; n.y = f.midY - 130 }
        Store.shared.notes.append(n)
        select(n.id)
        editor.focus()
    }

    @objc private func openSticky() {
        guard let n = selectedNote else { return }
        AppDelegate.shared.open(n)
    }

    @objc func deleteSelected() {
        guard let n = selectedNote else { return }
        if !n.text.isEmpty {
            let a = NSAlert(); a.messageText = "このノートを削除しますか？"; a.informativeText = "元に戻せません。"
            a.addButton(withTitle: "削除"); a.addButton(withTitle: "キャンセル"); a.alertStyle = .warning
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        let idx = rows.firstIndex { $0 === n } ?? 0
        selectedID = nil
        AppDelegate.shared.delete(n)
        reload()
        select(rows.indices.contains(idx) ? rows[idx].id : rows.last?.id)
    }

    private func popup(_ m: NSMenu, _ sender: NSView) { m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender) }

    @objc private func showColor(_ s: NSButton) {
        let m = NSMenu()
        for (i, t) in themes.enumerated() {
            let it = NSMenuItem(title: t.name, action: #selector(setColor(_:)), keyEquivalent: "")
            it.tag = i; it.target = self; it.image = swatch(t.bg); it.state = i == selectedNote?.theme ? .on : .off
            m.addItem(it)
        }
        popup(m, s)
    }
    @objc private func setColor(_ s: NSMenuItem) { selectedNote?.theme = s.tag; Store.shared.changed() }

    @objc private func showProject(_ s: NSButton) {
        let m = NSMenu()
        let none = NSMenuItem(title: "プロジェクトなし", action: #selector(assignOne(_:)), keyEquivalent: ""); none.target = self
        none.state = selectedNote?.projectID == nil ? .on : .off; m.addItem(none)
        for p in Store.shared.projects {
            let it = NSMenuItem(title: p.name, action: #selector(assignOne(_:)), keyEquivalent: "")
            it.representedObject = p.id; it.target = self; it.image = swatch(theme(p.theme).accent)
            it.state = p.id == selectedNote?.projectID ? .on : .off; m.addItem(it)
        }
        m.addItem(.separator())
        m.addItem(withTitle: "新規プロジェクト…", action: #selector(newProjectForNote), keyEquivalent: "").target = self
        popup(m, s)
    }
    @objc private func assignOne(_ s: NSMenuItem) { selectedNote?.projectID = s.representedObject as? UUID; Store.shared.changed() }
    @objc private func newProjectForNote() {
        if let p = AppDelegate.shared.promptNewProject() { selectedNote?.projectID = p.id; Store.shared.changed() }
    }

    @objc private func showMore(_ s: NSButton) {
        let m = NSMenu()
        m.addItem(withTitle: "別ウィンドウで開く", action: #selector(openSticky), keyEquivalent: "").target = self
        let pv = m.addItem(withTitle: "マークダウンプレビュー", action: #selector(togglePreview), keyEquivalent: ""); pv.target = self
        pv.state = selectedNote?.preview == true ? .on : .off
        let fl = m.addItem(withTitle: "別ウィンドウを最前面に固定", action: #selector(toggleFloat), keyEquivalent: ""); fl.target = self
        fl.state = selectedNote?.floating == true ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "ノートを削除…", action: #selector(deleteSelected), keyEquivalent: "").target = self
        popup(m, s)
    }
    @objc func togglePreview() { selectedNote?.preview.toggle(); Store.shared.changed() }
    @objc private func toggleFloat() { selectedNote?.floating.toggle(); Store.shared.changed() }

    // MARK: actions — list header
    @objc private func showSort(_ s: NSButton) {
        let m = NSMenu()
        for mode in [SortMode.modified, .title, .project] {
            let it = NSMenuItem(title: mode.rawValue, action: #selector(setSort(_:)), keyEquivalent: "")
            it.representedObject = mode.rawValue; it.target = self; it.state = mode == sort ? .on : .off
            m.addItem(it)
        }
        popup(m, s)
    }
    @objc private func setSort(_ s: NSMenuItem) { sort = SortMode(rawValue: s.representedObject as! String) ?? .modified; reload() }

    @objc private func showFilter(_ s: NSButton) {
        let st = Store.shared, m = NSMenu()
        func item(_ t: String, _ f: Filter, _ color: NSColor?, _ count: Int, done: Bool = false) {
            let it = NSMenuItem(title: "\(t)  (\(count))", action: #selector(setFilter(_:)), keyEquivalent: "")
            it.target = self; it.tag = 0
            it.representedObject = FilterBox(f)
            if let c = color { it.image = swatch(c) }
            it.state = f == filter ? .on : .off
            m.addItem(it)
        }
        item("すべてのノート", .all, nil, st.notes.count)
        item("未分類", .none, nil, st.notes.filter { $0.projectID == nil }.count)
        if !st.projects.isEmpty { m.addItem(.separator()) }
        for p in st.projects { item((p.completed ? "✓ " : "") + p.name, .project(p.id), theme(p.theme).accent, st.notes.filter { $0.projectID == p.id }.count) }
        m.addItem(.separator())
        m.addItem(withTitle: "新規プロジェクト…", action: #selector(addProject), keyEquivalent: "").target = self
        if currentProject != nil {
            let sub = NSMenu()
            for (t, a) in [("名前を変更…", #selector(renameProject)), ("期限を設定…", #selector(setDue)), ("完了 / 再開", #selector(toggleDone)),
                           ("色を変更…", #selector(pickProjectColor)), ("プロジェクトを削除…", #selector(deleteProject))] {
                sub.addItem(withTitle: t, action: a, keyEquivalent: "").target = self
            }
            let parent = NSMenuItem(title: "このプロジェクト", action: nil, keyEquivalent: ""); parent.submenu = sub
            m.addItem(parent)
        }
        popup(m, s)
    }
    final class FilterBox: NSObject { let f: Filter; init(_ f: Filter) { self.f = f } }
    @objc private func setFilter(_ s: NSMenuItem) {
        guard let b = s.representedObject as? FilterBox else { return }
        filter = b.f
        reload()
        if let id = selectedID, !rows.contains(where: { $0.id == id }) { select(rows.first?.id) }
    }

    @objc func addProject() {
        if let p = AppDelegate.shared.promptNewProject() { filter = .project(p.id); reload(); select(rows.first?.id) }
    }
    @objc private func renameProject() {
        guard let p = currentProject, let name = promptText("プロジェクト名を変更", "名前", p.name) else { return }
        p.name = name; Store.shared.changed()
    }
    @objc private func deleteProject() {
        guard let p = currentProject else { return }
        let a = NSAlert(); a.messageText = "プロジェクト「\(p.name)」を削除しますか？"; a.informativeText = "ノートは残り、未分類になります。"
        a.addButton(withTitle: "削除"); a.addButton(withTitle: "キャンセル"); a.alertStyle = .warning
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let s = Store.shared
        s.notes.filter { $0.projectID == p.id }.forEach { $0.projectID = nil }
        s.projects.removeAll { $0 === p }
        filter = .all; s.changed()
    }
    @objc private func toggleDone() { currentProject?.completed.toggle(); Store.shared.changed() }
    @objc private func setDue() {
        guard let p = currentProject else { return }
        let pick = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        pick.datePickerStyle = .textFieldAndStepper; pick.datePickerElements = .yearMonthDay
        pick.dateValue = p.due ?? Date()
        let a = NSAlert(); a.messageText = "「\(p.name)」の期限"; a.accessoryView = pick
        a.addButton(withTitle: "設定"); a.addButton(withTitle: "解除"); a.addButton(withTitle: "キャンセル")
        switch a.runModal() {
        case .alertFirstButtonReturn: p.due = pick.dateValue
        case .alertSecondButtonReturn: p.due = nil
        default: return
        }
        Store.shared.changed()
    }
    @objc private func pickProjectColor() {
        let m = NSMenu()
        for (i, t) in themes.enumerated() {
            let it = NSMenuItem(title: t.name, action: #selector(setProjectColor(_:)), keyEquivalent: "")
            it.tag = i; it.target = self; it.image = swatch(t.accent); m.addItem(it)
        }
        m.popUp(positioning: nil, at: NSEvent.mouseLocation.applying(.identity), in: nil)
    }
    @objc private func setProjectColor(_ s: NSMenuItem) { currentProject?.theme = s.tag; Store.shared.changed() }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), window?.firstResponder === list { deleteSelected() } else { super.keyDown(with: event) }
    }
}

extension MainController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let c = list.clickedRow
        guard c >= 0, c < rows.count else { return }
        let n = rows[c]
        select(n.id)
        menu.addItem(withTitle: "別ウィンドウで開く", action: #selector(openSticky), keyEquivalent: "").target = self
        let sub = NSMenu()
        let none = NSMenuItem(title: "プロジェクトなし", action: #selector(assignOne(_:)), keyEquivalent: ""); none.target = self; sub.addItem(none)
        for p in Store.shared.projects {
            let it = NSMenuItem(title: p.name, action: #selector(assignOne(_:)), keyEquivalent: "")
            it.representedObject = p.id; it.target = self; it.image = swatch(theme(p.theme).accent); sub.addItem(it)
        }
        let parent = NSMenuItem(title: "プロジェクトへ移動", action: nil, keyEquivalent: ""); parent.submenu = sub
        menu.addItem(parent)
        menu.addItem(.separator())
        menu.addItem(withTitle: "削除…", action: #selector(deleteSelected), keyEquivalent: "").target = self
    }
}
