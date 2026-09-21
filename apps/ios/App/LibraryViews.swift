import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import FleunceCore

struct ThemesView: View {
    let coordinator: ConversationCoordinator
    let choose: (ConversationTheme?) -> Void
    @State private var search = ""
    @State private var category = "All"
    @State private var current = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var themes: [ConversationTheme] {
        coordinator.language.themes.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search)) }
    }
    private var categories: [String] { coordinator.language.themes.map(\.category).reduce(into: ["All"]) { if !$0.contains($1) { $0.append($1) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "A place to begin", title: "What’s on\nyour mind?", subtitle: "Same friend. Somewhere new.")
                Button { choose(nil) } label: {
                    HStack { Image(systemName: "waveform"); Text("Just talk"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 26))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c) { category = c }.font(.caption).padding(.horizontal, 15).padding(.vertical, 11)
                                .background(category == c ? FleunceColor.peach : .white.opacity(0.65), in: Capsule())
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : (horizontalSizeClass == .regular ? 220 : 150)), spacing: 16)], spacing: 16) {
                    ForEach(themes) { theme in
                        Button { if theme.id == "today" { current = true } else { choose(theme) } } label: {
                            VStack(alignment: .leading, spacing: 28) {
                                Image(systemName: theme.symbol).font(.system(size: 28, weight: .light)).foregroundStyle(FleunceColor.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(theme.title).font(.system(.headline, design: .rounded))
                                    Text(theme.subtitle).font(.caption).foregroundStyle(FleunceColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(19)
                                .background(FleunceColor.panels[theme.colorIndex], in: RoundedRectangle(cornerRadius: 27))
                        }.buttonStyle(.plain)
                    }
                }
                if themes.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .topLeading)
        }.foregroundStyle(FleunceColor.ink)
            .searchable(text: $search, prompt: "Find a conversation")
            .sheet(isPresented: $current) { CurrentTopicView(coordinator: coordinator) { choose(coordinator.selectedTheme) } }
    }
}

struct CurrentTopicView: View {
    let coordinator: ConversationCoordinator
    let selected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var brief: TopicBrief?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "The world today", title: "A fresh conversation.", subtitle: "What would you like to talk about?")
                    TextField(coordinator.language.topicPlaceholder, text: $query, axis: .vertical).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Button { find() } label: {
                        HStack { Text(loading ? "Finding something interesting…" : "Find a topic"); Spacer(); if loading { ProgressView() } else { Image(systemName: "sparkle.magnifyingglass") } }.padding(18).background(FleunceColor.peach, in: Capsule())
                    }.disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error { Text(error).font(.footnote).foregroundStyle(FleunceColor.secondary) }
                    if let brief {
                        Text(.init(brief.text)).font(.body).textSelection(.enabled)
                        SourcesView(sources: brief.sources, date: brief.retrievedAt)
                        Button("Talk about this", systemImage: "waveform") { coordinator.discuss(brief); selected(); dismiss() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).background(FleunceColor.orange, in: Capsule())
                    }
                    Text("Search uses your Gemini API account. Sources stay attached to the topic.").font(.footnote).foregroundStyle(FleunceColor.secondary)
                }.padding(26)
            }.background(FleunceColor.cream).foregroundStyle(FleunceColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    private func find() {
        loading = true; error = nil
        Task { do { brief = try await coordinator.currentTopic(query) } catch { self.error = error.localizedDescription }; loading = false }
    }
}

