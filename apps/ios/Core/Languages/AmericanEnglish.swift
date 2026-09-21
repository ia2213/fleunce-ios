import Foundation

extension LanguageModule {
    public static let americanEnglish = LanguageModule(
        id: "en-US", name: "English (US)", nativeName: "American English", variety: "American Accent", locale: "en-US",
        greeting: "Hey there!", greetingWord: "hey",
        speechGuidance: "Use clear, natural General American English pronunciation. Focus on American vocabulary and idioms.",
        writingGuidance: "Use standard American English spelling (e.g., color, favor, organize).",
        lemmaGuidance: "Give countable nouns in singular and verbs in base form.",
        teachingFocus: ["Everyday American conversation", "American idioms and phrasal verbs"],
        topicPlaceholder: "Travel, US culture, tech, work...",
        lookupUnavailableReply: "I couldn't look that up right now.",
        themeOverrides: [:]
    )
}
