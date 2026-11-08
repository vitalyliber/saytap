import AVFoundation
import Carbon.HIToolbox
import Cocoa
import CoreServices
import PhononTTS
import Translation

// MARK: - Settings

let SOURCE_LANGUAGE = "en"
let TARGET_LANGUAGE_KEY = "targetLanguage"
let DEFAULT_TARGET_LANGUAGE = "es"
// Google's codes where they differ from the dictionaries' language identifiers.
let GOOGLE_LANGUAGE_CODES = ["zh-Hans": "zh-CN", "zh-Hant": "zh-TW", "zh-Hant-HK": "zh-TW", "yue-Hant": "yue"]
let TRANSLATION_LANGUAGES_SETTINGS = "System Settings → General → Language & Region → Translation Languages"
let HTTP_TOO_MANY_REQUESTS = 429
// Google usually answers in 0.1–0.3 s; a stalled network hands the text to Apple Translation after this.
let GOOGLE_TIMEOUT: TimeInterval = 1
let INDEX_LANGUAGE_KEY = "DCSDictionaryIndexLanguage"
let DESCRIPTION_LANGUAGE_KEY = "DCSDictionaryDescriptionLanguage"
let ENTRY_XHTML_VERSION = 0
let MAX_DICTIONARY_RECORDS = 3
let MAIN_TRANSLATION_TERMS = 2
let TRAILING_PUNCTUATION = CharacterSet(charactersIn: ",;:/ ")
// Separators and grammar labels (impf, pf, m pl) the dictionary adds for display.
let HIDDEN_ENTRY_CLASSES: Set<String> = ["gp", "tgr"]

struct SpeechSpeed {
    let title: String
    let rate: Float
}

// Applied when playing, with the pitch kept: the Core ML model has no speed condition.
let SPEECH_SPEEDS = [
    SpeechSpeed(title: "Very slow", rate: 0.7),
    SpeechSpeed(title: "Slow", rate: 0.85),
    SpeechSpeed(title: "Normal", rate: 1),
    SpeechSpeed(title: "Fast", rate: 1.15),
    SpeechSpeed(title: "Very fast", rate: 1.35),
]
let DEFAULT_SPEED_INDEX = 2
let SPEED_KEY = "speed"
let SPEED_SAMPLE = "This is how fast I speak."
let VOICE_KEY = "voice"
let VOICE_SAMPLE = "Hello, this is how I sound."

let PHONON_VOICES = ["Harper", "Hadley", "Everly", "Maeve", "Edwin", "Spencer"]
// The model folder build.sh puts in the app's Resources, and its copy in Application Support,
// where Core ML compiles it on the first launch.
let MODELS_FOLDER = "Models"
// One sample to schedule after an utterance: its playback marks the end of the speech.
let END_MARKER_SAMPLES = 1

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

let SUPPORT_FOLDER = "Word Popup"
let HISTORY_FILE = "history.json"
let HISTORY_WINDOW_SIZE = NSSize(width: 720, height: 560)
let HISTORY_ROW_HEIGHT: CGFloat = 40
let HISTORY_SPACING: CGFloat = 8
let HISTORY_CELL_INSET: CGFloat = 4
let HISTORY_COLUMNS: [(id: String, title: String, width: CGFloat)] = [
    ("word", "Word", 170),
    ("translation", "Translation", 330),
    ("count", "Times", 50),
    ("date", "Last looked up", 140),
]
let DELETE_KEY_CODES: Set<UInt16> = [UInt16(kVK_Delete), UInt16(kVK_ForwardDelete)]

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

struct DictionaryEntry: Codable {
    var partOfSpeech: String
    var terms: [String]
}

struct Translation: Codable {
    var text: String
    var phonetic: String?
    var dictionary: [DictionaryEntry]
}

struct TranslationFailure: Error {
    let message: String
}

