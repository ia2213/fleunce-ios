import Foundation

extension LanguageModule {
    public static let hebrew = LanguageModule(
        id: "he", name: "Hebrew", nativeName: "עברית", variety: "Modern Standard", locale: "he-IL",
        greeting: "שלום!", greetingWord: "שלום",
        speechGuidance: "Use clear Modern Hebrew with natural Israeli pronunciation.",
        writingGuidance: "Use standard Hebrew alphabet.",
        lemmaGuidance: "Give nouns in singular masculine/feminine and verbs in ground form.",
        teachingFocus: ["Everyday Hebrew phrases", "Roots and conversation"],
        topicPlaceholder: "Travel, Israeli culture, daily life...",
        lookupUnavailableReply: "סליחה, לא הצלחתי לבדוק את זה עכשיו.",
        themeOverrides: [:]
    )
}
