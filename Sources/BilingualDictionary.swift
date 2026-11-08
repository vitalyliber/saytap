import CoreServices
import Foundation

@_silgen_name("DCSCopyAvailableDictionaries") private func DCSCopyAvailableDictionaries() -> Unmanaged<CFSet>?
@_silgen_name("DCSDictionaryGetLanguages") private func DCSDictionaryGetLanguages(_ dictionary: DCSDictionary) -> Unmanaged<CFArray>?
@_silgen_name("DCSCopyRecordsForSearchString")
private func DCSCopyRecordsForSearchString(_ dictionary: DCSDictionary, _ text: CFString,
                                           _ method: UnsafeRawPointer?, _ maxResults: UnsafeRawPointer?) -> Unmanaged<CFArray>?
@_silgen_name("DCSRecordCopyData") private func DCSRecordCopyData(_ record: CFTypeRef, _ version: Int) -> Unmanaged<CFString>?
@_silgen_name("DCSRecordGetHeadword") private func DCSRecordGetHeadword(_ record: CFTypeRef) -> Unmanaged<CFString>?
// nil until the dictionary is downloaded.
@_silgen_name("DCSDictionaryGetURL") private func DCSDictionaryGetURL(_ dictionary: DCSDictionary) -> Unmanaged<CFURL>?

// The bilingual dictionaries that come with macOS, read through private DictionaryServices calls: the public API
// only searches the dictionaries ticked in Dictionary.app and returns an entry as one line of plain text.
// Oxford entries mark parts of speech, translations and examples with classes, so they can be split up.
struct DictionaryRecord {
    let headword: String
    let xhtml: String
}

enum BilingualDictionary {
    // Target language → dictionary, for every dictionary that translates from English. Read again by refresh(),
    // since dictionaries are downloaded while the app runs.
    private(set) static var byLanguage = available()

    static func refresh() {
        byLanguage = available()
    }

    static func isDownloaded(_ language: String) -> Bool {
        byLanguage[language].map(isDownloaded) ?? false
    }

    // Takes about a minute; refresh() then finds it downloaded.
    static func startDownload(_ language: String) {
        guard let dictionary = byLanguage[language] else { return }
        _ = DCSCopyRecordsForSearchString(dictionary, DOWNLOAD_TRIGGER_WORD as CFString, nil, nil)?.takeRetainedValue()
    }

    // A language with two dictionaries gets the downloaded one.
    private static func available() -> [String: DCSDictionary] {
        var found: [String: DCSDictionary] = [:]
        let dictionaries = (DCSCopyAvailableDictionaries()?.takeRetainedValue() as? Set<AnyHashable>) ?? []
        for case let dictionary as DCSDictionary in dictionaries {
            let pairs = DCSDictionaryGetLanguages(dictionary)?.takeUnretainedValue() as? [[String: String]] ?? []
            for pair in pairs where pair[INDEX_LANGUAGE_KEY] == SOURCE_LANGUAGE {
                guard let language = pair[DESCRIPTION_LANGUAGE_KEY], language != SOURCE_LANGUAGE else { continue }
                if found[language].map({ !isDownloaded($0) && isDownloaded(dictionary) }) ?? true {
                    found[language] = dictionary
                }
            }
        }
        return found
    }

    private static func isDownloaded(_ dictionary: DCSDictionary) -> Bool {
        DCSDictionaryGetURL(dictionary) != nil
    }

    // A dictionary that isn't downloaded yet returns no records, so the phrase translators take over.
    // A phrasal verb comes back as its verb's whole entry, so only its own section is read.
    static func lookUp(_ text: String, in language: String) -> Translation? {
        guard let dictionary = byLanguage[language] else { return nil }
        let records = DCSCopyRecordsForSearchString(dictionary, text as CFString, nil, nil)?.takeRetainedValue() as? [AnyObject] ?? []
        return translation(from: records.prefix(MAX_DICTIONARY_RECORDS).compactMap { record in
            (DCSRecordCopyData(record, ENTRY_XHTML_VERSION)?.takeRetainedValue() as String?).map { xhtml in
                DictionaryRecord(headword: DCSRecordGetHeadword(record)?.takeUnretainedValue() as String? ?? text, xhtml: xhtml)
            }
        })
    }

    static func translation(from records: [DictionaryRecord]) -> Translation? {
        var phonetic: String?
        var entries: [DictionaryEntry] = []
        for record in records {
            guard let body = (try? XMLDocument(xmlString: record.xhtml, options: [.nodeLoadExternalEntitiesNever]))?.rootElement()
            else { continue }
            let headword = record.headword
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
