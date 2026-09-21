import Foundation

extension LanguageModule {
    public static let britishEnglish = LanguageModule(
        id: "en-GB", name: "English (UK)", nativeName: "British English", variety: "British Accent", locale: "en-GB",
        greeting: "Hello there!", greetingWord: "hello",
        speechGuidance: "Use clear, natural Received Pronunciation or Standard Southern British English pronunciation. Focus on British vocabulary and phrasing.",
        writingGuidance: "Use standard British English spelling (e.g., colour, favour, organise).",
        lemmaGuidance: "Give countable nouns in singular and verbs in base form.",
        teachingFocus: ["Everyday British conversation", "British expressions and vocabulary"],
        topicPlaceholder: "Travel, UK culture, tea, daily life...",
        lookupUnavailableReply: "I couldn't check that right now.",
        themeOverrides: [:]
    )
}
