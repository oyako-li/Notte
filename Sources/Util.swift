import AppKit

func promptText(_ message: String, _ label: String, _ initial: String = "") -> String? {
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    f.stringValue = initial; f.placeholderString = label
    let a = NSAlert()
    a.messageText = message; a.accessoryView = f
    a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = f
    guard a.runModal() == .alertFirstButtonReturn else { return nil }
    let s = f.stringValue.trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? nil : s
}
