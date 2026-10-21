import SwiftUI
import FluenceCore

struct OnboardingView: View {
    let coordinator: ConversationCoordinator
    let done: () -> Void
    @State private var step = 0
    @State private var targetID: String
    @State private var meaningLanguage: String
    @State private var hasChosenMeaning: Bool
    @State private var apiKeyInput: String = ""
    @State private var greetingIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    init(coordinator: ConversationCoordinator, done: @escaping () -> Void) {
        self.coordinator = coordinator
        self.done = done
        _targetID = State(initialValue: coordinator.language.id)
        _meaningLanguage = State(initialValue: coordinator.store.preferences.meaningLanguage.isEmpty ? "Français" : coordinator.store.preferences.meaningLanguage)
        _hasChosenMeaning = State(initialValue: coordinator.store.preferences.meaningLanguage != Preferences().meaningLanguage)
        _apiKeyInput = State(initialValue: KeychainHelper.shared.read(for: .groq) ?? "")
    }

    private var target: LanguageModule { LanguageRegistry.module(for: targetID) ?? .german }
    private var greeting: String { reduceMotion ? target.greeting : LanguageRegistry.all[greetingIndex].greeting }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button { move(to: step - 1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                            .background(FluenceColor.surfaceSecondary, in: Circle())
                    }.accessibilityLabel("Retour").accessibilityIdentifier("onboarding-back")
                } else { Brand() }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == step ? FluenceColor.accent : FluenceColor.secondary.opacity(0.25))
                            .frame(width: index == step ? 24 : 8, height: 6)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("Étape \(step + 1) sur 3")
            }.padding(.horizontal, 24).padding(.top, 12).frame(height: 54)

            ScrollView {
                VStack(spacing: step == 0 ? 20 : 18) {
                    VStack(spacing: 6) {
                        Text(greeting)
                            .font(.system(size: typeSize.isAccessibilitySize ? 44 : 52, weight: .bold, design: .rounded))
                            .tracking(-1.5).id(greeting)
                            .foregroundStyle(FluenceColor.ink)
                            .transition(.opacity)
                            .frame(height: 64)
                            .accessibilityIdentifier("onboarding-greeting")
                    }.padding(.top, 8).accessibilityElement(children: .ignore).accessibilityLabel("Bienvenue sur Fluence")

                    Group {
                        if step == 0 { languageStep }
                        else if step == 1 { meaningStep }
                        else { aiEngineStep }
                    }.id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 14)))
                    
                    if step == 1 && typeSize.isAccessibilitySize { consentDetails }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }.scrollIndicators(.hidden).id(step)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if step == 1 && !typeSize.isAccessibilitySize { consentDetails }
                Button {
                    advance()
                } label: {
                    Text(step < 2 ? "Continuer" : "🚀 Commencer l'apprentissage")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(FluenceColor.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: FluenceColor.accent.opacity(0.3), radius: 8, y: 3)
                }
                .accessibilityIdentifier("onboarding-continue")
                
                if !typeSize.isAccessibilitySize {
                    Text(step == 0 ? "Nous adapterons le rythme de la conversation à votre niveau." : (step == 1 ? "Vous pouvez modifier ces deux langues à tout moment dans les Réglages." : "Vos données et clés restent chiffrées sur votre iPhone."))
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .background(FluenceColor.surface.ignoresSafeArea())
        }
        .background(FluenceColor.background.ignoresSafeArea())
        .foregroundStyle(FluenceColor.ink).tint(FluenceColor.accent)
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: targetID)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3.8)) } catch { return }
                guard !Task.isCancelled else { return }
                if scenePhase == .active {
                    withAnimation(.easeInOut(duration: 0.6)) { greetingIndex = (greetingIndex + 1) % LanguageRegistry.all.count }
                }
            }
        }
    }

    private var consentDetails: some View {
        VStack(spacing: 8) {
            Text(AIProcessingConsent.summary)
                .font(.footnote).foregroundStyle(FluenceColor.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding-ai-consent")
            Link("Politique de confidentialité", destination: URL(string: "https://fluence.chat/privacy/")!)
                .font(.footnote).underline().foregroundStyle(FluenceColor.accent).accessibilityIdentifier("onboarding-privacy-policy")
        }
    }

    private func frenchName(for id: String, fallback: String) -> String {
        switch id {
        case "de": return "Allemand"
        case "fr": return "Français"
        case "en-US": return "Anglais (Américain)"
        case "en-GB": return "Anglais (Britannique)"
        case "es": return "Espagnol"
        case "it": return "Italien"
        case "ro": return "Roumain"
        case "pt": return "Portugais"
        case "zh": return "Chinois (Mandarin)"
        case "ja": return "Japonais"
        case "ru": return "Russe"
        case "ar": return "Arabe"
        case "he": return "Hébreu"
        case "no": return "Norvégien"
        default: return fallback
        }
    }

    private var languageStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Quelle langue souhaitez-vous parler ?")
                    .font(.title2.bold())
                    .foregroundStyle(FluenceColor.ink)
                    .multilineTextAlignment(.center)
                Text("Choisissez votre langue d'apprentissage principale")
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.secondary)
            }
            .padding(.bottom, 2)
            
            LazyVStack(spacing: 10) {
                ForEach(LanguageRegistry.all) { language in
                    let isSelected = targetID == language.id
                    Button {
                        targetID = language.id
                    } label: {
                        HStack(spacing: 14) {
                            Text(language.flag)
                                .font(.system(size: 30))
                                .frame(width: 42, height: 42)
                                .background(isSelected ? FluenceColor.accent.opacity(0.18) : FluenceColor.surfaceSecondary, in: Circle())
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(frenchName(for: language.id, fallback: language.nativeName))
                                    .font(.headline.bold())
                                    .foregroundStyle(FluenceColor.ink)
                                Text("\(language.nativeName) · \(language.variety)")
                                    .font(.caption)
                                    .foregroundStyle(FluenceColor.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3.bold())
                                .foregroundStyle(isSelected ? FluenceColor.accent : FluenceColor.secondary.opacity(0.35))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? FluenceColor.surfaceSecondary : FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(isSelected ? FluenceColor.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding-language-\(language.id)")
                }
            }
        }
    }

    private var meaningStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Une aide dans votre langue")
                    .font(.title2.bold())
                    .foregroundStyle(FluenceColor.ink)
                Text("Fluence s'exprime en \(frenchName(for: target.id, fallback: target.name)). Choisissez votre langue de confort pour la traduction et les explications pédagogiques.")
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Langue des explications et sous-titres")
                    .font(.subheadline.bold())
                    .foregroundStyle(FluenceColor.ink)
                
                Picker("Langue de traduction", selection: Binding(get: { meaningLanguage }, set: { meaningLanguage = $0; hasChosenMeaning = true })) {
                    ForEach(MeaningLanguages.all, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(FluenceColor.accent.opacity(0.5), lineWidth: 1.5)
                }
            }
            
            // Live Preview Card
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(target.flag)
                        .font(.title3)
                    Text(target.greeting)
                        .font(.headline.bold())
                        .foregroundStyle(FluenceColor.ink)
                    Spacer()
                    Text("Original")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FluenceColor.surfaceSecondary, in: Capsule())
                        .foregroundStyle(FluenceColor.secondary)
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    Text(meaningFlag(for: meaningLanguage))
                        .font(.title3)
                    Text(MeaningLanguages.greeting(in: meaningLanguage))
                        .font(.subheadline)
                        .foregroundStyle(FluenceColor.secondary)
                    Spacer()
                    Text("Traduction")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FluenceColor.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(FluenceColor.accent)
                }
            }
            .padding(18)
            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }

    private var aiEngineStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(FluenceColor.accent)
                Text("Moteur d'Intelligence Artificielle")
                    .font(.title2.bold())
                    .foregroundStyle(FluenceColor.ink)
                Text("Fluence fonctionne immédiatement avec le Mode Auto intelligent. Vous pouvez également connecter vos propres clés API (OpenAI ChatGPT, Claude, Gemini, Groq, DeepSeek, Mistral, OpenRouter ou VPS).")
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(FluenceColor.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mode Auto Activé")
                            .font(.headline.bold())
                            .foregroundStyle(FluenceColor.ink)
                        Text("Groq · Gemini · ChatGPT · Claude · VPS")
                            .font(.caption)
                            .foregroundStyle(FluenceColor.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(FluenceColor.accent.opacity(0.3), lineWidth: 1)
                }
                
                Text("Vous pourrez ajouter vos clés API personnelles à tout moment dans Réglages > Fournisseurs d'IA.")
                    .font(.caption)
                    .foregroundStyle(FluenceColor.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.top, 6)
        }
    }

    private func advance() {
        if step == 0 {
            if !hasChosenMeaning && meaningLanguage == target.name {
                let preferredNames = Locale.preferredLanguages.map { identifier in
                    let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
                    if code == "zh" { return "Chinese (Simplified)" }
                    return LanguageRegistry.module(for: code)?.name ?? Locale(identifier: "fr").localizedString(forLanguageCode: code)?.capitalized ?? ""
                }
                meaningLanguage = preferredNames.first { MeaningLanguages.all.contains($0) && $0 != target.name }
                    ?? MeaningLanguages.all.first { $0 != target.name } ?? "Français"
            }
            move(to: 1)
        } else if step == 1 {
            move(to: 2)
        } else {
            let cleanKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanKey.isEmpty {
                try? KeychainHelper.shared.save(cleanKey, for: .groq)
                try? KeychainHelper.shared.save(cleanKey, for: .owner)
            }
            coordinator.selectLanguage(targetID)
            coordinator.selectMeaningLanguage(meaningLanguage)
            coordinator.store.updatePreferences { $0.meaningVisible = true; $0.aiConsentVersion = AIProcessingConsent.version }
            done()
        }
    }

    private func meaningFlag(for language: String) -> String {
        switch language.lowercased() {
        case "français", "french": return "🇫🇷"
        case "english", "anglais": return "🇬🇧"
        case "deutsch", "allemand", "german": return "🇩🇪"
        case "español", "espagnol", "spanish": return "🇪🇸"
        case "italiano", "italien", "italian": return "🇮🇹"
        case "português", "portugais", "portuguese": return "🇵🇹"
        case "română", "roumain", "romanian": return "🇷🇴"
        case "العربية", "arabe", "arabic": return "🇸🇦"
        case "中文", "chinois", "chinese (simplified)": return "🇨🇳"
        case "polski", "polonais", "polish": return "🇵🇱"
        case "українська", "ukrainien", "ukrainian": return "🇺🇦"
        default: return "🌐"
        }
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { step = value }
    }
}

