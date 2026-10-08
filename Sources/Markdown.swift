import AppKit

enum MD {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    static let heading = re(#"^(#{1,6})([ \t]+)"#)
    static let quote = re(#"^>[ \t]?"#)
    static let hr = re(#"^[ \t]*([-*_])([ \t]*\1){2,}[ \t]*$"#)
    static let list = re(#"^([ \t]*)((?:[-*+•]|\d+\.)[ \t]+)(\[[ xX]\][ \t]+)?"#)
    static let code = re(#"`([^`\n]+)`"#)
    static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italicStar = re(#"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=[^\s*])\*(?![*\w])"#)
    static let italicUnder = re(#"(?<![_\w])_(?=[^\s_])([^_\n]+?)(?<=[^\s_])_(?![_\w])"#)
    static let strike = re(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    static let link = re(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#)
    static let bare = re(#"(?<![(\w])https?://[^\s)>\]]+"#)

    static func mono(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: .regular) }

    static func style(_ ts: NSTextStorage, theme t: Theme, preview: Bool, size: CGFloat) {
        let ns = ts.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        let base = NSFont.systemFont(ofSize: size)
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = 3
        let dim = t.fg.withAlphaComponent(0.38)
        let fm = NSFontManager.shared

        ts.beginEditing()
        ts.setAttributes([.font: base, .foregroundColor: t.fg, .paragraphStyle: ps], range: full)

        func mark(_ r: NSRange) {
            guard r.length > 0 else { return }
            if preview {
                ts.addAttributes([.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear], range: r)
            } else {
                ts.addAttribute(.foregroundColor, value: dim, range: r)
            }
        }
        func trait(_ r: NSRange, _ tr: NSFontTraitMask) {
            ts.enumerateAttribute(.font, in: r) { v, rr, _ in
                let f = (v as? NSFont) ?? base
                ts.addAttribute(.font, value: fm.convert(f, toHaveTrait: tr), range: rr)
            }
        }
        func rangeIn(_ m: NSTextCheckingResult, _ i: Int) -> NSRange { m.range(at: i) }

        var inFence = false
        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lr, _, _ in
            let line = ns.substring(with: lr)
            if line.hasPrefix("```") {
                inFence.toggle()
                ts.addAttributes([.font: mono(size), .foregroundColor: dim], range: lr)
                return
            }
            if inFence {
                ts.addAttributes([.font: mono(size), .backgroundColor: t.fg.withAlphaComponent(0.08)], range: lr)
                return
            }
            let lineNS = line as NSString
            let local = NSRange(location: 0, length: lineNS.length)
            func abs(_ r: NSRange) -> NSRange { NSRange(location: r.location + lr.location, length: r.length) }

            if let m = heading.firstMatch(in: line, range: local) {
                let level = m.range(at: 1).length
                let scale: [CGFloat] = [1.7, 1.45, 1.25, 1.1, 1.0, 1.0]
                let f = fm.convert(NSFont.systemFont(ofSize: size * scale[level - 1]), toHaveTrait: .boldFontMask)
                ts.addAttribute(.font, value: f, range: lr)
                mark(abs(m.range))
            } else if let m = quote.firstMatch(in: line, range: local) {
                let p = NSMutableParagraphStyle(); p.lineSpacing = 3; p.firstLineHeadIndent = 4; p.headIndent = 4
                ts.addAttributes([.paragraphStyle: p, .foregroundColor: t.fg.withAlphaComponent(0.7)], range: lr)
                trait(lr, .italicFontMask)
                ts.addAttribute(.foregroundColor, value: t.accent, range: abs(m.range))
            } else if hr.firstMatch(in: line, range: local) != nil {
                ts.addAttributes([.foregroundColor: dim, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: lr)
                return
            } else if let m = list.firstMatch(in: line, range: local) {
                let lead = m.range(at: 1), bullet = m.range(at: 2), box = m.range(at: 3)
                let p = NSMutableParagraphStyle(); p.lineSpacing = 3
                let w = ("0" as NSString).size(withAttributes: [.font: base]).width
                let indent = CGFloat(lead.length) * w * 1.2
                let hang = CGFloat(m.range.length - lead.length) * w * 0.9
                p.firstLineHeadIndent = indent; p.headIndent = indent + hang
                ts.addAttribute(.paragraphStyle, value: p, range: lr)
                ts.addAttribute(.foregroundColor, value: t.accent, range: abs(bullet))
                if box.location != NSNotFound {
                    let b = abs(box)
                    ts.addAttributes([.font: mono(size), .foregroundColor: t.accent], range: NSRange(location: b.location, length: 3))
                    let checked = lineNS.substring(with: NSRange(location: box.location + 1, length: 1)) != " "
                    if checked {
                        let rest = NSRange(location: b.location + b.length, length: lr.location + lr.length - b.location - b.length)
                        ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: dim], range: rest)
                    }
                }
            }

            // inline
            bold.enumerateMatches(in: line, range: local) { m, _, _ in
                guard let m = m else { return }
                trait(abs(m.range(at: 2)), .boldFontMask)
                let a = abs(m.range)
                mark(NSRange(location: a.location, length: 2)); mark(NSRange(location: a.location + a.length - 2, length: 2))
            }
            for rx in [italicStar, italicUnder] {
                rx.enumerateMatches(in: line, range: local) { m, _, _ in
                    guard let m = m else { return }
                    trait(abs(m.range(at: 1)), .italicFontMask)
                    let a = abs(m.range)
                    mark(NSRange(location: a.location, length: 1)); mark(NSRange(location: a.location + a.length - 1, length: 1))
                }
            }
            strike.enumerateMatches(in: line, range: local) { m, _, _ in
                guard let m = m else { return }
                ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: abs(m.range(at: 1)))
                let a = abs(m.range)
                mark(NSRange(location: a.location, length: 2)); mark(NSRange(location: a.location + a.length - 2, length: 2))
            }
            link.enumerateMatches(in: line, range: local) { m, _, _ in
                guard let m = m else { return }
                let a = abs(m.range), txt = abs(m.range(at: 1))
                let urlStr = lineNS.substring(with: m.range(at: 2))
                var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: t.accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
                if let u = URL(string: urlStr) { attrs[.link] = u }
                ts.addAttributes(attrs, range: txt)
                mark(NSRange(location: a.location, length: 1))
                mark(NSRange(location: txt.location + txt.length, length: a.location + a.length - txt.location - txt.length))
            }
            bare.enumerateMatches(in: line, range: local) { m, _, _ in
                guard let m = m else { return }
                let a = abs(m.range)
                if ts.attribute(.link, at: a.location, effectiveRange: nil) != nil { return }
                if let u = URL(string: lineNS.substring(with: m.range)) {
                    ts.addAttributes([.link: u, .foregroundColor: t.accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: a)
                }
            }
            code.enumerateMatches(in: line, range: local) { m, _, _ in
                guard let m = m else { return }
                let a = abs(m.range)
                ts.addAttributes([.font: mono(size), .foregroundColor: t.fg, .backgroundColor: t.fg.withAlphaComponent(0.1)], range: abs(m.range(at: 1)))
                mark(NSRange(location: a.location, length: 1)); mark(NSRange(location: a.location + a.length - 1, length: 1))
            }
        }
        ts.endEditing()
    }
}
