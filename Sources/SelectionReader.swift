import Carbon.HIToolbox
import Cocoa

enum SelectionReader {
    static func read(completion: @escaping (String?) -> Void) {
        if let text = accessibilitySelection(), !text.isEmpty {
            completion(text)
        } else {
            copySelection(completion: completion)
        }
    }

    private static func accessibilitySelection() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }

        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        return selected as? String
    }

    // Apps without accessibility support (Chrome pages, Electron apps) only give the selection up through ⌘C.
    private static func copySelection(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.map(copyItem) ?? []
        let changeCount = pasteboard.changeCount

        pressCommandC()

        let deadline = Date().addingTimeInterval(COPY_TIMEOUT)
        func poll() {
            if pasteboard.changeCount != changeCount {
                let text = pasteboard.string(forType: .string)
                restore(savedItems, to: pasteboard)
                completion(text)
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + COPY_POLL_INTERVAL, execute: poll)
            } else {
                completion(nil)
            }
        }
        poll()
    }

    private static func pressCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_C)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func copyItem(_ item: NSPasteboardItem) -> NSPasteboardItem {
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }

    private static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