// Words come from the bilingual dictionary that ships with macOS. Phrases it doesn't have go to Google,
// and to Apple's on-device translation when Google fails or limits requests.
enum Translator {
    static func translate(_ text: String, to language: String, completion: @escaping (Result<Translation, TranslationFailure>) -> Void) {
        if let entry = BilingualDictionary.lookUp(text, in: language) {
            completion(.success(entry))
            return
        }
        translateWithGoogle(text, to: language) { google in
            guard case .failure(let googleFailure) = google else { return completion(google) }
            translateWithApple(text, to: language) { apple in
                let hint = "To translate phrases offline, add \(languageName(language)) in \(TRANSLATION_LANGUAGES_SETTINGS)."
                completion(apple.map { .success($0) } ?? .failure(TranslationFailure(message: "\(googleFailure.message) \(hint)")))
            }
        }
    }

    static func languageName(_ language: String) -> String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    private static func translateWithGoogle(_ text: String, to language: String,
                                            completion: @escaping (Result<Translation, TranslationFailure>) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: GOOGLE_LANGUAGE_CODES[language] ?? language),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dt", value: "bd"),
            URLQueryItem(name: "dt", value: "rm"),
            URLQueryItem(name: "q", value: text),
        ]

        let request = URLRequest(url: components.url!, timeoutInterval: GOOGLE_TIMEOUT)
        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<Translation, TranslationFailure>
            if (response as? HTTPURLResponse)?.statusCode == HTTP_TOO_MANY_REQUESTS {
                result = .failure(TranslationFailure(message: "Google is limiting translations right now."))
            } else if let data, let translation = parse(data) {
                result = .success(translation)
            } else {
                let reason = (error ?? URLError(.cannotParseResponse)).localizedDescription
                result = .failure(TranslationFailure(message: "Google Translate failed: \(reason)"))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    // Works only when the language is downloaded in System Settings; nil otherwise.
    private static func translateWithApple(_ text: String, to language: String, completion: @escaping (Translation?) -> Void) {
        Task {
            let session = TranslationSession(installedSource: Locale.Language(identifier: SOURCE_LANGUAGE),
                                             target: Locale.Language(identifier: language))
            let response = try? await session.translate(text)
            await MainActor.run {
                completion(response.map { Translation(text: $0.targetText, phonetic: nil, dictionary: []) })
            }
        }
    }

    // Response shape: [[[translated, original, …], …, [null, null, translit, source translit]], [[pos, [terms], …], …], …]
    private static func parse(_ data: Data) -> Translation? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [[Any]] else { return nil }

        let text = sentences.compactMap { $0.first as? String }.joined()
        let phonetic = sentences.last.flatMap { $0.count > 3 ? $0[3] as? String : nil }
        let entries = (root.count > 1 ? root[1] as? [[Any]] : nil) ?? []
        let dictionary = entries.compactMap { entry -> DictionaryEntry? in
            guard let partOfSpeech = entry.first as? String,
                  let terms = entry.count > 1 ? entry[1] as? [String] : nil else { return nil }
            return DictionaryEntry(partOfSpeech: partOfSpeech, terms: Array(terms.prefix(MAX_DICTIONARY_TERMS)))
        }
        return Translation(text: text, phonetic: phonetic, dictionary: dictionary)
    }
}

@_silgen_name("DCSCopyAvailableDictionaries") private func DCSCopyAvailableDictionaries() -> Unmanaged<CFSet>?
@_silgen_name("DCSDictionaryGetLanguages") private func DCSDictionaryGetLanguages(_ dictionary: DCSDictionary) -> Unmanaged<CFArray>?
@_silgen_name("DCSCopyRecordsForSearchString")
private func DCSCopyRecordsForSearchString(_ dictionary: DCSDictionary, _ text: CFString,
                                           _ method: UnsafeRawPointer?, _ maxResults: UnsafeRawPointer?) -> Unmanaged<CFArray>?
@_silgen_name("DCSRecordCopyData") private func DCSRecordCopyData(_ record: CFTypeRef, _ version: Int) -> Unmanaged<CFString>?
@_silgen_name("DCSRecordGetHeadword") private func DCSRecordGetHeadword(_ record: CFTypeRef) -> Unmanaged<CFString>?

