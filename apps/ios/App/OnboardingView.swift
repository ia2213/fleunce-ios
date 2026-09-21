import SwiftUI
import FleunceCore

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
        _meaningLanguage = State(initialValue: coordinator.store.preferences.meaningLanguage)
        _hasChosenMeaning = State(initialValue: coordinator.store.preferences.meaningLanguage != Preferences().meaningLanguage)
        _apiKeyInput = State(initialValue: CredentialStore.read() ?? "")
    }

    private var target: LanguageModule { LanguageRegistry.module(for: targetID) ?? .norwegian }
    private var greeting: String { reduceMotion ? target.greeting : LanguageRegistry.all[greetingIndex].greeting }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button { move(to: step - 1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                            .modifier(SoftGlass())
                    }.accessibilityLabel("Back").accessibilityIdentifier("onboarding-back")
                } else { Brand() }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == step ? FleunceColor.orange : FleunceColor.peach)
                            .frame(width: index == step ? 24 : 8, height: 6)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("Step \(step + 1) of 3")
            }.padding(.horizontal, 26).padding(.top, 8).frame(height: 54)

            ScrollView {
                VStack(spacing: step == 0 ? 22 : 18) {
                    VStack(spacing: 4) {
                        FleunceOrb().frame(height: typeSize.isAccessibilitySize ? 80 : step == 0 ? 134 : 74)
                        Text(greeting)
                            .font(.system(size: typeSize.isAccessibilitySize ? 46 : step == 0 ? 60 : 48, weight: .medium, design: .rounded))
                            .tracking(-2).id(greeting)
                            .transition(.opacity)
                            .frame(height: step == 0 ? 76 : 60)
                            .accessibilityIdentifier("onboarding-greeting")
                    }.padding(.top, step == 0 ? 8 : 0).accessibilityElement(children: .ignore).accessibilityLabel("Welcome to Fleunce")

                    Group {
                        if step == 0 { languageStep }
                        else if step == 1 { meaningStep }
                        else { keyStep }
                    }.id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 14)))
                    if step == 1 && typeSize.isAccessibilitySize { consentDetails }
                }.padding(.horizontal, 26).padding(.bottom, 22)
            }.scrollIndicators(.hidden).id(step)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if step == 1 && !typeSize.isAccessibilitySize { consentDetails }
                Button(step < 2 ? "Continue" : "Start Conversation") { advance() }
                    .font(.system(.headline, design: .rounded)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 19)
                    .background(FleunceColor.orange, in: Capsule())
                    .accessibilityIdentifier("onboarding-continue")
                if !typeSize.isAccessibilitySize {
                    Text(step == 0 ? "We’ll find your pace through conversation." : (step == 1 ? "You can change both languages in Settings." : "Your key stays encrypted on this iPhone."))
                        .font(.caption).foregroundStyle(FleunceColor.secondary).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 16)
                .background(FleunceColor.cream)
        }
        .background(OnboardingBackground())
        .foregroundStyle(FleunceColor.ink).tint(FleunceColor.ink)
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
        VStack(spacing: 12) {
            Text(AIProcessingConsent.summary)
                .font(.footnote).foregroundStyle(FleunceColor.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding-ai-consent")
            Link("Privacy policy", destination: URL(string: "https://fleunce.chat/privacy/")!)
                .font(.footnote).underline().accessibilityIdentifier("onboarding-privacy-policy")
        }
    }

    private var languageStep: some View {
        VStack(spacing: 18) {
            Text("What would you\nlike to speak?")
                .font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.5)
                .multilineTextAlignment(.center).accessibilityIdentifier("onboarding-language-title")
            VStack(spacing: 10) {
                ForEach(LanguageRegistry.all) { language in
                    Button { targetID = language.id } label: {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(language.nativeName).font(.system(.headline, design: .rounded))
                                Text(language.settingsTitle).font(.caption).foregroundStyle(FleunceColor.secondary)
                            }
                            Spacer()
                            Image(systemName: targetID == language.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(targetID == language.id ? FleunceColor.orange : FleunceColor.secondary.opacity(0.4))
                        }.padding(.horizontal, 18).padding(.vertical, 13).frame(maxWidth: .infinity)
                            .background(targetID == language.id ? .white.opacity(0.92) : .white.opacity(0.52), in: RoundedRectangle(cornerRadius: 22))
                            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(targetID == language.id ? FleunceColor.orange.opacity(0.55) : .clear, lineWidth: 1.5) }
                    }.buttonStyle(.plain)
                        .accessibilityLabel(language.settingsTitle)
                        .accessibilityAddTraits(targetID == language.id ? .isSelected : [])
                        .accessibilityIdentifier("onboarding-language-\(language.id)")
                }
            }
        }
    }

    private var meaningStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text("A little help,\nin your language.")
                    .font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.5)
                Text("Fleunce speaks \(target.name). Choose the language you read most easily for meanings.")
                    .font(.subheadline).foregroundStyle(FleunceColor.secondary)
            }.multilineTextAlignment(.center).accessibilityIdentifier("onboarding-meaning-title")
            Picker("Subtitle language", selection: Binding(get: { meaningLanguage }, set: { meaningLanguage = $0; hasChosenMeaning = true })) {
                ForEach(MeaningLanguages.all, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.menu).font(.system(.headline, design: .rounded))
                .padding(20).frame(maxWidth: .infinity)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("onboarding-meaning-picker")
            VStack(spacing: 8) {
                Text(target.greeting).font(.system(.title2, design: .rounded, weight: .medium))
                if target.id == "zh", let reading = MandarinPinyin.reading(target.greeting) {
                    Text(reading).font(.callout).foregroundStyle(FleunceColor.secondary)
                }
                Text(MeaningLanguages.greeting(in: meaningLanguage)).font(.body).foregroundStyle(FleunceColor.secondary)
                    .accessibilityIdentifier("onboarding-meaning-example")
                Text("Turn meanings on whenever you need a hand.").font(.caption).foregroundStyle(FleunceColor.secondary).padding(.top, 8)
            }.multilineTextAlignment(.center).padding(.vertical, 12)
        }
    }

    private var keyStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "key.fill").font(.system(size: 36, weight: .light)).foregroundStyle(FleunceColor.orange)
                Text("Groq API Key")
                    .font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-0.5)
                Text("Enter your free Groq API key (gsk_...). It is saved securely on your iPhone's Keychain.")
                    .font(.subheadline).foregroundStyle(FleunceColor.secondary).multilineTextAlignment(.center)
            }
            VStack(spacing: 12) {
                SecureField("Groq API key (gsk_...)", text: $apiKeyInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(16)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                
                Link("Get a free API key at console.groq.com", destination: URL(string: "https://console.groq.com/keys")!)
                    .font(.caption).underline()
            }
            .padding(.top, 10)
        }
    }

    private func advance() {
        if step == 0 {
            if !hasChosenMeaning && meaningLanguage == target.name {
                let preferredNames = Locale.preferredLanguages.map { identifier in
                    let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
                    if code == "zh" { return "Chinese (Simplified)" }
                    return LanguageRegistry.module(for: code)?.name ?? Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized ?? ""
                }
                meaningLanguage = preferredNames.first { MeaningLanguages.all.contains($0) && $0 != target.name }
                    ?? MeaningLanguages.all.first { $0 != target.name } ?? "English"
            }
            move(to: 1)
        } else if step == 1 {
            move(to: 2)
        } else {
            let cleanKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanKey.isEmpty {
                try? CredentialStore.save(cleanKey)
            }
            coordinator.selectLanguage(targetID)
            coordinator.selectMeaningLanguage(meaningLanguage)
            coordinator.store.updatePreferences { $0.meaningVisible = true; $0.aiConsentVersion = AIProcessingConsent.version }
            done()
        }
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { step = value }
    }
}

