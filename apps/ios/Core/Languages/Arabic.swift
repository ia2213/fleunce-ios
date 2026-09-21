import Foundation

extension LanguageModule {
    public static let arabic = LanguageModule(
        id: "ar", name: "Arabic", nativeName: "العربية", variety: "Modern Standard", locale: "ar-SA",
        greeting: "مرحبًا!", greetingWord: "مرحبا",
        speechGuidance: "Use clear Modern Standard Arabic (Fusha) with natural pronunciation.",
        writingGuidance: "Use standard Arabic script with clear diacritics where necessary for clarity.",
        lemmaGuidance: "Give nouns in singular and verbs in past singular 3rd person form.",
        teachingFocus: ["Everyday Arabic greetings and customs", "Grammar, roots and vocabulary"],
        topicPlaceholder: "Travel, culture, coffee, daily life...",
        lookupUnavailableReply: "عذرًا، لم أتمكن من البحث الآن.",
        themeOverrides: [:]
    )
}