enum AIProcessingConsent {
    static let version = 2
    static let summary = "Avec votre accord, Fluence transmet votre audio et vos phrases au moteur d'IA sélectionné (Groq, OpenAI, Gemini, Claude ou votre VPS) pour générer les conversations interactives. Vos données restent strictement privées."
    enum ConsentError: LocalizedError {
        case required
        var errorDescription: String? { "Avant d'utiliser les fonctionnalités vocales d'IA, ouvrez l'onglet Parler pour valider le consentement de traitement audio." }
    }
}

struct AIConsentView: View {
    let agree: () -> Void
    let decline: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "waveform.bubble").font(.system(size: 32, weight: .light)).foregroundStyle(FluenceColor.accent)
            Text("Avant de commencer").font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityIdentifier("ai-consent-title")
            Text(AIProcessingConsent.summary).font(.body)
            Text("Votre progression et vos données d'apprentissage restent enregistrées sur cet iPhone. Fluence ne stocke aucun enregistrement audio brut. Vous pouvez explorer vos fiches et cours librement sans accepter.")
                .font(.subheadline).foregroundStyle(FluenceColor.secondary)
            Link("Politique de confidentialité", destination: URL(string: "https://fluence.chat/privacy/")!).font(.subheadline).underline().foregroundStyle(FluenceColor.accent)
            Button("Accepter et continuer", action: agree).font(.headline).frame(maxWidth: .infinity).padding(18)
                .background(FluenceColor.accent, in: Capsule()).foregroundStyle(.white).accessibilityIdentifier("ai-consent-agree")
            Button("Pas maintenant", action: decline).font(.subheadline).frame(maxWidth: .infinity)
                .foregroundStyle(FluenceColor.secondary)
                .accessibilityIdentifier("ai-consent-decline")
        }.padding(28).foregroundStyle(FluenceColor.ink).tint(FluenceColor.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(FluenceColor.background)
            .presentationDetents([.large]).interactiveDismissDisabled()
    }
}
