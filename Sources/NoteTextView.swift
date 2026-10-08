import AppKit

final class NoteTextView: NSTextView {
    var previewMode = false { didSet { isEditable = !previewMode } }

    // MARK: click handling (task checkboxes, links)
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let lm = layoutManager, let tc = textContainer, string.count > 0 {
            let o = textContainerOrigin
            let pt = NSPoint(x: p.x - o.x, y: p.y - o.y)
            var frac: CGFloat = 0
            let idx = lm.characterIndex(for: pt, in: tc, fractionOfDistanceBetweenInsertionPoints: &frac)
            let used = lm.lineFragmentUsedRect(forGlyphAt: min(lm.glyphIndexForCharacter(at: idx), max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
            if pt.x <= used.maxX + 2, idx < (string as NSString).length {
                if toggleCheckbox(at: idx) { return }
                if previewMode || event.modifierFlags.contains(.command),
                   let u = textStorage?.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                    NSWorkspace.shared.open(u); return
                }
            }
        }
        super.mouseDown(with: event)
    }

    private func toggleCheckbox(at idx: Int) -> Bool {
        let ns = string as NSString
        let line = ns.lineRange(for: NSRange(location: idx, length: 0))
        guard let m = MD.list.firstMatch(in: ns.substring(with: line), range: NSRange(location: 0, length: line.length)),
              m.range(at: 3).location != NSNotFound else { return false }
        let box = NSRange(location: line.location + m.range(at: 3).location, length: 3)
        guard NSLocationInRange(idx, box) else { return false }
        let on = ns.substring(with: NSRange(location: box.location + 1, length: 1)) == " "
        let r = NSRange(location: box.location + 1, length: 1)
        if shouldChangeText(in: r, replacementString: on ? "x" : " ") {
            textStorage?.replaceCharacters(in: r, with: on ? "x" : " ")
            didChangeText()
        }
        return true
    }

    // MARK: editing helpers
    private func replace(_ r: NSRange, with s: String) {
        if shouldChangeText(in: r, replacementString: s) {
            textStorage?.replaceCharacters(in: r, with: s)
            didChangeText()
        }
    }

    private func wrap(_ m: String) {
        let r = selectedRange(), ns = string as NSString, n = (m as NSString).length
        if r.length == 0 {
            replace(r, with: m + m)
            setSelectedRange(NSRange(location: r.location + n, length: 0)); return
        }
        let sel = ns.substring(with: r)
        let selNS = sel as NSString
        if selNS.length >= 2 * n, sel.hasPrefix(m), sel.hasSuffix(m), !(n == 1 && (sel.hasPrefix(m + m))) {
            let inner = selNS.substring(with: NSRange(location: n, length: selNS.length - 2 * n))
            replace(r, with: inner)
            setSelectedRange(NSRange(location: r.location, length: (inner as NSString).length))
        } else {
            replace(r, with: m + sel + m)
            setSelectedRange(NSRange(location: r.location + n, length: r.length))
        }
    }

    @objc func mdBold(_ s: Any?) { wrap("**") }
    @objc func mdItalic(_ s: Any?) { wrap("*") }
    @objc func mdStrike(_ s: Any?) { wrap("~~") }
    @objc func mdCode(_ s: Any?) { wrap("`") }

    @objc func mdLink(_ s: Any?) {
        let r = selectedRange(), ns = string as NSString
        let sel = ns.substring(with: r)
        replace(r, with: "[\(sel)](https://)")
        let loc = r.location + (sel as NSString).length + 3
        setSelectedRange(NSRange(location: loc, length: 8))
    }

    private func editLines(_ f: (String) -> String) {
        let ns = string as NSString
        let lines = ns.lineRange(for: selectedRange())
        let old = ns.substring(with: lines)
        var parts = old.components(separatedBy: "\n")
        let trailing = parts.last == "" ; if trailing { parts.removeLast() }
        let new = parts.map(f).joined(separator: "\n") + (trailing ? "\n" : "")
        replace(lines, with: new)
        setSelectedRange(NSRange(location: lines.location, length: (new as NSString).length - (trailing ? 1 : 0)))
    }

