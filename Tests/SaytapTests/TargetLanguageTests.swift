import Testing
@testable import Saytap

struct TargetLanguageTests {
    let languages = AppDelegate.targetLanguages(available: ["de", "zh-Hans", "ru", "zh-Hant", "es"],
                                                preferredLanguages: ["en-US", "ru-RU", "zh-Hant-TW"])

    @Test func systemLanguagesComeFirstInTheirOrder() {
        #expect(languages.preferred == ["ru", "zh-Hant"])
    }

    @Test func theRestFollow() {
        #expect(Set(languages.others) == ["de", "es", "zh-Hans"])
    }

    @Test func simplifiedChineseIsNotTraditional() {
        #expect(!AppDelegate.sameLanguage("zh-Hans", "zh-Hant-TW"))
    }

    @Test func regionDoesNotMatter() {
        #expect(AppDelegate.sameLanguage("ru", "ru-RU"))
    }
}