// The bilingual dictionaries that come with macOS, read through private DictionaryServices calls: the public API
// only searches the dictionaries ticked in Dictionary.app and returns an entry as one line of plain text.
// Oxford entries mark parts of speech, translations and examples with classes, so they can be split up.
enum BilingualDictionary {
    // Target language → dictionary, for every dictionary that translates from English.
    static let byLanguage: [String: DCSDictionary] = {
        var found: [String: DCSDictionary] = [:]
        let dictionaries = (DCSCopyAvailableDictionaries()?.takeRetainedValue() as? Set<AnyHashable>) ?? []
        for case let dictionary as DCSDictionary in dictionaries {
            let pairs = DCSDictionaryGetLanguages(dictionary)?.takeUnretainedValue() as? [[String: String]] ?? []
            for pair in pairs where pair[INDEX_LANGUAGE_KEY] == SOURCE_LANGUAGE {
                if let language = pair[DESCRIPTION_LANGUAGE_KEY], language != SOURCE_LANGUAGE, found[language] == nil {
                    found[language] = dictionary
                }
            }
        }
        return found
    }()

    // A dictionary that isn't downloaded yet returns no records, so the phrase translators take over.
    // A phrasal verb comes back as its verb's whole entry, so only its own section is read.
    static func lookUp(_ text: String, in language: String) -> Translation? {
        guard let dictionary = byLanguage[language] else { return nil }
        let records = DCSCopyRecordsForSearchString(dictionary, text as CFString, nil, nil)?.takeRetainedValue() as? [AnyObject] ?? []
        var phonetic: String?
        var entries: [DictionaryEntry] = []
        for record in records.prefix(MAX_DICTIONARY_RECORDS) {
            guard let xhtml = DCSRecordCopyData(record, ENTRY_XHTML_VERSION)?.takeRetainedValue() as String?,
                  let body = (try? XMLDocument(xmlString: xhtml, options: [.nodeLoadExternalEntitiesNever]))?.rootElement()
            else { continue }
            let headword = DCSRecordGetHeadword(record)?.takeUnretainedValue() as String? ?? text
            let phrasalVerb = elements(in: body, withClass: "pvsec").first { section in
                elements(in: section, withClass: "pv").first.map { collapsed($0.stringValue ?? "") }?
                    .caseInsensitiveCompare(headword) == .orderedSame
            }
            if phrasalVerb == nil {
                phonetic = phonetic ?? elements(in: body, withClass: "ph").first.map(plainText)
            }
            for group in elements(in: phrasalVerb ?? body, withClass: "gramb", skipping: phrasalVerb == nil ? ["pvsec"] : []) {
                var terms: [String] = []
                for term in elements(in: group, withClass: "trans", skipping: ["exg"]).map(plainText)
                where !term.isEmpty && !terms.contains(term) {
                    terms.append(term)
                }
                guard !terms.isEmpty else { continue }
                let partOfSpeech = elements(in: group, withClass: "ps").first.map(plainText) ?? ""
                entries.append(DictionaryEntry(partOfSpeech: partOfSpeech, terms: Array(terms.prefix(MAX_DICTIONARY_TERMS))))
            }
        }
        guard let first = entries.first else { return nil }
        return Translation(text: first.terms.prefix(MAIN_TRANSLATION_TERMS).joined(separator: ", "), phonetic: phonetic, dictionary: entries)
    }

    // Walks the tree by hand: XMLNode's relative XPath (".//text()") also returns text after the node.
    private static func elements(in node: XMLNode, withClass name: String, skipping skipped: Set<String> = []) -> [XMLNode] {
        (node.children ?? []).flatMap { child -> [XMLNode] in
            let childClasses = classes(of: child)
            if !childClasses.isDisjoint(with: skipped) { return [] }
            return childClasses.contains(name) ? [child] : elements(in: child, withClass: name, skipping: skipped)
        }
    }

    private static func classes(of node: XMLNode) -> Set<String> {
        Set(((node as? XMLElement)?.attribute(forName: "class")?.stringValue ?? "").split(separator: " ").map(String.init))
    }

