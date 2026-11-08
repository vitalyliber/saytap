import Foundation
@testable import WordPopup

enum Fixture {
    static func data(_ name: String) -> Data {
        try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
    }

    // Records saved from the Oxford Russian Dictionary: [{"headword": …, "xhtml": …}].
    static func records(_ name: String) -> [DictionaryRecord] {
        let saved = try! JSONDecoder().decode([[String: String]].self, from: data(name))
        return saved.map { DictionaryRecord(headword: $0["headword"]!, xhtml: $0["xhtml"]!) }
    }

    static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(HISTORY_FILE)
    }
}
