import Testing
@testable import WordPopup

struct TranslatorTests {
    let fromDictionary = Translation(text: "from the dictionary", phonetic: nil, dictionary: [])
    let remembered = Translation(text: "remembered", phonetic: nil, dictionary: [])
    let fromGoogle = Translation(text: "from Google", phonetic: nil, dictionary: [])
    let fromApple = Translation(text: "from Apple", phonetic: nil, dictionary: [])
    let googleLimit = TranslationFailure(message: "Google is limiting translations right now.")

    // The sources answer at once, so the completion has run when translate returns.
    func translate(dictionary: Translation?, remembered: Translation?, google: Result<Translation, TranslationFailure>,
                   apple: Translation?) -> Result<Translation, TranslationFailure>? {
        var result: Result<Translation, TranslationFailure>?
        Translator.translate("word", to: "ru", remembered: remembered,
                             dictionary: { _, _ in dictionary },
                             google: { _, _, completion in completion(google) },
                             apple: { _, _, completion in completion(apple) }) { result = $0 }
        return result
    }

    @Test func dictionaryComesFirst() {
        let result = translate(dictionary: fromDictionary, remembered: remembered, google: .success(fromGoogle), apple: fromApple)
        #expect(result?.translation == fromDictionary)
    }

    @Test func rememberedTranslationSavesARequest() {
        let result = translate(dictionary: nil, remembered: remembered, google: .success(fromGoogle), apple: fromApple)
        #expect(result?.translation == remembered)
    }

    @Test func googleTranslatesWhatIsNew() {
        let result = translate(dictionary: nil, remembered: nil, google: .success(fromGoogle), apple: fromApple)
        #expect(result?.translation == fromGoogle)
    }

    @Test func appleStepsInWhenGoogleFails() {
        let result = translate(dictionary: nil, remembered: nil, google: .failure(googleLimit), apple: fromApple)
        #expect(result?.translation == fromApple)
    }

    @Test func failureExplainsGoogleAndHowToGoOffline() {
        let result = translate(dictionary: nil, remembered: nil, google: .failure(googleLimit), apple: nil)
        let hint = "To translate phrases offline, add \(Translator.languageName("ru")) in \(TRANSLATION_LANGUAGES_SETTINGS)."
        #expect(result?.failureMessage == "\(googleLimit.message) \(hint)")
    }
}
