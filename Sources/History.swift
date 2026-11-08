import Foundation

struct HistoryEntry: Codable {
    var word: String
    var translation: Translation
    // Missing in entries saved before translations were reused.
    var language: String?
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

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(SUPPORT_FOLDER).appendingPathComponent(HISTORY_FILE)) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.file = file
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func record(_ word: String, translation: Translation, language: String) {
        var count = 1
        if let index = entries.firstIndex(where: { $0.word.caseInsensitiveCompare(word) == .orderedSame }) {
            count += entries.remove(at: index).count
        }
        entries.insert(HistoryEntry(word: word, translation: translation, language: language, count: count, lastLookedUp: Date()), at: 0)
        save()
    }

    func translation(of word: String, in language: String) -> Translation? {
        entries.first { $0.word.caseInsensitiveCompare(word) == .orderedSame && $0.language == language }?.translation
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