    // The node's words without the separators and grammar labels the dictionary adds for display.
    // A verb's imperfective and perfective forms stay apart: "вводить в комнату / ввести в комнату".
    private static func plainText(_ node: XMLNode) -> String {
        let forms = elements(in: node, withClass: "tfrm")
        let text = forms.isEmpty ? visibleText(node) : forms.map(visibleText).map(collapsed).joined(separator: " / ")
        // A removed case label leaves "(с )"; close the gap.
        return collapsed(text).replacingOccurrences(of: " )", with: ")").trimmingCharacters(in: TRAILING_PUNCTUATION)
    }

    private static func visibleText(_ node: XMLNode) -> String {
        if node.kind == .text { return node.stringValue ?? "" }
        if !classes(of: node).isDisjoint(with: HIDDEN_ENTRY_CLASSES) { return "" }
        return (node.children ?? []).map(visibleText).joined()
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - History

struct HistoryEntry: Codable {
    var word: String
    var translation: Translation
    var count: Int
    var lastLookedUp: Date

    func matches(_ query: String) -> Bool {
        ([word, translation.text] + translation.dictionary.flatMap(\.terms)).contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

// Every looked-up word with its translation, newest first. A word looked up again moves to the top.
final class History {
    private(set) var entries: [HistoryEntry] = []
    var onChange: (() -> Void)?
    private let file: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(SUPPORT_FOLDER)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent(HISTORY_FILE)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func record(_ word: String, translation: Translation) {
        var count = 1
        if let index = entries.firstIndex(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
            count += entries.remove(at: index).count
        }
        entries.insert(HistoryEntry(word: word, translation: translation, count: count, lastLookedUp: Date()), at: 0)
        save()
    }

    func remove(_ words: Set<String>) {
        entries.removeAll { words.contains($0.word) }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            entries = try decoder.decode([HistoryEntry].self, from: data)
        } catch {
            // Keep an unreadable file aside rather than overwrite it on the next save.
            try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("unreadable"))
        }
    }

    private func save() {
        try? encoder.encode(entries).write(to: file, options: .atomic)
        onChange?()
    }
}

final class HistoryTable: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if DELETE_KEY_CODES.contains(event.keyCode) { onDelete?() } else { super.keyDown(with: event) }
    }
}

// A list of the history with a search field. Clicking a row speaks the word; ⌫ deletes the selected rows.
final class HistoryWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onSpeak: ((String) -> Void)?

    private let history: History
    private let window: NSWindow
    private let search = NSSearchField()
    private let table = HistoryTable()
    private let dateFormatter = DateFormatter()
    private var shown: [HistoryEntry] = []

    init(history: History) {
        self.history = history
        window = NSWindow(contentRect: NSRect(origin: .zero, size: HISTORY_WINDOW_SIZE),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        super.init()
        window.title = "Word History"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("History")

        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true

        search.placeholderString = "Search words and translations"
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(reload)

        for column in HISTORY_COLUMNS {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.id))
            tableColumn.title = column.title
            tableColumn.width = column.width
            table.addTableColumn(tableColumn)
        }
        table.rowHeight = HISTORY_ROW_HEIGHT
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(speakClickedRow)
        table.onDelete = { [weak self] in self?.deleteSelectedRows() }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        let stack = NSStackView(views: [search, scroll])
        stack.orientation = .vertical
        stack.spacing = HISTORY_SPACING
        stack.edgeInsets = NSEdgeInsets(top: HISTORY_SPACING, left: HISTORY_SPACING, bottom: HISTORY_SPACING, right: HISTORY_SPACING)
        window.contentView = stack

        history.onChange = { [weak self] in self?.reload() }
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reload() {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        shown = query.isEmpty ? history.entries : history.entries.filter { $0.matches(query) }
        table.reloadData()
    }

    @objc private func speakClickedRow() {
        guard shown.indices.contains(table.clickedRow) else { return }
        onSpeak?(shown[table.clickedRow].word)
    }

    private func deleteSelectedRows() {
        history.remove(Set(table.selectedRowIndexes.map { shown[$0].word }))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let entry = shown[row]
        let view = cell(id)
        switch id.rawValue {
        case "word":
            view.textField?.attributedStringValue = twoLines(entry.word, entry.translation.phonetic.map { "[\($0)]" })
        case "translation":
            let meanings = entry.translation.dictionary.map { "\($0.partOfSpeech): \($0.terms.joined(separator: ", "))" }
            view.textField?.attributedStringValue = twoLines(entry.translation.text, meanings.isEmpty ? nil : meanings.joined(separator: "; "))
            view.toolTip = ([entry.translation.text] + meanings).joined(separator: "\n")
        case "count":
            view.textField?.stringValue = "×\(entry.count)"
        default:
            view.textField?.stringValue = dateFormatter.string(from: entry.lastLookedUp)
        }
        return view
    }

    private func cell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        if let reused = table.makeView(withIdentifier: id, owner: self) as? NSTableCellView { return reused }
        let view = NSTableCellView()
        view.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.maximumNumberOfLines = 2
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        view.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HISTORY_CELL_INSET),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HISTORY_CELL_INSET),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    // Each line is cut with an ellipsis instead of wrapping.
    private func twoLines(_ main: String, _ detail: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: main, attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .paragraphStyle: paragraph,
        ])
        if let detail {
            text.append(NSAttributedString(string: "\n\(detail)", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .paragraphStyle: paragraph,
            ]))
        }
        return text
    }
}

