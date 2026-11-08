import Foundation
import Translation

struct DictionaryEntry: Codable, Equatable {
    var partOfSpeech: String
    var terms: [String]
}

struct Translation: Codable, Equatable {
    var text: String
    var phonetic: String?
    var dictionary: [DictionaryEntry]
}

struct TranslationFailure: Error {
    let message: String
}

// Words come from the bilingual dictionary that ships with macOS. Phrases it doesn't have come from the history when
// they were translated before, otherwise from Google, and from Apple's on-device translation when Google fails.
enum Translator {
    typealias DictionaryLookUp = (_ text: String, _ language: String) -> Translation?
    typealias GoogleTranslation = (_ text: String, _ language: String,
                                   _ completion: @escaping (Result<Translation, TranslationFailure>) -> Void) -> Void
    typealias AppleTranslation = (_ text: String, _ language: String, _ completion: @escaping (Translation?) -> Void) -> Void

    // A remembered translation saves a request, but comes after the dictionary, which may have been downloaded since.
    // The sources are parameters so tests can replace them.
    static func translate(_ text: String, to language: String, remembered: Translation?,
                          dictionary: DictionaryLookUp = BilingualDictionary.lookUp, google: @escaping GoogleTranslation = translateWithGoogle,
                          apple: @escaping AppleTranslation = translateWithApple,
                          completion: @escaping (Result<Translation, TranslationFailure>) -> Void) {
        if let entry = dictionary(text, language) ?? remembered {
            completion(.success(entry))
            return
        }
        google(text, language) { google in
            guard case .failure(let googleFailure) = google else { return completion(google) }
            apple(text, language) { apple in
                let hint = "To translate phrases offline, add \(languageName(language)) in \(TRANSLATION_LANGUAGES_SETTINGS)."
                completion(apple.map { .success($0) } ?? .failure(TranslationFailure(message: "\(googleFailure.message) \(hint)")))
            }
        }
    }

    static func languageName(_ language: String) -> String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    static func translateWithGoogle(_ text: String, to language: String,
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
            let result = googleResult(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    static func googleResult(data: Data?, response: URLResponse?, error: Error?) -> Result<Translation, TranslationFailure> {
        if (response as? HTTPURLResponse)?.statusCode == HTTP_TOO_MANY_REQUESTS {
            return .failure(TranslationFailure(message: "Google is limiting translations right now."))
        }
        if let data, let translation = parse(data) {
            return .success(translation)
        }
        let reason = (error ?? URLError(.cannotParseResponse)).localizedDescription
        return .failure(TranslationFailure(message: "Google Translate failed: \(reason)"))
    }

    // Works only when the language is downloaded in System Settings; nil otherwise.
    static func translateWithApple(_ text: String, to language: String, completion: @escaping (Translation?) -> Void) {
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
    static func parse(_ data: Data) -> Translation? {
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
