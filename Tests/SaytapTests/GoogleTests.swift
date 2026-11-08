import Foundation
import Testing
@testable import Saytap

struct GoogleTests {
    let url = URL(string: "https://translate.googleapis.com/translate_a/single")!

    @Test func readsThePhraseTranslation() {
        #expect(Translator.parse(Fixture.data("google-practically-no-change"))?.text == "практически без изменений")
    }

    @Test func readsTheWordsDictionary() {
        #expect(Translator.parse(Fixture.data("google-harbour"))?.dictionary.first?.partOfSpeech == "noun")
    }

    @Test func tooManyRequestsSaysGoogleIsLimiting() {
        let response = HTTPURLResponse(url: url, statusCode: HTTP_TOO_MANY_REQUESTS, httpVersion: nil, headerFields: nil)
        let result = Translator.googleResult(data: Data(), response: response, error: nil)
        #expect(result.failureMessage == "Google is limiting translations right now.")
    }

    @Test func unreadableResponseIsAFailure() {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        let result = Translator.googleResult(data: Data("<html>".utf8), response: response, error: nil)
        #expect(result.failureMessage?.hasPrefix("Google Translate failed:") == true)
    }
}

extension Result where Success == Translation, Failure == TranslationFailure {
    var translation: Translation? { try? get() }

    var failureMessage: String? {
        if case .failure(let failure) = self { failure.message } else { nil }
    }
}