// MARK: - Speech

// Speaks with Phonon on the Neural Engine. The model ships in the app's Resources and is copied to Application Support
// on the first launch, where Core ML compiles it (several seconds, once); later launches load it in about half a second.
// Audio plays as it's generated, through a time-pitch unit that sets the speed without changing the voice.
// Its state is only touched on the main thread: chunks from the generating task arrive through the main queue.
final class Speaker: @unchecked Sendable {
    var voice = PHONON_VOICES[0]
    var speed = SPEECH_SPEEDS[DEFAULT_SPEED_INDEX]
    private var phonon: Task<Phonon, Error>?
    private var generation: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Phonon.sampleRate, channels: 1)!
    private var request = 0
    private var samples: [Float] = []
    // Kept without the speed, which only changes playback.
    private var cached: (key: String, samples: [Float])?

    init() {
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    // Starts loading the model with the current voice, so the first word doesn't wait for it.
    func load() {
        let voice = voice
        phonon = Task.detached {
            guard let bundled = Bundle.main.url(forResource: MODELS_FOLDER, withExtension: nil) else {
                throw PhononError(description: "The app has no \(MODELS_FOLDER) folder: build it with build.sh.")
            }
            let installed = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(SUPPORT_FOLDER).appendingPathComponent(MODELS_FOLDER)
            let phonon = try await Phonon.load(models: PhononModels.install(bundled: bundled, to: installed), language: .english)
            try await phonon.setVoice(voice)
            return phonon
        }
    }

    // Beeps when the model can't load or speak.
    func speak(_ text: String) {
        stop()
        let current = request
        let key = "\(voice)|\(text)"
        if let cached, cached.key == key {
            enqueue(cached.samples, for: current)
            finish(key: key, for: current)
            return
        }
        guard let phonon else { return NSSound.beep() }

        let voice = voice
        generation = Task.detached { [weak self] in
            do {
                let phonon = try await phonon.value
                if phonon.voice != voice { try await phonon.setVoice(voice) }
                try await phonon.speak(text) { chunk in
                    DispatchQueue.main.async { self?.enqueue(chunk, for: current) }
                }
                DispatchQueue.main.async { self?.finish(key: key, for: current) }
            } catch {
                NSLog("Phonon failed: %@", String(describing: error))
                DispatchQueue.main.async { if self?.request == current { NSSound.beep() } }
            }
        }
    }

    // Also invalidates the running request, so chunks still on their way are dropped.
    func stop() {
        request += 1
        generation?.cancel()
        generation = nil
        samples = []
        node.stop()
    }

    private func enqueue(_ chunk: [Float], for current: Int) {
        guard request == current, let buffer = buffer(chunk) else { return }
        samples += chunk
        timePitch.rate = speed.rate
        if !engine.isRunning { try? engine.start() }
        node.scheduleBuffer(buffer)
        if !node.isPlaying { node.play() }
    }

    // Caches the finished utterance and pauses the engine once it has played, so the idle app doesn't keep audio running.
    private func finish(key: String, for current: Int) {
        guard request == current, let marker = buffer([Float](repeating: 0, count: END_MARKER_SAMPLES)) else { return }
        cached = (key, samples)
        node.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { if self?.request == current { self?.engine.pause() } }
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
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

final class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        popup.onReplay = { [weak self] in self.map { $0.speaker.speak($0.currentWord) } }
        hotKey = HotKey(keyCode: HOTKEY_KEY_CODE, modifiers: HOTKEY_MODIFIERS) { [weak self] in self?.lookUpSelection() }
        doubleTap = DoubleTap(modifier: DOUBLE_TAP_MODIFIER) { [weak self] in self?.lookUpSelection() }
        let savedSpeed = UserDefaults.standard.string(forKey: SPEED_KEY)
        if let speed = SPEECH_SPEEDS.first(where: { $0.title == savedSpeed }) { speaker.speed = speed }
        if let voice = UserDefaults.standard.string(forKey: VOICE_KEY), PHONON_VOICES.contains(voice) { speaker.voice = voice }
        speaker.load()
        targetLanguage = UserDefaults.standard.string(forKey: TARGET_LANGUAGE_KEY) ?? AppDelegate.preferredTargetLanguage()
        setUpMenu()
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

        Translator.translate(word, to: targetLanguage) { [weak self] result in
            guard let self, self.currentWord == word else { return }
            switch result {
            case .success(let translation):
                self.history.record(word, translation: translation)
                self.popup.show(word: word, translation: translation, status: nil)
            case .failure(let failure):
                self.popup.show(word: word, translation: nil, status: failure.message)
            }
        }
    }

    // The preferred languages in System Settings → Language & Region first, then the rest by name.
    private static func targetLanguages() -> (preferred: [String], others: [String]) {
        var others = BilingualDictionary.byLanguage.keys.sorted { Translator.languageName($0) < Translator.languageName($1) }
        var preferred: [String] = []
        for identifier in Locale.preferredLanguages {
            if let index = others.firstIndex(where: { sameLanguage($0, identifier) }) { preferred.append(others.remove(at: index)) }
        }
        return (preferred, others)
    }

    private static func preferredTargetLanguage() -> String {
        let languages = targetLanguages()
        return languages.preferred.first ?? languages.others.first ?? DEFAULT_TARGET_LANGUAGE
    }

    // Same language and script, so Simplified Chinese doesn't match Traditional.
    private static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        let (left, right) = (Locale.Language(identifier: lhs), Locale.Language(identifier: rhs))
        return left.languageCode == right.languageCode
            && Locale.Language(identifier: left.maximalIdentifier).script == Locale.Language(identifier: right.maximalIdentifier).script
    }

    private func targetLanguageMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let languages = AppDelegate.targetLanguages()
        for group in [languages.preferred, languages.others] where !group.isEmpty {
            if submenu.numberOfItems > 0 { submenu.addItem(.separator()) }
            for language in group {
                let option = submenu.addItem(withTitle: Translator.languageName(language), action: #selector(changeTargetLanguage), keyEquivalent: "")
                option.target = self
                option.representedObject = language
                option.state = language == targetLanguage ? .on : .off
            }
        }
        let item = NSMenuItem(title: "Translate to", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func changeTargetLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        targetLanguage = language
        UserDefaults.standard.set(language, forKey: TARGET_LANGUAGE_KEY)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
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
        for submenu in [NSMenu(title: "Word Popup"), edit, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Word Popup")

        let menu = NSMenu()
        menu.addItem(withTitle: "Speak & translate selection (\(DOUBLE_TAP_LABEL) or \(HOTKEY_LABEL))", action: #selector(lookUpSelection), keyEquivalent: "")
        menu.addItem(withTitle: "History…", action: #selector(showHistory), keyEquivalent: "")
        menu.addItem(targetLanguageMenuItem())
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

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