enum AIProcessingConsent {
    static let version = 1
    static let summary = "With your permission, Fleunce sends audio and selected text to Groq (Llama 3.1 & Whisper Turbo) to provide conversations and meanings. Provider retention rules apply."
    enum ConsentError: LocalizedError {
        case required
        var errorDescription: String? { "Before using AI features, open Talk and tap the microphone to review how Groq processes your audio and text." }
    }
}

struct AIConsentView: View {
    let agree: () -> Void
    let decline: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "waveform.bubble").font(.system(size: 32, weight: .light)).foregroundStyle(FleunceColor.orange)
            Text("Before we talk.").font(.system(.title, design: .rounded, weight: .semibold))
                .accessibilityIdentifier("ai-consent-title")
            Text(AIProcessingConsent.summary).font(.body)
            Text("Your learning record is stored on this iPhone. Fleunce does not save raw audio. You can keep browsing your saved words and conversations without agreeing.")
                .font(.subheadline).foregroundStyle(FleunceColor.secondary)
            Link("Privacy policy", destination: URL(string: "https://fleunce.chat/privacy/")!).font(.subheadline).underline()
            Button("Agree and continue", action: agree).font(.headline).frame(maxWidth: .infinity).padding(18)
                .background(FleunceColor.orange, in: Capsule()).accessibilityIdentifier("ai-consent-agree")
            Button("Not now", action: decline).font(.subheadline).frame(maxWidth: .infinity)
                .accessibilityIdentifier("ai-consent-decline")
        }.padding(28).foregroundStyle(FleunceColor.ink).tint(FleunceColor.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(FleunceColor.cream)
            .presentationDetents([.large]).interactiveDismissDisabled()
    }
}

private struct OnboardingBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 0.14
            if #available(iOS 18.0, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + sin(phase) * 0.12), Float(0.45 + cos(phase) * 0.1)], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ], colors: [FleunceColor.cream, FleunceColor.butter.opacity(0.7), FleunceColor.cream,
                            FleunceColor.cream, FleunceColor.peach.opacity(0.75), FleunceColor.lilac.opacity(0.45),
                            FleunceColor.cream, FleunceColor.cream, FleunceColor.cream])
            } else {
                LinearGradient(colors: [FleunceColor.cream, FleunceColor.peach.opacity(0.75), FleunceColor.cream], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.background(FleunceColor.cream).ignoresSafeArea().accessibilityHidden(true)
    }
}
