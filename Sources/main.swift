import AVFoundation
import Carbon.HIToolbox
import Cocoa

// MARK: - Settings

let TARGET_LANGUAGE = "ru"

struct SpeechSpeed {
    let title: String
    let phononDelta: Double
    let playbackRate: Float
}

// Phonon's duration_delta only stretches speech by about ±10%, so the outer presets also change the playback rate.
let SPEECH_SPEEDS = [
    SpeechSpeed(title: "Very slow", phononDelta: 0.3, playbackRate: 0.75),
    SpeechSpeed(title: "Slow", phononDelta: 0.3, playbackRate: 1),
    SpeechSpeed(title: "Normal", phononDelta: 0, playbackRate: 1),
    SpeechSpeed(title: "Fast", phononDelta: -0.3, playbackRate: 1),
    SpeechSpeed(title: "Very fast", phononDelta: -0.3, playbackRate: 1.25),
]
let DEFAULT_SPEED_INDEX = 2
let SPEED_KEY = "speed"
let SPEED_SAMPLE = "This is how fast I speak."
let VOICE_KEY = "voice"
let VOICE_SAMPLE = "Hello, this is how I sound."

let PHONON_VOICES = ["Harper", "Hadley", "Everly", "Maeve", "Edwin", "Spencer"]
let PHONON_LANGUAGE = "en"
let PHONON_EXECUTABLES = ["/opt/homebrew/bin/ptts", "/usr/local/bin/ptts"]
let PHONON_INSTALL_HINT = "brew install gradium-ai/tap/ptts"

let HOTKEY_KEY_CODE = UInt32(kVK_ANSI_T)
let HOTKEY_MODIFIERS = UInt32(controlKey | optionKey)
let HOTKEY_LABEL = "⌃⌥T"
let HOTKEY_SIGNATURE: OSType = 0x5750_4F50 // "WPOP"

let DOUBLE_TAP_MODIFIER = NSEvent.ModifierFlags.option
let DOUBLE_TAP_LABEL = "⌥⌥"
let TRACKED_MODIFIERS: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
let TAP_MAX_DURATION: TimeInterval = 0.3
let DOUBLE_TAP_INTERVAL: TimeInterval = 0.4

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

// Speaks with Phonon by running the ptts command for each phrase. It first runs offline: asking Hugging Face
// for updates takes most of a second. Only a voice that isn't downloaded yet needs the online run.
final class Speaker {
    var voice = PHONON_VOICES[0]
    var speed = SPEECH_SPEEDS[DEFAULT_SPEED_INDEX]
    private var process: Process?
    private var player: AVAudioPlayer?
    private var request = 0
    private var cached: (key: String, file: URL)?

