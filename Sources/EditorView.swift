import AppKit

/// Markdown editor for one Note (shared by sticky windows and the main window).
final class EditorView: NSView, NSTextViewDelegate, NSTextStorageDelegate {
    let scroll = NSScrollView()
    let tv = NoteTextView()
    private(set) var note: Note?
    var fontSize: CGFloat = 14
    private var styling = false
    private var lastTheme = -1, lastPreview = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        addSubview(scroll)

        tv.frame = scroll.contentView.bounds
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 8, height: 4)
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.delegate = self
        tv.textStorage?.delegate = self
        scroll.documentView = tv
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    func load(_ n: Note?) {
        note = n
        tv.string = n?.text ?? ""
        tv.isEditable = n != nil
        tv.undoManager?.removeAllActions()
        refresh(force: true)
    }

    @objc private func storeChanged() { refresh(force: false) }

    private var currentTheme: Theme { theme(note?.theme ?? 0) }

    func refresh(force: Bool) {
        guard let n = note else { tv.string = ""; return }
        let t = theme(n.theme)
        tv.insertionPointColor = t.fg
        tv.selectedTextAttributes = [.backgroundColor: t.accent.withAlphaComponent(0.3)]
        tv.previewMode = n.preview
        let focused = window?.isKeyWindow == true && window?.firstResponder === tv
        if tv.string != n.text, !tv.hasMarkedText(), !focused {
            let sel = tv.selectedRange()
            tv.string = n.text
            tv.setSelectedRange(NSRange(location: min(sel.location, (n.text as NSString).length), length: 0))
            restyle(); return
        }
        if force || lastTheme != n.theme || lastPreview != n.preview { restyle() }
        lastTheme = n.theme; lastPreview = n.preview
    }

    func restyle() {
        guard let ts = tv.textStorage, !styling, !tv.hasMarkedText() else { return }
        styling = true
        let sel = tv.selectedRange()
        MD.style(ts, theme: currentTheme, preview: note?.preview ?? false, size: fontSize)
        if NSMaxRange(sel) <= ts.length { tv.setSelectedRange(sel) }
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: currentTheme.fg]
        styling = false
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !styling, !tv.hasMarkedText() else { return }
        styling = true
        MD.style(textStorage, theme: currentTheme, preview: note?.preview ?? false, size: fontSize)
        styling = false
    }

    func textDidChange(_ notification: Notification) {
        guard let n = note else { return }
        n.text = tv.string
        n.modified = Date()
        if !tv.hasMarkedText() { restyle() }
        Store.shared.changed()
    }

    func focus() { window?.makeFirstResponder(tv) }
}
