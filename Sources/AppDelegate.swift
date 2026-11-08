import Cocoa
import ServiceManagement
import Translation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let speaker = Speaker()
    private let popup = Popup()
    private let history = History()
    private lazy var historyWindow: HistoryWindow = {
        let window = HistoryWindow(history: history)
        window.onSpeak = { [weak self] word in self?.speaker.speak(word) }
        return window
    }()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var doubleTap: DoubleTap?
    private var currentWord = ""
    private var targetLanguage = ""
    private let packDownloader = TranslationPackDownloader()
    private var packStatus: LanguageAvailability.Status?
    private let statusMenu = NSMenu()
    private let languageMenu = NSMenu()
    private let dictionaryItem = NSMenuItem(title: "", action: #selector(downloadDictionary), keyEquivalent: "")
    private let packItem = NSMenuItem(title: "", action: #selector(downloadTranslationPack), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        popup.onReplay = { [weak self] in self.map { $0.speaker.speak($0.currentWord) } }
        hotKey = HotKey(keyCode: HOTKEY_KEY_CODE, modifiers: HOTKEY_MODIFIERS) { [weak self] in self?.lookUpSelection() }
        doubleTap = DoubleTap(modifier: DOUBLE_TAP_MODIFIER) { [weak self] in self?.lookUpSelection() }
        let savedSpeed = UserDefaults.standard.string(forKey: SPEED_KEY)
        if let speed = SPEECH_SPEEDS.first(where: { $0.title == savedSpeed }) { speaker.speed = speed }
        if let voice = UserDefaults.standard.string(forKey: VOICE_KEY), PHONON_VOICES.contains(voice) { speaker.voice = voice }
        let savedStyle = UserDefaults.standard.string(forKey: POPUP_STYLE_KEY)
        if let style = POPUP_STYLES.first(where: { $0.title == savedStyle }) { popup.style = style }
        speaker.onNote = { [weak self] note in self?.popup.speechNote = note }
        speaker.load()
        targetLanguage = UserDefaults.standard.string(forKey: TARGET_LANGUAGE_KEY) ?? AppDelegate.preferredTargetLanguage()
        setUpMenu()
        refreshPackStatus()
        setUpShortcuts()

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
            if word.isEmpty && !AXIsProcessTrusted() {
                self.popup.show(word: "", translation: nil,
                                status: "Saytap can't read the selection without the Accessibility permission. Open the menu bar icon → Allow Accessibility…",
                                at: NSEvent.mouseLocation)
            } else if word.isEmpty {
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

        let language = targetLanguage
        Translator.translate(word, to: language, remembered: history.translation(of: word, in: language)) { [weak self] result in
            guard let self, self.currentWord == word else { return }
            switch result {
            case .success(let translation):
                self.history.record(word, translation: translation, language: language)
                self.popup.show(word: word, translation: translation, status: nil)
            case .failure(let failure):
                self.popup.show(word: word, translation: nil, status: failure.message)
            }
        }
    }

    // The preferred languages in System Settings → Language & Region first, then the rest by name.
    static func targetLanguages(available: [String] = Array(BilingualDictionary.byLanguage.keys),
                                preferredLanguages: [String] = Locale.preferredLanguages) -> (preferred: [String], others: [String]) {
        var others = available.sorted { Translator.languageName($0) < Translator.languageName($1) }
        var preferred: [String] = []
        for identifier in preferredLanguages {
            if let index = others.firstIndex(where: { sameLanguage($0, identifier) }) { preferred.append(others.remove(at: index)) }
        }
        return (preferred, others)
    }

    private static func preferredTargetLanguage() -> String {
        let languages = targetLanguages()
        return languages.preferred.first ?? languages.others.first ?? DEFAULT_TARGET_LANGUAGE
    }

    // Same language and script, so Simplified Chinese doesn't match Traditional.
    static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let (left, right) = (Locale.Language(identifier: lhs), Locale.Language(identifier: rhs))
        return left.languageCode == right.languageCode
            && Locale.Language(identifier: left.maximalIdentifier).script == Locale.Language(identifier: right.maximalIdentifier).script
    }

    // Filled on every open by menuNeedsUpdate, so a dictionary downloaded meanwhile loses its mark.
    private func targetLanguageMenuItem() -> NSMenuItem {
        languageMenu.delegate = self
        let item = NSMenuItem(title: "Translate to", action: nil, keyEquivalent: "")
        item.submenu = languageMenu
        return item
    }

    private func fillLanguageMenu() {
        languageMenu.removeAllItems()
        let languages = AppDelegate.targetLanguages()
        for group in [languages.preferred, languages.others] where !group.isEmpty {
            if languageMenu.numberOfItems > 0 { languageMenu.addItem(.separator()) }
            for language in group {
                let name = Translator.languageName(language)
                let option = languageMenu.addItem(withTitle: name, action: #selector(changeTargetLanguage), keyEquivalent: "")
                option.target = self
                option.representedObject = language
                option.state = language == targetLanguage ? .on : .off
                if !BilingualDictionary.isDownloaded(language) {
                    let title = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                    title.append(NSAttributedString(string: "  dictionary not downloaded", attributes: [
                        .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
                    option.attributedTitle = title
                }
            }
        }
    }

    // Starts downloading the language's dictionary, and offers its offline translation, when they're missing.
    @objc private func changeTargetLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        targetLanguage = language
        UserDefaults.standard.set(language, forKey: TARGET_LANGUAGE_KEY)
        packStatus = nil
        if !BilingualDictionary.isDownloaded(language) { BilingualDictionary.startDownload(language) }
        updateLanguageItems()
        refreshPackStatus { [weak self] status in
            if status == .supported { self?.downloadTranslationPack() }
        }
    }

    // The menu items that offer what the current language is missing.
    private func updateLanguageItems() {
        let name = Translator.languageName(targetLanguage)
        dictionaryItem.title = "Downloading the \(name) dictionary…"
        dictionaryItem.isHidden = BilingualDictionary.byLanguage[targetLanguage] == nil || BilingualDictionary.isDownloaded(targetLanguage)
        packItem.title = "Download \(name) for offline translation…"
        packItem.isHidden = packStatus != .supported
    }

    private func refreshPackStatus(completion: ((LanguageAvailability.Status) -> Void)? = nil) {
        let language = targetLanguage
        Task { @MainActor [weak self] in
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: SOURCE_LANGUAGE),
                                                             to: Locale.Language(identifier: language))
            guard let self, self.targetLanguage == language else { return }
            self.packStatus = status
            self.updateLanguageItems()
            completion?(status)
        }
    }

    // Starts the download again, for when the first attempt had no connection.
    @objc private func downloadDictionary() {
        BilingualDictionary.startDownload(targetLanguage)
    }

    @objc private func downloadTranslationPack() {
        packDownloader.download(targetLanguage) { [weak self] in self?.refreshPackStatus() }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSLog("Launch at login failed: %@", String(describing: error))
        }
        // macOS may ask the person to allow it in Login Items first.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === languageMenu {
            BilingualDictionary.refresh()
            fillLanguageMenu()
            return
        }
        BilingualDictionary.refresh()
        updateLanguageItems()
        refreshPackStatus()
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let trusted = AXIsProcessTrusted()
        accessibilityItem.title = trusted ? "Accessibility permission…" : "Allow Accessibility…"
        accessibilityItem.image = trusted ? nil : NSImage(systemSymbolName: WARNING_SYMBOL, accessibilityDescription: "Missing")
    }

    @objc private func showHistory() {
        historyWindow.show()
    }

    // A menu bar app shows no main menu, but text fields still need its Edit shortcuts, and windows ⌘W.
    private func setUpShortcuts() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [NSMenu(title: "Saytap"), edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Saytap")

        let menu = statusMenu
        menu.delegate = self
        for missing in [dictionaryItem, packItem] {
            missing.image = NSImage(systemSymbolName: WARNING_SYMBOL, accessibilityDescription: "Missing")
            missing.indentationLevel = 1
        }
        menu.addItem(withTitle: "Speak & translate selection (\(DOUBLE_TAP_LABEL) or \(HOTKEY_LABEL))", action: #selector(lookUpSelection), keyEquivalent: "")
        menu.addItem(withTitle: "History…", action: #selector(showHistory), keyEquivalent: "")
        menu.addItem(targetLanguageMenuItem())
        menu.addItem(dictionaryItem)
        menu.addItem(packItem)
        menu.addItem(speedMenuItem())
        menu.addItem(voiceMenuItem())
        menu.addItem(styleMenuItem())
        menu.addItem(loginItem)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Saytap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        for voice in PHONON_VOICES {
            let option = submenu.addItem(withTitle: voice, action: #selector(changeVoice), keyEquivalent: "")
            option.target = self
            option.state = voice == speaker.voice ? .on : .off
        }
        let item = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func changeVoice(_ sender: NSMenuItem) {
        speaker.voice = sender.title
        UserDefaults.standard.set(sender.title, forKey: VOICE_KEY)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        speaker.speak(currentWord.isEmpty ? VOICE_SAMPLE : currentWord)
    }

    private func styleMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for style in POPUP_STYLES {
            let option = submenu.addItem(withTitle: style.title, action: #selector(changeStyle), keyEquivalent: "")
            option.target = self
            option.state = style.title == popup.style.title ? .on : .off
        }
        let item = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // Shows the last looked-up word in the new style.
    @objc private func changeStyle(_ sender: NSMenuItem) {
        guard let style = POPUP_STYLES.first(where: { $0.title == sender.title }) else { return }
        popup.style = style
        UserDefaults.standard.set(style.title, forKey: POPUP_STYLE_KEY)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        if let last = history.entries.first {
            currentWord = last.word
            popup.show(word: last.word, translation: last.translation, at: NSEvent.mouseLocation)
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
