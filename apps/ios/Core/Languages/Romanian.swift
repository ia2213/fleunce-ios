import Foundation

extension LanguageModule {
    public static let romanian = LanguageModule(
        id: "ro", name: "Romanian", nativeName: "Română", variety: "Standard", locale: "ro-RO",
        greeting: "Salut!", greetingWord: "salut",
        speechGuidance: "Use clear Standard Romanian pronunciation.",
        writingGuidance: "Use standard Romanian diacritics (ș, ț, ă, î, â).",
        lemmaGuidance: "Give nouns in nominative singular with indefinite article and verbs in dictionary infinitive form.",
        teachingFocus: ["Everyday Romanian phrases", "Nouns, cases and natural expressions"],
        topicPlaceholder: "Travel, Romanian customs, daily life...",
        lookupUnavailableReply: "Ne pare rău, nu am putut verifica acum.",
        themeOverrides: [:]
    )
}
