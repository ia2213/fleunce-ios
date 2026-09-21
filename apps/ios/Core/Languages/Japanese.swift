import Foundation

extension LanguageModule {
    public static let japanese = LanguageModule(
        id: "ja", name: "Japanese", nativeName: "日本語", variety: "Standard", locale: "ja-JP",
        greeting: "こんにちは！", greetingWord: "こんにちは",
        speechGuidance: "Use natural Standard Japanese (Hyojungo) with appropriate politeness levels (Desu/Masu).",
        writingGuidance: "Use standard Kanji, Hiragana and Katakana.",
        lemmaGuidance: "Give verbs in dictionary form.",
        teachingFocus: ["Everyday Japanese phrases", "Keigo and natural expressions"],
        topicPlaceholder: "Travel, food, anime, culture...",
        lookupUnavailableReply: "申し訳ありません。現在調べられませんでした。",
        themeOverrides: [:]
    )
}
