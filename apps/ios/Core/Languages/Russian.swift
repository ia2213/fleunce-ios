import Foundation

extension LanguageModule {
    public static let russian = LanguageModule(
        id: "ru", name: "Russian", nativeName: "Русский", variety: "Standard", locale: "ru-RU",
        greeting: "Привет!", greetingWord: "Привет",
        speechGuidance: "Use clear Standard Russian pronunciation.",
        writingGuidance: "Use standard Cyrillic script.",
        lemmaGuidance: "Give nouns in nominative singular and verbs in infinitive.",
        teachingFocus: ["Everyday Russian phrases", "Cases and verb aspects"],
        topicPlaceholder: "Travel, literature, daily life...",
        lookupUnavailableReply: "Извините, не удалось проверить сейчас.",
        themeOverrides: [:]
    )
}