    @objc func mdHeading(_ s: Any?) {
        editLines { l in
            if let m = MD.heading.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) {
                let rest = (l as NSString).substring(from: m.range.length)
                return m.range(at: 1).length >= 3 ? rest : String(repeating: "#", count: m.range(at: 1).length + 1) + " " + rest
            }
            return "# " + l
        }
    }

    @objc func mdBullet(_ s: Any?) {
        editLines { l in
            if let m = MD.list.firstMatch(in: l, range: NSRange(location: 0, length: (l as NSString).length)) {
                return (l as NSString).substring(from: m.range.length)
            }
            return "• " + l
        }
    }

    @objc func mdTask(_ s: Any?) {
        editLines { l in
            let ns = l as NSString
            guard let m = MD.list.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { return "• [ ] " + l }
            if m.range(at: 3).location != NSNotFound {
                return ns.substring(to: m.range(at: 3).location) + ns.substring(from: m.range.length)
            }
            return ns.substring(to: m.range.length) + "[ ] " + ns.substring(from: m.range.length)
        }
    }

    @objc func mdQuote(_ s: Any?) {
        editLines { l in l.hasPrefix("> ") ? String(l.dropFirst(2)) : "> " + l }
    }

    // MARK: Notion-style auto conversion
    static let autoBullet = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+]$"#)
    static let autoTask = try! NSRegularExpression(pattern: #"^([ \t]*)(?:(?:•|[-*+]|\d+\.)\s)?\[\]$"#)
    static let autoHR = try! NSRegularExpression(pattern: #"^---$"#)

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard let s = string as? String, s == " ", selectedRange().length == 0 else { return }
        let ns = self.string as NSString
        let cur = selectedRange().location
        let ls = ns.lineRange(for: NSRange(location: cur - 1, length: 0)).location
        guard cur - 1 >= ls else { return }
        let before = ns.substring(with: NSRange(location: ls, length: cur - 1 - ls))
        let b = before as NSString
        let full = NSRange(location: 0, length: b.length)
        let repl = NSRange(location: ls, length: cur - ls)
        if let m = NoteTextView.autoBullet.firstMatch(in: before, range: full) {
            replace(repl, with: b.substring(with: m.range(at: 1)) + "• ")
        } else if let m = NoteTextView.autoTask.firstMatch(in: before, range: full) {
            replace(repl, with: b.substring(with: m.range(at: 1)) + "• [ ] ")
        }
    }

    // MARK: Enter continues lists, Tab indents list items
    static let cont = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+•])|(\d+)\.|(>))[ \t]+(\[[ xX]\][ \t]+)?"#)

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
        let ln = line as NSString
        guard sel.length == 0, let m = NoteTextView.cont.firstMatch(in: line, range: NSRange(location: 0, length: ln.length)),
              sel.location - lr.location >= m.range.length else { super.insertNewline(sender); return }
        if m.range.length == ln.length {
            replace(NSRange(location: lr.location, length: ln.length), with: "")
            return
        }
        let indent = ln.substring(with: m.range(at: 1))
        var prefix: String
        if m.range(at: 2).location != NSNotFound { prefix = ln.substring(with: m.range(at: 2)) + " " }
        else if m.range(at: 3).location != NSNotFound { prefix = "\((Int(ln.substring(with: m.range(at: 3))) ?? 0) + 1). " }
        else { prefix = "> " }
        if m.range(at: 5).location != NSNotFound { prefix += "[ ] " }
        insertText("\n" + indent + prefix, replacementRange: sel)
    }

    override func insertTab(_ sender: Any?) {
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lr)
        if NoteTextView.cont.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
            let cur = selectedRange()
            replace(NSRange(location: lr.location, length: 0), with: "  ")
            setSelectedRange(NSRange(location: cur.location + 2, length: cur.length))
        } else { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let line = ns.substring(with: lr)
        let n = line.hasPrefix("  ") ? 2 : (line.hasPrefix(" ") || line.hasPrefix("\t") ? 1 : 0)
        guard n > 0 else { return }
        let cur = selectedRange()
        replace(NSRange(location: lr.location, length: n), with: "")
        setSelectedRange(NSRange(location: max(lr.location, cur.location - n), length: cur.length))
    }
}
