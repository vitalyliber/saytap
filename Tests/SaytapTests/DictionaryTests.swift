import Testing
@testable import Saytap

struct DictionaryTests {
    let harbour = BilingualDictionary.translation(from: Fixture.records("dictionary-harbours"))
    let showUp = BilingualDictionary.translation(from: Fixture.records("dictionary-show-up"))
    let introduce = BilingualDictionary.translation(from: Fixture.records("dictionary-introduce"))

    @Test func mainTranslationIsTheFirstTwoTerms() {
        #expect(harbour?.text == "га́вань, порт")
    }

    @Test func readsTheTranscription() {
        #expect(harbour?.phonetic == "ˈhɑːbə")
    }

    @Test func groupsTermsByPartOfSpeech() {
        #expect(harbour?.dictionary.map(\.partOfSpeech) == ["noun", "transitive verb"])
    }

    @Test func leavesExamplesOut() {
        #expect(harbour?.dictionary.first?.terms == ["га́вань", "порт", "убе́жище"])
    }

    @Test func joinsImperfectiveAndPerfectiveForms() {
        #expect(harbour?.dictionary.last?.terms == ["дава́ть убе́жище / дать убе́жище", "укрыва́ть / укры́ть"])
    }

    @Test func readsOnlyThePhrasalVerbsSection() {
        #expect(showUp?.dictionary.map(\.partOfSpeech) == ["transitive verb", "intransitive verb"])
    }

    @Test func phrasalVerbHasNoTranscription() {
        #expect(showUp?.phonetic == nil)
    }

    @Test func hidesGrammarLabels() {
        let terms = introduce?.dictionary.flatMap(\.terms) ?? []
        #expect(!terms.contains { $0.contains("impf") || $0.contains(" pf") })
    }

    @Test func noRecordsMeanNoTranslation() {
        #expect(BilingualDictionary.translation(from: []) == nil)
    }
}