    static var executable: URL? {
        PHONON_EXECUTABLES.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    // Beeps when ptts is missing or fails.
    func speak(_ text: String) {
        stop()
        let current = request
        let (voice, delta, playbackRate) = (voice, speed.phononDelta, speed.playbackRate)
        let key = "\(voice)|\(delta)|\(text)"
        if let cached, cached.key == key {
            play(cached.file, rate: playbackRate)
            return
        }
        guard let executable = Speaker.executable else {
            NSSound.beep()
            return
        }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("word-popup-\(current).wav")
        let finish = { [weak self] (succeeded: Bool) in
            guard let self, self.request == current else { return }
            if succeeded {
                self.cached.map { try? FileManager.default.removeItem(at: $0.file) }
                self.cached = (key, file)
                self.play(file, rate: playbackRate)
            } else {
                NSSound.beep()
            }
        }
        generate(executable, text: text, voice: voice, delta: delta, to: file, offline: true) { [weak self] succeeded in
            guard let self, self.request == current else { return }
            if succeeded {
                finish(true)
            } else {
                self.generate(executable, text: text, voice: voice, delta: delta, to: file, offline: false, completion: finish)
            }
        }
    }

    // Also invalidates the running request, so a terminated run is ignored.
    func stop() {
        request += 1
        process?.terminate()
        process = nil
        player?.stop()
    }

    private func generate(_ executable: URL, text: String, voice: String, delta: Double, to file: URL, offline: Bool,
                          completion: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--lang", PHONON_LANGUAGE, "--voice", voice, "--condition", "duration_delta=\(delta)",
                             "-o", file.path, "--", text]
        var environment = ProcessInfo.processInfo.environment
        if offline { environment["HF_HUB_OFFLINE"] = "1" }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let succeeded = finished.terminationReason == .exit && finished.terminationStatus == 0
            DispatchQueue.main.async { completion(succeeded) }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            completion(false)
        }
    }

    private func play(_ file: URL, rate: Float) {
        player = try? AVAudioPlayer(contentsOf: file)
        player?.enableRate = true
        player?.rate = rate
        player?.play()
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

// MARK: - Double-tap trigger

// Fires when the modifier is tapped twice on its own; any key, click or other modifier in between cancels it.
final class DoubleTap {
    private let modifier: NSEvent.ModifierFlags
    private let action: () -> Void
    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var lastTapAt: Date?

    init(modifier: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.modifier = modifier
        self.action = action
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] in self?.handle($0) },
            NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.reset()
            },
        ].compactMap { $0 }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(TRACKED_MODIFIERS)
        if flags == modifier {
            pressedAt = Date()
        } else if flags.isEmpty, let pressedAt, Date().timeIntervalSince(pressedAt) < TAP_MAX_DURATION {
            registerTap()
        } else {
            reset()
        }
    }

    private func registerTap() {
        pressedAt = nil
        let now = Date()
        if let lastTapAt, now.timeIntervalSince(lastTapAt) < DOUBLE_TAP_INTERVAL {
            self.lastTapAt = nil
            action()
        } else {
            lastTapAt = now
        }
    }

    private func reset() {
        pressedAt = nil
        lastTapAt = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let speaker = Speaker()
    private let popup = Popup()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var doubleTap: DoubleTap?
    private var currentWord = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        popup.onReplay = { [weak self] in self.map { $0.speaker.speak($0.currentWord) } }
        hotKey = HotKey(keyCode: HOTKEY_KEY_CODE, modifiers: HOTKEY_MODIFIERS) { [weak self] in self?.lookUpSelection() }
        doubleTap = DoubleTap(modifier: DOUBLE_TAP_MODIFIER) { [weak self] in self?.lookUpSelection() }
        let savedSpeed = UserDefaults.standard.string(forKey: SPEED_KEY)
        if let speed = SPEECH_SPEEDS.first(where: { $0.title == savedSpeed }) { speaker.speed = speed }
        if let voice = UserDefaults.standard.string(forKey: VOICE_KEY), PHONON_VOICES.contains(voice) { speaker.voice = voice }
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
        let speechHint = Speaker.executable == nil ? "To hear words: \(PHONON_INSTALL_HINT)" : nil

        Translator.translate(word) { [weak self] result in
            guard let self, self.currentWord == word else { return }
            switch result {
            case .success(let translation):
                self.popup.show(word: word, translation: translation, status: speechHint)
            case .failure(let error):
                self.popup.show(word: word, translation: nil, status: "Translation failed: \(error.localizedDescription)")
            }
        }
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Word Popup")

        let menu = NSMenu()
        menu.addItem(withTitle: "Speak & translate selection (\(DOUBLE_TAP_LABEL) or \(HOTKEY_LABEL))", action: #selector(lookUpSelection), keyEquivalent: "")
        menu.addItem(speedMenuItem())
        menu.addItem(voiceMenuItem())
        menu.addItem(withTitle: "Accessibility permission…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Word Popup", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        item.menu = menu
        statusItem = item
    }

    private func speedMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for speed in SPEECH_SPEEDS {
            let option = submenu.addItem(withTitle: speed.title, action: #selector(changeSpeed), keyEquivalent: "")
            option.target = self
            option.state = speed.title == speaker.speed.title ? .on : .off
        }
        let item = NSMenuItem(title: "Speed", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func changeSpeed(_ sender: NSMenuItem) {
        guard let speed = SPEECH_SPEEDS.first(where: { $0.title == sender.title }) else { return }
        speaker.speed = speed
        UserDefaults.standard.set(speed.title, forKey: SPEED_KEY)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        speaker.speak(currentWord.isEmpty ? SPEED_SAMPLE : currentWord)
    }

    private func voiceMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.delegate = self
        let item = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // Rebuilt on every open, so installing ptts while the app runs shows the voices.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard Speaker.executable != nil else {
            menu.addItem(withTitle: "Speech needs: \(PHONON_INSTALL_HINT)", action: nil, keyEquivalent: "")
            return
        }
        for voice in PHONON_VOICES {
            let option = menu.addItem(withTitle: voice, action: #selector(changeVoice), keyEquivalent: "")
            option.target = self
            option.state = voice == speaker.voice ? .on : .off
        }
    }

    @objc private func changeVoice(_ sender: NSMenuItem) {
        speaker.voice = sender.title
        UserDefaults.standard.set(sender.title, forKey: VOICE_KEY)
        speaker.speak(currentWord.isEmpty ? VOICE_SAMPLE : currentWord)
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