struct WordsView: View {
    let coordinator: ConversationCoordinator
    @State private var search = ""
    @State private var selected: WordState?
    @State private var sessions = false
    private var learner: LearnerState { coordinator.store.learner }
    private var words: [WordState] { learner.words.filter { search.isEmpty || $0.lemma.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Little by little · \(coordinator.language.name)", title: "Your words.", subtitle: "Familiar words, ready for another conversation.")
                if words.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "leaf").font(.system(size: 34, weight: .light))
                        Text(search.isEmpty ? "They’ll grow from here." : "No matching words yet.").font(.system(.title2, design: .rounded, weight: .medium))
                        Text(search.isEmpty ? "As we talk, useful words and phrases find a home here. Their strength grows when you recall them over time." : "Try another \(coordinator.language.name) word or English meaning.").font(.subheadline).foregroundStyle(FleunceColor.secondary)
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(FleunceColor.sage, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(words) { word in
                            Button { selected = word } label: {
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(word.lemma).font(.system(.title2, design: .rounded, weight: .medium))
                                        Text(word.meaning).font(.subheadline).foregroundStyle(FleunceColor.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    VStack(alignment: .trailing, spacing: 8) { RecallBars(count: word.bars); Text(word.label).font(.caption2).foregroundStyle(FleunceColor.secondary) }
                                }.padding(.vertical, 20)
                            }.buttonStyle(.plain)
                            Divider().overlay(FleunceColor.peach)
                        }
                    }
                }
                HStack { Text("1 · Fragile"); Spacer(); Text("2 · Growing"); Spacer(); Text("3 · Steady") }.font(.caption).foregroundStyle(FleunceColor.secondary)
                Text("The bars estimate spoken recall, not permanent mastery. Using a word with visible meanings counts as supported practice.").font(.footnote).foregroundStyle(FleunceColor.secondary)
                if !learner.capabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Finding your voice").font(.system(.title3, design: .rounded, weight: .semibold))
                        ForEach(learner.capabilities, id: \.self) { Text($0).font(.subheadline) }
                        Text("Observed across conversations. These are provisional, not formal level certificates.").font(.footnote).foregroundStyle(FleunceColor.secondary)
                    }.padding(22).background(FleunceColor.butter, in: RoundedRectangle(cornerRadius: 24))
                }
                Button("Past conversations", systemImage: "clock.arrow.circlepath") { sessions = true }.font(.subheadline).padding(.vertical, 8)
            }.padding(26).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .topLeading)
        }.foregroundStyle(FleunceColor.ink).searchable(text: $search, prompt: "Find a word")
            .sheet(item: $selected) { word in WordDetailView(word: word, store: coordinator.store) }
            .sheet(isPresented: $sessions) { SessionHistoryView(store: coordinator.store) }
    }
}

struct WordDetailView: View {
    let word: WordState
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(word.lemma).font(.system(.largeTitle, design: .rounded, weight: .medium))
                if store.language.id == "zh" { PinyinHelp(text: word.lemma) }
                Text(word.meaning).font(.title3).foregroundStyle(FleunceColor.secondary)
                HStack { RecallBars(count: word.bars); Text(word.label).font(.subheadline) }
                Text(word.explanation).font(.body)
                Text("“\(word.example)”").font(.system(.title3, design: .rounded)).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(FleunceColor.peach, in: RoundedRectangle(cornerRadius: 22))
                Text("\(word.independentCount) independent uses · Last seen \(word.lastSeen.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(FleunceColor.secondary)
                Button("Remove from my words", role: .destructive) { store.hideWord(word.id); dismiss() }.font(.footnote)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(FleunceColor.cream).foregroundStyle(FleunceColor.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct SourcesView: View {
    var sources: [SourceLink]
    var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources · \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(FleunceColor.secondary)
            ForEach(sources) { source in if let url = source.safeURL { Link(destination: url) { Label(source.title, systemImage: "arrow.up.right").font(.subheadline) } } }
        }
    }
}

struct TranscriptView: View {
    let session: SessionRecord?
    var meaningLanguage = "English"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let session {
                        ForEach(session.passages) { passage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(passage.speaker == .assistant ? "FLEUNCE" : "YOU").font(.caption).tracking(1).foregroundStyle(FleunceColor.secondary)
                                Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                                if session.languageID == "zh" { PinyinHelp(text: passage.text) }
                                if let translation = session.translations[MeaningRequest.cacheKey(revisionKey: passage.revisionKey, language: meaningLanguage)] ?? session.translations[passage.revisionKey] {
                                    Text(translation).font(.subheadline).foregroundStyle(FleunceColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(session.topics) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                        if session.fragments.isEmpty && session.topics.isEmpty { Text("Your conversation will appear here.").foregroundStyle(FleunceColor.secondary) }
                    } else { Text("Start a conversation and your words will appear here.") }
                }.padding(26)
            }.background(FleunceColor.cream).foregroundStyle(FleunceColor.ink)
                .navigationTitle("Our conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SessionHistoryView: View {
    let store: LearningStore
    @State private var selected: SessionRecord?
    @State private var deleting: SessionRecord?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.learningSessions.isEmpty { Text("Your \(store.language.name) conversations will appear here.").foregroundStyle(FleunceColor.secondary) }
                ForEach(store.learningSessions) { session in
                    Button { selected = session } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(FleunceColor.secondary)
                        }.padding(.vertical, 8)
                    }.swipeActions { Button("Delete", role: .destructive) { deleting = session }.disabled(session.endedAt == nil) }
                }
            }.scrollContentBackground(.hidden).background(FleunceColor.cream)
                .navigationTitle("Past conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(item: $selected) { session in EditableTranscriptView(sessionID: session.id, store: store) }
            .confirmationDialog("Delete this conversation and its learning evidence?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete conversation", role: .destructive) { if let deleting { store.deleteSession(deleting.id) }; deleting = nil }
            }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EditableTranscriptView: View {
    let sessionID: UUID
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var editedText = ""
    private var session: SessionRecord? { store.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(session?.passages ?? []) { passage in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(passage.speaker == .user ? "YOU" : "FLEUNCE").font(.caption).tracking(1)
                                Spacer()
                                if passage.speaker == .user && session?.endedAt != nil {
                                    Button("Edit") { editedText = passage.text; editingID = passage.id }.font(.caption)
                                }
                            }.foregroundStyle(FleunceColor.secondary)
                            Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                            if session?.languageID == "zh" { PinyinHelp(text: passage.text) }
                        }
                    }
                    ForEach(session?.topics ?? []) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26)
            }.background(FleunceColor.cream).foregroundStyle(FleunceColor.ink)
                .navigationTitle("Our conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("What you said", text: $editedText, axis: .vertical).lineLimit(4...10).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Text("Correct a misheard phrase. Learning evidence from the old wording will be removed; the original remains in your backup history.").font(.footnote).foregroundStyle(FleunceColor.secondary)
                    Spacer()
                }.padding(24).background(FleunceColor.cream).navigationTitle("What you said").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingID = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") { if let id = editingID { store.correctPassage(sessionID: sessionID, passageID: id, text: editedText) }; editingID = nil } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
}

