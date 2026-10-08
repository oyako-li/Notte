import AppKit

struct Theme {
    let name: String
    let bg: NSColor
    let fg: NSColor
    let accent: NSColor
}

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

let themes: [Theme] = [
    Theme(name: "Yellow", bg: hex(0xFFF1A8), fg: hex(0x3A3320), accent: hex(0xB8860B)),
    Theme(name: "Pink", bg: hex(0xF9BEC4), fg: hex(0x3B2326), accent: hex(0xC2185B)),
    Theme(name: "Blue", bg: hex(0xBFE0F5), fg: hex(0x1F3040), accent: hex(0x1565C0)),
    Theme(name: "Green", bg: hex(0xC9EBC0), fg: hex(0x223420), accent: hex(0x2E7D32)),
    Theme(name: "Purple", bg: hex(0xD9C9F2), fg: hex(0x2B2140), accent: hex(0x6A1B9A)),
    Theme(name: "Orange", bg: hex(0xFFD7A8), fg: hex(0x3D2A14), accent: hex(0xE65100)),
    Theme(name: "Gray", bg: hex(0xE2E2E2), fg: hex(0x262626), accent: hex(0x455A64)),
    Theme(name: "Charcoal", bg: hex(0x2D2F33), fg: hex(0xE8E8E8), accent: hex(0x64B5F6)),
]

func theme(_ i: Int) -> Theme { themes[max(0, min(themes.count - 1, i))] }

final class Note: Codable {
    var id = UUID()
    var text = ""
    var theme = 0
    var x = 0.0, y = 0.0, w = 300.0, h = 260.0
    var projectID: UUID?
    var floating = false
    var isOpen = true
    var preview = false
    var modified = Date()

    var title: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var t = line.trimmingCharacters(in: .whitespaces)
            t = t.replacingOccurrences(of: #"^(#{1,6}\s+|[-*+•]\s+(\[[ xX]\]\s+)?|\d+\.\s+|>\s*)"#, with: "", options: .regularExpression)
            if !t.isEmpty { return t }
        }
        return "(empty)"
    }

    var tasks: (done: Int, total: Int) { Note.countTasks(text) }

    static let taskRegex = try! NSRegularExpression(pattern: #"^[ \t]*(?:[-*+•]|\d+\.)[ \t]+\[([ xX])\]"#, options: .anchorsMatchLines)

    static func countTasks(_ s: String) -> (Int, Int) {
        let ns = s as NSString
        var d = 0, t = 0
        taskRegex.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m else { return }
            t += 1
            if ns.substring(with: m.range(at: 1)) != " " { d += 1 }
        }
        return (d, t)
    }
}

final class Project: Codable {
    var id = UUID()
    var name: String
    var theme = 2
    var due: Date?
    var completed = false
    init(name: String, theme: Int = 2) { self.name = name; self.theme = theme }
}

extension Notification.Name {
    static let storeChanged = Notification.Name("MarkStickyStoreChanged")
}

final class Store {
    static let shared = Store()
    var notes: [Note] = []
    var projects: [Project] = []
    private var pending: DispatchWorkItem?

    private var url: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MarkSticky")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("store.json")
    }

    private struct Payload: Codable { var notes: [Note]; var projects: [Project] }

    func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let p = try? dec.decode(Payload.self, from: data) { notes = p.notes; projects = p.projects }
    }

    func saveNow() {
        pending?.cancel()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(Payload(notes: notes, projects: projects)) { try? data.write(to: url, options: .atomic) }
    }

    func changed(notify: Bool = true) {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        if notify { NotificationCenter.default.post(name: .storeChanged, object: nil) }
    }

    func project(_ id: UUID?) -> Project? { id == nil ? nil : projects.first { $0.id == id } }

    func tasks(in project: Project?) -> (done: Int, total: Int) {
        var d = 0, t = 0
        for n in notes where n.projectID == project?.id {
            let c = n.tasks; d += c.done; t += c.total
        }
        return (d, t)
    }
}
