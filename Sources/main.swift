import AVFoundation
import Carbon.HIToolbox
import Cocoa

// MARK: - Settings

let TARGET_LANGUAGE = "ru"
let SPEECH_LANGUAGE_PREFIX = "en"
let PREFERRED_SPEECH_REGION = "en-US"

let HOTKEY_KEY_CODE = UInt32(kVK_ANSI_T)
let HOTKEY_MODIFIERS = UInt32(controlKey | optionKey)
let HOTKEY_LABEL = "⌃⌥T"
let HOTKEY_SIGNATURE: OSType = 0x5750_4F50 // "WPOP"

let MAX_SELECTION_LENGTH = 500
let COPY_TIMEOUT: TimeInterval = 0.4
let COPY_POLL_INTERVAL: TimeInterval = 0.02
let POPUP_LIFETIME: TimeInterval = 10
let POPUP_WIDTH: CGFloat = 340
let POPUP_PADDING: CGFloat = 14
let POPUP_CORNER_RADIUS: CGFloat = 12
let POPUP_CURSOR_OFFSET: CGFloat = 16
let MAX_DICTIONARY_TERMS = 6
let ESCAPE_KEY_CODE = UInt16(kVK_Escape)

// MARK: - Selected text

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

// MARK: - Translation

struct Translation {
    var text: String
    var phonetic: String?
    var dictionary: [(partOfSpeech: String, terms: [String])]
}

enum Translator {
    static func translate(_ text: String, completion: @escaping (Result<Translation, Error>) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: TARGET_LANGUAGE),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "rm"),
            URLQueryItem(name: "q", value: text),
        ]

        URLSession.shared.dataTask(with: components.url!) { data, _, error in
            let result: Result<Translation, Error>
            if let data, let translation = parse(data) {
                result = .success(translation)
            } else {
                result = .failure(error ?? URLError(.cannotParseResponse))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // Response shape: [[[translated, original, …], …, [null, null, translit, source translit]], [[pos, [terms], …], …], …]
    private static func parse(_ data: Data) -> Translation? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [[Any]] else { return nil }

        let text = sentences.compactMap { $0.first as? String }.joined()
        let phonetic = sentences.last.flatMap { $0.count > 3 ? $0[3] as? String : nil }
        let entries = (root.count > 1 ? root[1] as? [[Any]] : nil) ?? []
        let dictionary = entries.compactMap { entry -> (String, [String])? in
            guard let partOfSpeech = entry.first as? String,
                  let terms = entry.count > 1 ? entry[1] as? [String] : nil else { return nil }
            return (partOfSpeech, Array(terms.prefix(MAX_DICTIONARY_TERMS)))
        }
        return Translation(text: text, phonetic: phonetic, dictionary: dictionary)
    }
}

// MARK: - Speech

final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice = bestEnglishVoice()

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    // Premium and Enhanced voices first; among equals, the preferred region.
    private func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(SPEECH_LANGUAGE_PREFIX) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality.rawValue < rhs.quality.rawValue }
                return lhs.language != PREFERRED_SPEECH_REGION && rhs.language == PREFERRED_SPEECH_REGION
            }
    }
}

// MARK: - Pop-up

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

final class Popup {
    var onReplay: (() -> Void)?

    private let panel: PopupPanel
    private let stack = NSStackView()
    private var hideTimer: Timer?
    private var monitors: [Any] = []