struct SettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasKey = CredentialStore.hasKey
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: BackupDocument?
    @State private var deleting = false
    @State private var notices = false
    @State private var showingAPIKey = false
    private var store: LearningStore { coordinator.store }
    private var totalVoiceSeconds: Double { store.sessions.reduce(0) { $0 + $1.voiceSeconds } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LearningLanguagePicker(coordinator: coordinator)
                    Toggle("Meaning subtitles", isOn: Binding(get: { store.preferences.meaningVisible }, set: { value in
                        if value != store.preferences.meaningVisible { coordinator.toggleMeaning() }
                    }))
                    Picker("Meaning language", selection: Binding(get: { store.preferences.meaningLanguage }, set: { coordinator.selectMeaningLanguage($0) })) {
                        ForEach(MeaningLanguages.all, id: \.self) { Text($0) }
                    }
                    Picker("Correction Level / Niveau", selection: Binding(get: { store.preferences.correctionLevel }, set: { val in store.updatePreferences { $0.correctionLevel = val } })) {
                        Text("Fort / Strict (Corrige tout)").tag("high")
                        Text("Moyen / Équilibré (Naturel)").tag("medium")
                        Text("Faible / Fluide (Erreurs clés)").tag("low")
                    }
                    TextField("A few things you enjoy", text: Binding(get: { store.preferences.interests }, set: { value in store.updatePreferences { $0.interests = String(value.prefix(500)) } }), axis: .vertical)
                } header: { Text("Just your pace") } footer: { Text(coordinator.isRunning ? "End this conversation to switch languages. Each language keeps its own words and progress." : "Each language keeps its own words and progress. Fleunce finds your pace through conversation.") }
                if ManagedAccountConfiguration.load() != nil {
                    Section {
                        NavigationLink { ManagedAccountView() } label: {
                            Label("Account", systemImage: "person.crop.circle")
                        }.disabled(coordinator.isRunning).accessibilityIdentifier("managed-account-settings")
                    }
                }
                Section {
                    Picker("AI Provider Mode", selection: Binding(get: { store.preferences.providerID }, set: { val in store.updatePreferences { $0.providerID = val } })) {
                        Text("Auto-Switch (Groq → Gemini → VPS)").tag("auto")
                        Text("Personal Hermes VPS Agent").tag("hermes_vps")
                        Text("Google Gemini API").tag("google")
                        Text("Groq API Cloud").tag("groq")
                    }
                } header: { Text("Moteur IA Principal") } footer: {
                    Text("En mode Auto, l'application bascule automatiquement entre Groq, Google Gemini et votre VPS personnel si un service est indisponible.")
                }

                Section {
                    TextField("VPS Endpoint URL", text: Binding(get: { store.preferences.vpsEndpoint }, set: { val in store.updatePreferences { $0.vpsEndpoint = val } }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("VPS Auth Token (Facultatif)", text: Binding(get: { store.preferences.vpsAPIKey }, set: { val in store.updatePreferences { $0.vpsAPIKey = val } }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("VPS Model", selection: Binding(get: { store.preferences.vpsModel }, set: { val in store.updatePreferences { $0.vpsModel = val } })) {
                        Text("Hermes Auto (OmniRoute)").tag("auto/best-coding")
                        Text("Nous Hermes 3 (8B Local)").tag("NousResearch/Hermes-3-Llama-3.1-8B")
                        Text("Hermes Vocal VPS").tag("hermes-agent-vps")
                    }
                } header: { Text("🏛️ Personal Hermes VPS Agent") } footer: {
                    Text("Connecté à votre serveur Oracle VPS personnel.")
                }

                Section {
                    SecureField("Google API Key (AIzaSy...)", text: Binding(get: { store.preferences.googleAPIKey }, set: { val in store.updatePreferences { $0.googleAPIKey = val } }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Gemini Model", selection: Binding(get: { store.preferences.geminiModel }, set: { val in store.updatePreferences { $0.geminiModel = val } })) {
                        Text("Gemini 2.0 Flash (Recommandé)").tag("gemini-2.0-flash")
                        Text("Gemini 2.0 Flash Lite").tag("gemini-2.0-flash-lite")
                        Text("Gemini 1.5 Flash").tag("gemini-1.5-flash")
                        Text("Gemini 1.5 Pro").tag("gemini-1.5-pro")
                    }
                    Link("Obtenir une clé Gemini gratuite", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                } header: { Text("🌐 Google Gemini Engine") }

                Section {
                    Picker("Groq Model", selection: Binding(get: { store.preferences.groqModel }, set: { val in store.updatePreferences { $0.groqModel = val } })) {
                        Text("GPT-OSS 120B (Recommandé)").tag("openai/gpt-oss-120b")
                        Text("GPT-OSS 20B").tag("openai/gpt-oss-20b")
                        Text("Qwen 3.8 27B").tag("qwen/qwen3.8-27b")
                        Text("Llama 3.3 70B Versatile").tag("llama-3.3-70b-versatile")
                        Text("Llama 3.1 8B Instant").tag("llama-3.1-8b-instant")
                    }
                    DisclosureGroup(isExpanded: $showingAPIKey) {
                        if hasKey { Label("Clé Groq sauvegardée sur cet iPhone", systemImage: "checkmark.shield") }
                        SecureField(hasKey ? "Remplacer la clé Groq (gsk_...)" : "Clé Groq API (gsk_...)", text: $key)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive().accessibilityIdentifier("api-key")
                        Button(hasKey ? "Enregistrer la nouvelle clé" : "Enregistrer la clé") {
                            do { try CredentialStore.save(key); key = ""; hasKey = true; message = "Enregistré avec succès." }
                            catch { message = error.localizedDescription }
                        }.disabled(key.isEmpty || coordinator.isRunning)
                        Link("Obtenir une clé Groq gratuite", destination: URL(string: "https://console.groq.com/keys")!)
                        if hasKey {
                            Button("Supprimer la clé", role: .destructive) {
                                do { try CredentialStore.delete(); hasKey = false; message = "Clé supprimée." }
                                catch { message = error.localizedDescription }
                            }.disabled(coordinator.isRunning)
                        }
                    } label: { Label("Clé API Groq", systemImage: "key").accessibilityIdentifier("advanced-api-key") }
                } header: { Text("⚡ Groq Engine Cloud") } footer: {
                    Text("Select your preferred model on Groq. STT uses Groq Whisper Turbo and TTS uses your iPhone's native iOS voice.")
                }
                Section {
                    Picker("Moteur Vocal / Voice Engine", selection: Binding(get: { store.preferences.ttsEngine }, set: { val in store.updatePreferences { $0.ttsEngine = val } })) {
                        Text("Voix iOS Native (AVSpeechSynthesizer)").tag("ios")
                        Text("Voix Google Gemini (IA Audio API)").tag("gemini")
                    }
                    let availableVoices = AVSpeechSynthesisVoice.speechVoices().filter {
                        $0.language.lowercased().hasPrefix(String(store.language.locale.prefix(2)).lowercased())
                    }
                    Picker("Voice Accent / Voix", selection: Binding(get: { store.preferences.selectedVoiceIdentifier }, set: { val in store.updatePreferences { $0.selectedVoiceIdentifier = val } })) {
                        Text("Automatic (Best Premium Voice)").tag("")
                        ForEach(availableVoices, id: \.identifier) { v in
                            let qualityStr = v.quality == .premium ? " (Premium)" : (v.quality == .enhanced ? " (Enhanced)" : "")
                            Text("\(v.name) · \(v.language)\(qualityStr)").tag(v.identifier)
                        }
                    }
                    Button("Play Voice Sample / Écouter l'extrait") {
                        let text = store.language.greeting
                        let synth = AVSpeechSynthesizer()
                        let utterance = AVSpeechUtterance(string: text)
                        if !store.preferences.selectedVoiceIdentifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: store.preferences.selectedVoiceIdentifier) {
                            utterance.voice = v
                        } else {
                            utterance.voice = AVSpeechSynthesisVoice(language: store.language.locale)
                        }
                        utterance.rate = store.preferences.speechRate
                        synth.speak(utterance)
                    }
                } header: { Text("Voice & Accent Selection") } footer: {
                    Text("Select a specific voice accent for \(store.language.name). Tap Play Voice Sample to preview.")
                }
                Section {
                    Picker("Conversation limit", selection: Binding(get: { store.preferences.sessionMinutes }, set: { value in store.updatePreferences { $0.sessionMinutes = value } })) {
                        Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("60 minutes").tag(60)
                    }
                    Picker("Speech Speed / Vitesse", selection: Binding(get: { store.preferences.speechRate }, set: { val in store.updatePreferences { $0.speechRate = val } })) {
                        Text("Slow / Lente (0.8x)").tag(Float(0.40))
                        Text("Normal / Normale (1.0x)").tag(Float(0.50))
                        Text("Fast / Rapide (1.2x)").tag(Float(0.60))
                    }
                    LabeledContent("Recorded voice time", value: "\(Int(totalVoiceSeconds / 60)) min \(Int(totalVoiceSeconds) % 60) sec")
                    LabeledContent("Voice estimate", value: String(format: "$%.2f USD", totalVoiceSeconds / 60 * 0.05))
                    LabeledContent("Search calls recorded", value: "\(store.sessions.reduce(0) { $0 + $1.searchCalls })")
                    Link("Groq Console usage", destination: URL(string: "https://console.groq.com/")!)
                } header: { Text("Keep it comfortable") } footer: {
                    Text("Translation, teaching and search cost extra. Your Groq dashboard is authoritative. The time limit is local, not a billing cap.")
                }
                Section {
                    Button("Export learning backup", systemImage: "square.and.arrow.up") {
                        do { backup = BackupDocument(data: try store.exportData()); exporting = true } catch { message = error.localizedDescription }
                    }
                    Button("Import learning backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(coordinator.isRunning)
                    Button("Delete all conversations and learning", role: .destructive) { deleting = true }.disabled(coordinator.isRunning)
                } header: { Text("Your words belong to you") } footer: {
                    Text("Backups include transcripts and learning evidence, never your API key. Import adds conversations with new IDs. Existing conversations stay unchanged. There is no cloud sync.")
                }
                Section {
                    Link("Privacy policy", destination: URL(string: "https://fleunce.chat/privacy/")!)
                        .accessibilityIdentifier("settings-privacy-policy")
                    Link("Terms of use", destination: URL(string: "https://fleunce.chat/terms/")!)
                        .accessibilityIdentifier("settings-terms")
                    Link("Contact support", destination: URL(string: "https://fleunce.chat/support/")!)
                        .accessibilityIdentifier("settings-support")
                } header: { Text("Help and privacy") }
                Section {
                    Text("Fleunce 0.1 · Personal build").font(.footnote)
                    Text("Teacher: Groq Llama 3.1 8B · STT: Groq Whisper Turbo").font(.footnote)
                    Link("Groq data controls", destination: URL(string: "https://groq.com/privacy/")!)
                    Text("Audio and selected text go to Groq while you practise. Raw audio is not saved by Fleunce.").font(.footnote)
                    Button("Open-source notices") { notices = true }
                }
            }.scrollContentBackground(.hidden).background(FleunceColor.cream).tint(FleunceColor.secondary)
                .navigationTitle("Make yourself comfortable").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { key = ""; dismiss() } } }
        }
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Fleunce-learning-backup") { result in if case .failure(let error) = result { message = error.localizedDescription } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Archive.readImportData(from: url)); message = "Your backup has been imported."
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Delete all learning data on this phone?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete all learning data", role: .destructive) { coordinator.deleteLearningData() }
        } message: { Text("This removes conversations, vocabulary and progress. Export a backup first if you want to keep them. Your API key and preferences remain.") }
        .sheet(isPresented: $notices) {
            NavigationStack {
                ScrollView { Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Notices unavailable.").font(.footnote).padding(24).textSelection(.enabled) }
                    .navigationTitle("Open-source notices").navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

struct LearningLanguagePicker: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        Picker("Learning language", selection: Binding(get: { coordinator.language.id }, set: { coordinator.selectLanguage($0) })) {
            ForEach(LanguageRegistry.all) { language in Text(language.settingsTitle).tag(language.id) }
        }
        .pickerStyle(.menu)
        .disabled(coordinator.isRunning)
        .accessibilityIdentifier("learning-language-picker")
    }
}
