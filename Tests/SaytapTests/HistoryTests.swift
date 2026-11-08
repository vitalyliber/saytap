import Foundation
import Testing
@testable import Saytap

struct HistoryTests {
    let harbour = Translation(text: "гавань", phonetic: nil, dictionary: [])
    let file = Fixture.temporaryFile()

    func history(_ words: [String], language: String = "ru") -> History {
        let history = History(file: file)
        for word in words { history.record(word, translation: harbour, language: language) }
        return history
    }

    @Test func wordLookedUpAgainIsOneEntry() {
        #expect(history(["Harbour", "harbour"]).entries.count == 1)
    }

    @Test func wordLookedUpAgainCountsBoth() {
        #expect(history(["Harbour", "harbour"]).entries.first?.count == 2)
    }

    @Test func wordLookedUpAgainMovesToTheTop() {
        #expect(history(["harbour", "port", "harbour"]).entries.map(\.word) == ["harbour", "port"])
    }

    @Test func reusesATranslationInTheSameLanguage() {
        #expect(history(["harbour"]).translation(of: "HARBOUR", in: "ru") == harbour)
    }

    @Test func doesNotReuseATranslationInAnotherLanguage() {
        #expect(history(["harbour"]).translation(of: "harbour", in: "de") == nil)
    }

    @Test func keepsTheHistoryAcrossLaunches() {
        _ = history(["harbour"])
        #expect(History(file: file).entries.map(\.word) == ["harbour"])
    }

    @Test func readsEntriesSavedWithoutALanguage() throws {
        try saveOldEntry()
        #expect(History(file: file).entries.map(\.word) == ["harbour"])
    }

    @Test func doesNotReuseEntriesSavedWithoutALanguage() throws {
        try saveOldEntry()
        #expect(History(file: file).translation(of: "harbour", in: "ru") == nil)
    }

    @Test func keepsAnUnreadableFileAside() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        _ = History(file: file)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("unreadable").path))
    }

    private func saveOldEntry() throws {
        let old = #"[{"word": "harbour", "translation": {"text": "гавань", "dictionary": []}, "count": 1, "lastLookedUp": "2026-11-01T10:00:00Z"}]"#
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(old.utf8).write(to: file)
    }
}