    init() {
        panel = PopupPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = POPUP_CORNER_RADIUS
        background.layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: POPUP_PADDING, left: POPUP_PADDING, bottom: POPUP_PADDING, right: POPUP_PADDING)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: POPUP_WIDTH),
        ])
        panel.contentView = background
    }

    func show(word: String, translation: Translation?, status: String? = nil, at point: NSPoint? = nil) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        stack.addArrangedSubview(header(word: word, phonetic: translation?.phonetic))
        if let translation {
            stack.addArrangedSubview(label(translation.text, size: 16, weight: .medium))
            for entry in translation.dictionary {
                stack.addArrangedSubview(dictionaryLine(entry.partOfSpeech, entry.terms))
            }
        }
        if let status {
            stack.addArrangedSubview(label(status, size: 13, color: .secondaryLabelColor))
        }

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView!.fittingSize
        let origin = point.map { position(for: size, near: $0) } ?? panel.frame.origin
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        startHiding()
    }

    func hide() {
        panel.orderOut(nil)
        hideTimer?.invalidate()
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func startHiding() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: POPUP_LIFETIME, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.panel.frame.contains(NSEvent.mouseLocation) { self.startHiding() } else { self.hide() }
        }

        guard monitors.isEmpty else { return }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.hide()
        }) { monitors.append(clicks) }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == ESCAPE_KEY_CODE { self?.hide() }
        }) { monitors.append(keys) }
    }

    // Below-right of the cursor, flipped to stay on the screen the cursor is on.
    private func position(for size: NSSize, near point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let bounds = screen.visibleFrame
        var x = point.x + POPUP_CURSOR_OFFSET
        var y = point.y - POPUP_CURSOR_OFFSET - size.height
        if x + size.width > bounds.maxX { x = point.x - POPUP_CURSOR_OFFSET - size.width }
        if y < bounds.minY { y = point.y + POPUP_CURSOR_OFFSET }
        return NSPoint(x: max(bounds.minX, x), y: min(y, bounds.maxY - size.height))
    }

    private func header(word: String, phonetic: String?) -> NSView {
        let replay = NSButton(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Say again")!,
                              target: self, action: #selector(replay))
        replay.isBordered = false
        replay.contentTintColor = .controlAccentColor

        let title = label(word, size: 18, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        let row = NSStackView(views: [replay, title])
        row.spacing = 6
        guard let phonetic, !phonetic.isEmpty else { return row }

        let column = NSStackView(views: [row, label("[\(phonetic)]", size: 13, color: .secondaryLabelColor)])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        return column
    }

    private func dictionaryLine(_ partOfSpeech: String, _ terms: [String]) -> NSTextField {
        let text = NSMutableAttributedString(string: "\(partOfSpeech)  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        text.append(NSAttributedString(string: terms.joined(separator: ", "), attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]))
        let field = NSTextField(labelWithAttributedString: text)
        field.preferredMaxLayoutWidth = POPUP_WIDTH - 2 * POPUP_PADDING
        return field
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.isSelectable = false
        field.preferredMaxLayoutWidth = POPUP_WIDTH - 2 * POPUP_PADDING
        return field
    }

    @objc private func replay() { onReplay?() }
}

// MARK: - Global hotkey

final class HotKey {
    private var reference: EventHotKeyRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            Unmanaged<HotKey>.fromOpaque(context!).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: HOTKEY_SIGNATURE, id: 1),
                            GetApplicationEventTarget(), 0, &reference)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let speaker = Speaker()
    private let popup = Popup()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var currentWord = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        popup.onReplay = { [weak self] in self.map { $0.speaker.speak($0.currentWord) } }
        hotKey = HotKey(keyCode: HOTKEY_KEY_CODE, modifiers: HOTKEY_MODIFIERS) { [weak self] in self?.lookUpSelection() }
        setUpMenu()

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        NSLog("Accessibility trusted: %d", AXIsProcessTrustedWithOptions(prompt))

        if let index = CommandLine.arguments.firstIndex(of: "--show"), index + 1 < CommandLine.arguments.count {
            lookUp(CommandLine.arguments[index + 1])
        }
    }

    @objc func lookUpSelection() {
        SelectionReader.read { [weak self] text in
            guard let self else { return }
            let word = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if word.isEmpty {
                NSSound.beep()
            } else {
                self.lookUp(String(word.prefix(MAX_SELECTION_LENGTH)))
            }
        }
    }

    private func lookUp(_ word: String) {
        currentWord = word
        speaker.speak(word)
        popup.show(word: word, translation: nil, status: "Translating…", at: NSEvent.mouseLocation)

        Translator.translate(word) { [weak self] result in
            guard let self, self.currentWord == word else { return }
            switch result {
            case .success(let translation):
                self.popup.show(word: word, translation: translation)
            case .failure(let error):
                self.popup.show(word: word, translation: nil, status: "Translation failed: \(error.localizedDescription)")
            }
        }
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Word Popup")

        let menu = NSMenu()
        menu.addItem(withTitle: "Speak & translate selection (\(HOTKEY_LABEL))", action: #selector(lookUpSelection), keyEquivalent: "")
        menu.addItem(withTitle: "Accessibility settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Word Popup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
