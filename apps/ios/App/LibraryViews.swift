import SwiftUI
import StoreKit
import AVFoundation
import UniformTypeIdentifiers
import WebKit
import FluenceCore

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
                PageHeading(eyebrow: "Un point de départ", title: "Qu’avez-vous\nen tête ?", subtitle: "Le même compagnon. Un nouveau lieu.")
                Button { choose(nil) } label: {
                    HStack { Image(systemName: "waveform"); Text("Discuter librement"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 26))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(c == "All" ? "Tout" : c) { category = c }.font(.caption).padding(.horizontal, 15).padding(.vertical, 11)
                                .background(category == c ? FluenceColor.peach : .white.opacity(0.65), in: Capsule())
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : (horizontalSizeClass == .regular ? 220 : 150)), spacing: 16)], spacing: 16) {
                    ForEach(themes) { theme in
                        Button { if theme.id == "today" { current = true } else { choose(theme) } } label: {
                            VStack(alignment: .leading, spacing: 28) {
                                Image(systemName: theme.symbol).font(.system(size: 28, weight: .light)).foregroundStyle(FluenceColor.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(theme.title).font(.system(.headline, design: .rounded))
                                    Text(theme.subtitle).font(.caption).foregroundStyle(FluenceColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(19)
                                .background(FluenceColor.panels[theme.colorIndex], in: RoundedRectangle(cornerRadius: 27))
                        }.buttonStyle(.plain)
                    }
                }
                if themes.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .topLeading)
        }.foregroundStyle(FluenceColor.ink)
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
                    PageHeading(eyebrow: "Le monde actuel", title: "Un nouveau sujet.", subtitle: "De quoi aimeriez-vous parler ?")
                    TextField(coordinator.language.topicPlaceholder, text: $query, axis: .vertical).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Button { find() } label: {
                        HStack { Text(loading ? "Recherche en cours…" : "Trouver un sujet"); Spacer(); if loading { ProgressView() } else { Image(systemName: "sparkle.magnifyingglass") } }.padding(18).background(FluenceColor.peach, in: Capsule())
                    }.disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error { Text(error).font(.footnote).foregroundStyle(FluenceColor.secondary) }
                    if let brief {
                        Text(.init(brief.text)).font(.body).textSelection(.enabled)
                        SourcesView(sources: brief.sources, date: brief.retrievedAt)
                        Button("Parler de ça", systemImage: "waveform") { coordinator.discuss(brief); selected(); dismiss() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).background(FluenceColor.orange, in: Capsule())
                    }
                    Text("La recherche utilise votre compte Gemini API. Les sources restent liées à la discussion.").font(.footnote).foregroundStyle(FluenceColor.secondary)
                }.padding(26)
            }.background(FluenceColor.cream).foregroundStyle(FluenceColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
    private func find() {
        loading = true; error = nil
        Task { do { brief = try await coordinator.currentTopic(query) } catch { self.error = error.localizedDescription }; loading = false }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - In-App Google Drive Web View Component
struct GoogleDriveWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var currentURLString: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var webViewRef: WKWebView?
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Desktop Safari User-Agent prevents iOS Universal Links from handing off to the native Drive app
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        
        context.coordinator.webView = webView
        DispatchQueue.main.async {
            self.webViewRef = webView
        }
        
        var req = URLRequest(url: initialURL)
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        webView.load(req)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: GoogleDriveWebView
        weak var webView: WKWebView?
        
        init(_ parent: GoogleDriveWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            
            let scheme = url.scheme?.lowercased() ?? ""
            // Block all custom URL schemes (googledrive://, etc.) to force staying inside the in-app browser
            if scheme != "http" && scheme != "https" && scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            
            // Allow all web requests inside WKWebView
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                if let url = webView.url {
                    self.parent.currentURLString = url.absoluteString
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}

// MARK: - Google Drive Direct Browser Sheet
struct GoogleDriveBrowserSheet: View {
    let coordinator: ConversationCoordinator
    @ObservedObject private var service = GoogleDriveDirectService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var mode = 0 // 0: Partager via App, 1: Lien Drive, 2: Coller Texte, 3: Drive Web
    @State private var currentURLString = "https://drive.google.com"
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var webViewRef: WKWebView?
    
    @State private var driveLink = ""
    @State private var rawText = ""
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var isDownloading = false
    @State private var showNativeFilePicker = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                FluenceColor.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Mode Picker
                    Picker("Mode", selection: $mode) {
                        Text("📤 Partager App").tag(0)
                        Text("🔗 Lien").tag(1)
                        Text("📋 Coller").tag(2)
                        Text("🌐 Web").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(FluenceColor.surface)
                    
                    if mode == 0 {
                        // MODE 0: SHARE FROM GOOGLE DRIVE APP DIRECTLY
                        ScrollView {
                            VStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "square.and.arrow.up.circle.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(.blue)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Partage direct depuis Google Drive")
                                                .font(.system(.headline, design: .rounded, weight: .bold))
                                                .foregroundStyle(FluenceColor.ink)
                                            Text("Sans passer par les Fichiers iCloud")
                                                .font(.caption)
                                                .foregroundStyle(FluenceColor.secondary)
                                        }
                                    }
                                    
                                    Divider().overlay(FluenceColor.surfaceSecondary)
                                    
                                    VStack(alignment: .leading, spacing: 12) {
                                        stepRow(number: "1", text: "Pour un fichier ou plusieurs : Ouvrez le dossier dans Drive, restez appuyé pour sélectionner tous les fichiers, touchez « ••• » ➔ « Envoyer une copie » ➔ « Fluence ».")
                                        stepRow(number: "2", text: "Pour un dossier complet : Touchez « ••• » sur le dossier dans Drive ➔ « Copier le lien » ➔ Collez-le dans l'onglet « 🔗 Lien ».")
                                    }
                                    
                                    Button {
                                        if let url = URL(string: "googledrive://"), UIApplication.shared.canOpenURL(url) {
                                            UIApplication.shared.open(url)
                                        } else if let webURL = URL(string: "https://drive.google.com") {
                                            UIApplication.shared.open(webURL)
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.up.forward.app.fill")
                                            Text("Ouvrir l'application Google Drive")
                                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        }
                                        .foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 6)
                                }
                                .padding(20)
                                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                            }
                        }
                    } else if mode == 1 {
                        // MODE 1: LINK IMPORT
                        ScrollView {
                            VStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "link.badge.plus")
                                            .foregroundStyle(FluenceColor.emerald)
                                        Text("Coller un lien Google Drive")
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(FluenceColor.ink)
                                    }
                                    
                                    Text("Copiez le lien de partage d'un fichier dans Google Drive (« Copier le lien ») et collez-le ici :")
                                        .font(.caption)
                                        .foregroundStyle(FluenceColor.secondary)
                                    
                                    HStack(spacing: 8) {
                                        TextField("https://drive.google.com/file/d/...", text: $driveLink)
                                            .font(.subheadline)
                                            .padding(14)
                                            .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)
                                        
                                        Button {
                                            if let clip = UIPasteboard.general.string, clip.contains("drive.google.com") {
                                                driveLink = clip
                                            }
                                        } label: {
                                            Image(systemName: "doc.on.clipboard")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(FluenceColor.ink)
                                                .padding(14)
                                                .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Button {
                                        importFromLink()
                                    } label: {
                                        HStack(spacing: 8) {
                                            if isDownloading {
                                                ProgressView().tint(Color.white)
                                            } else {
                                                Image(systemName: "arrow.down.circle.fill")
                                            }
                                            Text(isDownloading ? "Téléchargement en cours…" : "Télécharger & Importer")
                                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                        }
                                        .foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(driveLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FluenceColor.secondary.opacity(0.3) : .blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(driveLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDownloading)
                                }
                                .padding(18)
                                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                            }
                        }
                    } else if mode == 2 {
                        // MODE 2: RAW TEXT / VOCABULARY PASTE
                        ScrollView {
                            VStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundStyle(.blue)
                                        Text("Coller du Texte ou Liste de Vocabulaire")
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(FluenceColor.ink)
                                    }
                                    
                                    Text("Copiez du texte depuis Google Docs, un PDF ou un tableur et collez-le ci-dessous. Les paires de mots et expressions seront détectées automatiquement.")
                                        .font(.caption)
                                        .foregroundStyle(FluenceColor.secondary)
                                    
                                    TextEditor(text: $rawText)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .frame(minHeight: 180)
                                        .padding(10)
                                        .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    
                                    HStack(spacing: 10) {
                                        Button {
                                            if let clip = UIPasteboard.general.string {
                                                rawText = clip
                                            }
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "doc.on.clipboard")
                                                Text("Coller")
                                            }
                                            .font(.system(.caption, design: .rounded, weight: .bold))
                                            .foregroundStyle(FluenceColor.ink)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Spacer()
                                        
                                        Button {
                                            importRawTextContent()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Ajouter au Vocabulaire")
                                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                            }
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FluenceColor.secondary.opacity(0.3) : .blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                .padding(18)
                                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                            }
                        }
                    } else {
                        // MODE 3: LIVE GOOGLE DRIVE WEB PORTAL
                        VStack(spacing: 0) {
                            HStack(spacing: 16) {
                                Button {
                                    webViewRef?.goBack()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(canGoBack ? .blue : FluenceColor.secondary.opacity(0.4))
                                }
                                .disabled(!canGoBack)
                                
                                Button {
                                    webViewRef?.goForward()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(canGoForward ? .blue : FluenceColor.secondary.opacity(0.4))
                                }
                                .disabled(!canGoForward)
                                
                                Button {
                                    webViewRef?.reload()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(FluenceColor.ink)
                                }
                                
                                Spacer()
                                
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                
                                Text("drive.google.com")
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(FluenceColor.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(FluenceColor.surfaceSecondary)
                            
                            GoogleDriveWebView(
                                initialURL: URL(string: "https://accounts.google.com/ServiceLogin?service=wise&passive=true&continue=https%3A%2F%2Fdrive.google.com%2Fdrive%2Fmy-drive")!,
                                currentURLString: $currentURLString,
                                canGoBack: $canGoBack,
                                canGoForward: $canGoForward,
                                isLoading: $isLoading,
                                webViewRef: $webViewRef
                            )
                            
                            VStack(spacing: 6) {
                                Button {
                                    importCurrentWebDocument()
                                } label: {
                                    HStack(spacing: 8) {
                                        if isDownloading {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                                .font(.system(size: 18, weight: .bold))
                                        }
                                        Text(isDownloading ? "Importation en cours…" : "📥 Importer ce document dans Fluence")
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                    }
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .disabled(isDownloading)
                            }
                            .padding(12)
                            .background(FluenceColor.surface)
                        }
                    }
                }
            }
            .navigationTitle("Google Drive & Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                if let clip = UIPasteboard.general.string, clip.contains("drive.google.com") {
                    driveLink = clip
                }
            }
            .alert("Importation", isPresented: $showAlert) {
                Button("OK", role: .cancel) {
                    if alertMessage?.contains("succès") == true {
                        dismiss()
                    }
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }
    
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(.blue, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(FluenceColor.ink)
        }
    }
    
    private func importRawTextContent() {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let count = AnkiGoogleDriveManager.shared.importRawText(text, store: coordinator.store, languageID: coordinator.language.id)
        rawText = ""
        alertMessage = "\(count) mots importés avec succès !"
        showAlert = true
    }
    
    private func importCurrentWebDocument() {
        isDownloading = true
        guard let webView = webViewRef else {
            let urlString = currentURLString
            Task {
                do {
                    let count = try await service.importFromPublicLink(urlString: urlString, store: coordinator.store, targetLanguageID: coordinator.language.id)
                    await MainActor.run {
                        isDownloading = false
                        alertMessage = "\(count) mots importés avec succès depuis Google Drive !"
                        showAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isDownloading = false
                        alertMessage = "Sélectionnez un fichier ou document dans votre Drive, puis appuyez sur Importer."
                        showAlert = true
                    }
                }
            }
            return
        }
        
        webView.evaluateJavaScript("window.location.href") { result, _ in
            let urlString = (result as? String) ?? currentURLString
            Task {
                do {
                    let count = try await service.importFromPublicLink(urlString: urlString, store: coordinator.store, targetLanguageID: coordinator.language.id)
                    await MainActor.run {
                        isDownloading = false
                        alertMessage = "\(count) mots importés avec succès depuis Google Drive !"
                        showAlert = true
                    }
                } catch {
                    await MainActor.run {
                        isDownloading = false
                        alertMessage = "Pour importer : ouvrez un fichier ou un document dans Drive, puis appuyez sur Importer."
                        showAlert = true
                    }
                }
            }
        }
    }
    
    private func importFromLink() {
        let link = driveLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        isDownloading = true
        Task {
            do {
                let count = try await service.importFromPublicLink(urlString: link, store: coordinator.store, targetLanguageID: coordinator.language.id)
                isDownloading = false
                driveLink = ""
                alertMessage = "\(count) mots importés avec succès depuis votre lien Google Drive !"
                showAlert = true
            } catch {
                isDownloading = false
                alertMessage = "Impossible d'importer ce lien Google Drive : \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
}

struct WordsView: View {
    let coordinator: ConversationCoordinator
    @State private var search = ""
    @State private var selected: WordState?
    @State private var sessions = false
    @State private var importingAnki = false
    @State private var showGoogleDrive = false
    @State private var exportURL: URL?
    @State private var alertMessage: String?
    @State private var showAlert = false
    
    private var learner: LearnerState { coordinator.store.learner }
    private var words: [WordState] { learner.words.filter { search.isEmpty || $0.lemma.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) } }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(eyebrow: "Mots et Vocabulaire", title: "Vos mots.", subtitle: "Mots et phrases pour vos futures discussions.")
                
                // Anki & Google Drive Sync / Import / Export Bar
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        // 1. Google Drive Direct Button
                        Button {
                            showGoogleDrive = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "externaldrive.badge.icloud")
                                    .font(.caption)
                                Text("Google Drive")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                            }
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        // 2. Anki, Folder & Local File Batch Import Button
                        Button {
                            importingAnki = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.caption)
                                Text("Dossier / Fichiers")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            }
                            .foregroundStyle(FluenceColor.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        // 3. Export Menu
                        Menu {
                            Button {
                                if let url = AnkiGoogleDriveManager.shared.exportToAnkiTSV(words: words, language: coordinator.language.name) {
                                    exportURL = url
                                }
                            } label: {
                                Label("Exporter Deck Anki (.txt / .tsv)", systemImage: "rectangle.stack.badge.plus")
                            }
                            
                            Button {
                                if let url = AnkiGoogleDriveManager.shared.exportToJSON(words: words, language: coordinator.language.name) {
                                    exportURL = url
                                }
                            } label: {
                                Label("Exporter Sauvegarde Drive (.json)", systemImage: "externaldrive.fill")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                                Text("Exporter")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            }
                            .foregroundStyle(FluenceColor.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(FluenceColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(FluenceColor.emerald)
                        Text("Accès direct Google Drive & Anki")
                            .font(.caption2)
                            .foregroundStyle(FluenceColor.secondary)
                        Spacer()
                        Text("\(words.count) mots")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(FluenceColor.ink)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(14)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                
                if words.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "leaf").font(.system(size: 34, weight: .light))
                        Text(search.isEmpty ? "Ils pousseront d'ici." : "Aucun mot correspondant.").font(.system(.title2, design: .rounded, weight: .medium))
                        Text(search.isEmpty ? "Au fil de nos discussions, les mots et expressions utiles apparaîtront ici. Vous pouvez aussi importer un paquet Anki ou un fichier depuis Google Drive." : "Essayer un autre mot ou une signification.").font(.subheadline).foregroundStyle(FluenceColor.secondary)
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(FluenceColor.sage, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(words) { word in
                            Button { selected = word } label: {
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(word.lemma).font(.system(size: 30, weight: .bold, design: .rounded))
                                        Text(word.meaning).font(.title3).foregroundStyle(FluenceColor.secondary)
                                    }
                                    Spacer(minLength: 10)
                                    VStack(alignment: .trailing, spacing: 8) { RecallBars(count: word.bars); Text(word.label).font(.caption2).foregroundStyle(FluenceColor.secondary) }
                                }.padding(.vertical, 20)
                            }.buttonStyle(.plain)
                            Divider().overlay(FluenceColor.peach)
                        }
                    }
                }
                HStack { Text("1 · Fragile"); Spacer(); Text("2 · En croissance"); Spacer(); Text("3 · Solide") }.font(.caption).foregroundStyle(FluenceColor.secondary)
                Text("Les barres estiment votre capacité de mémorisation orale. Le moteur FSRS gère l'espacement et la révision.").font(.footnote).foregroundStyle(FluenceColor.secondary)
                if !learner.capabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Trouver votre voix").font(.system(.title3, design: .rounded, weight: .semibold))
                        ForEach(learner.capabilities, id: \.self) { Text($0).font(.subheadline) }
                        Text("Observé lors de nos conversations. Estimations non officielles.").font(.footnote).foregroundStyle(FluenceColor.secondary)
                    }.padding(22).background(FluenceColor.butter, in: RoundedRectangle(cornerRadius: 24))
                }
            }.padding(22).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(FluenceColor.ink)
        .searchable(text: $search, prompt: "Rechercher un mot")
        .sheet(item: $selected) { word in WordDetailView(word: word, store: coordinator.store) }
        .sheet(isPresented: $sessions) { SessionHistoryView(store: coordinator.store) }
        .sheet(isPresented: $showGoogleDrive) { GoogleDriveBrowserSheet(coordinator: coordinator) }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let url = exportURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .fileImporter(isPresented: $importingAnki, allowedContentTypes: [.folder, .directory, .item, .data, .plainText, .pdf, .json, .commaSeparatedText, .tabSeparatedText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                Task {
                    do {
                        let res = try await AnkiGoogleDriveManager.shared.importBatch(from: urls, store: coordinator.store, languageID: coordinator.language.id)
                        alertMessage = "\(res.filesCount) fichier(s) du dossier traité(s), \(res.wordsCount) mots et expressions importés avec succès !"
                        showAlert = true
                    } catch {
                        alertMessage = "Erreur lors de l'importation : \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            case .failure(let error):
                alertMessage = "Sélection annulée ou erreur : \(error.localizedDescription)"
                showAlert = true
            }
        }
        .alert("Importation de vocabulaire", isPresented: $showAlert) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
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
                Text(word.meaning).font(.title3).foregroundStyle(FluenceColor.secondary)
                HStack { RecallBars(count: word.bars); Text(word.label).font(.subheadline) }
                Text(word.explanation).font(.body)
                Text("“\(word.example)”").font(.system(.title3, design: .rounded)).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(FluenceColor.peach, in: RoundedRectangle(cornerRadius: 22))
                Text("\(word.independentCount) utilisations indépendantes · Vu pour la dernière fois : \(word.lastSeen.formatted(date: .abbreviated, time: .omitted))").font(.footnote).foregroundStyle(FluenceColor.secondary)
                Button("Supprimer de mes mots", role: .destructive) { store.hideWord(word.id); dismiss() }.font(.footnote)
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(FluenceColor.cream).foregroundStyle(FluenceColor.ink)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct SourcesView: View {
    var sources: [SourceLink]
    var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources · \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(FluenceColor.secondary)
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
                                Text(passage.speaker == .assistant ? "FLUENCE" : "YOU").font(.caption).tracking(1).foregroundStyle(FluenceColor.secondary)
                                Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                                if session.languageID == "zh" { PinyinHelp(text: passage.text) }
                                if let translation = session.translations[MeaningRequest.cacheKey(revisionKey: passage.revisionKey, language: meaningLanguage)] ?? session.translations[passage.revisionKey] {
                                    Text(translation).font(.subheadline).foregroundStyle(FluenceColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(session.topics) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                        if session.fragments.isEmpty && session.topics.isEmpty { Text("Your conversation will appear here.").foregroundStyle(FluenceColor.secondary) }
                    } else { Text("Start a conversation and your words will appear here.") }
                }.padding(26)
            }.background(FluenceColor.cream).foregroundStyle(FluenceColor.ink)
                .navigationTitle("Notre conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
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
                if store.learningSessions.isEmpty { Text("Vos conversations en \(store.language.name) apparaîtront ici.").foregroundStyle(FluenceColor.secondary) }
                ForEach(store.learningSessions) { session in
                    Button { selected = session } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(FluenceColor.secondary)
                        }.padding(.vertical, 8)
                    }.swipeActions { Button("Supprimer", role: .destructive) { deleting = session }.disabled(session.endedAt == nil) }
                }
            }.scrollContentBackground(.hidden).background(FluenceColor.cream)
                .navigationTitle("Conversations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }.sheet(item: $selected) { session in EditableTranscriptView(sessionID: session.id, store: store) }
            .confirmationDialog("Supprimer cette conversation et ses données d'apprentissage ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Supprimer", role: .destructive) { if let deleting { store.deleteSession(deleting.id) }; deleting = nil }
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
                                Text(passage.speaker == .user ? "YOU" : "FLUENCE").font(.caption).tracking(1)
                                Spacer()
                                if passage.speaker == .user && session?.endedAt != nil {
                                    Button("Edit") { editedText = passage.text; editingID = passage.id }.font(.caption)
                                }
                            }.foregroundStyle(FluenceColor.secondary)
                            Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                            if session?.languageID == "zh" { PinyinHelp(text: passage.text) }
                        }
                    }
                    ForEach(session?.topics ?? []) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26)
            }.background(FluenceColor.cream).foregroundStyle(FluenceColor.ink)
                .navigationTitle("Notre conversation").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }.sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Ce que vous avez dit", text: $editedText, axis: .vertical).lineLimit(4...10).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    Text("Corrigez une phrase mal comprise. L'ancienne phrase sera remplacée dans l'historique et votre apprentissage s'adaptera.").font(.footnote).foregroundStyle(FluenceColor.secondary)
                    Spacer()
                }.padding(24).background(FluenceColor.cream).navigationTitle("Ce que vous avez dit").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Annuler") { editingID = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Sauvegarder") { if let id = editingID { store.correctPassage(sessionID: sessionID, passageID: id, text: editedText) }; editingID = nil } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
}

@MainActor
struct SettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: BackupDocument?
    @State private var deleting = false
    @State private var notices = false
    
    private var store: LearningStore { coordinator.store }
    private var totalVoiceSeconds: Double { store.sessions.reduce(0) { $0 + $1.voiceSeconds } }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased().hasPrefix(String(store.language.locale.prefix(2)).lowercased())
        }
    }

    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                premiumSection
                Group {
                    appearanceSection
                    kidsModeSection
                    pedagogySection
                    audioSection
                }
                Group {
                    notificationSection
                    aiSection
                    dataSection
                    aboutSection
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Fluence-learning-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Archive.readImportData(from: url))
                message = "Sauvegarde importée avec succès."
            } catch {
                message = error.localizedDescription
            }
        }
        .alert("Information", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .alert("Réinitialiser l'apprentissage", isPresented: $deleting) {
            Button("Annuler", role: .cancel) {}
            Button("Tout effacer", role: .destructive) {
                coordinator.deleteLearningData()
                dismiss()
            }
        } message: {
            Text("Voulez-vous vraiment effacer tout votre historique de sessions et réinitialiser vos statistiques ? Cette action est irréversible.")
        }
        .sheet(isPresented: $notices) {
            NavigationStack {
                ScrollView {
                    Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Notices unavailable.")
                        .font(.footnote)
                        .padding(24)
                }
                .navigationTitle("Mentions Légales")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { notices = false }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
    
    // MARK: - Sections Découpées pour Compilation Rapide
    
    @ViewBuilder
    private var premiumSection: some View {
        Section {
            Button(action: { showingPaywall = true }) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(StoreKitManager.shared.isPremium ? .yellow : .blue)
                    VStack(alignment: .leading) {
                        Text(StoreKitManager.shared.isPremium ? "Fluence Premium Actif" : "Passer à Fluence Premium")
                            .font(.headline)
                            .foregroundStyle(StoreKitManager.shared.isPremium ? .yellow : .primary)
                        Text(StoreKitManager.shared.isPremium ? "Merci pour votre soutien !" : "Débloquez l'apprentissage illimité")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !StoreKitManager.shared.isPremium {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker(selection: Binding(get: { store.preferences.appearance }, set: { val in store.updatePreferences { $0.appearance = val } })) {
                Text("Automatique (Système)").tag("system")
                Text("Sombre").tag("dark")
                Text("Clair").tag("light")
            } label: {
                Label("Thème d'affichage", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
        } header: {
            Text("Apparence")
        }
    }
    
    @ViewBuilder
    private var kidsModeSection: some View {
        Section {
            NavigationLink {
                KidsSettingsSubView(coordinator: coordinator)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                        Image(systemName: "face.smiling.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 16))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode Enfant & Contrôle Parental")
                            .font(.headline)
                            .foregroundStyle(FluenceColor.ink)
                        Text(store.preferences.isKidsModeActive ? "Actif · Verrouillé" : "Apprentissage ludique & Accès restreint")
                            .font(.caption)
                            .foregroundStyle(store.preferences.isKidsModeActive ? Color.green : FluenceColor.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(FluenceColor.secondary)
                }
            }
        } header: {
            Text("Espace Enfants")
        } footer: {
            Text("Permet de confier votre iPhone à votre enfant pour apprendre une langue en toute sécurité grâce au verrouillage parental et à l'Accès Guidé iOS.")
        }
    }
    
    @ViewBuilder
    private var pedagogySection: some View {
        Section {
            Picker(selection: Binding(get: { store.preferences.pedagogicalMode }, set: { val in store.updatePreferences { $0.pedagogicalMode = val } })) {
                Text("👨🏫 Professeur Particulier (Guidé)").tag("teacher")
                Text("💬 Discussion Libre (Immersion)").tag("conversation")
            } label: {
                Label("Mode d'apprentissage", systemImage: "graduationcap.fill")
            }
            .pickerStyle(.menu)
            
            Picker(selection: Binding(get: { coordinator.language.id }, set: { coordinator.selectLanguage($0) })) {
                ForEach(LanguageRegistry.all) { language in
                    Text(language.settingsTitle).tag(language.id)
                }
            } label: {
                Label("Langue apprise", systemImage: "globe")
            }
            .pickerStyle(.menu)
            
            Picker(selection: Binding(get: { store.preferences.cefrLevel }, set: { val in store.updatePreferences { $0.cefrLevel = val } })) {
                Text("A1 · Débutant").tag("A1")
                Text("A2 · Élémentaire").tag("A2")
                Text("B1 · Intermédiaire").tag("B1")
                Text("B2 · Avancé (Recommandé)").tag("B2")
                Text("C1 · Autonome / Médical").tag("C1")
                Text("C2 · Bilingue / Expert").tag("C2")
            } label: {
                Label("Niveau de départ (CECRL)", systemImage: "chart.bar.fill")
            }
            .pickerStyle(.menu)
            
            Toggle(isOn: Binding(get: { store.preferences.meaningVisible }, set: { value in
                if value != store.preferences.meaningVisible { coordinator.toggleMeaning() }
            })) {
                Label("Sous-titres & Traduction", systemImage: "captions.bubble.fill")
            }
            
            if store.preferences.meaningVisible {
                Picker(selection: Binding(get: { store.preferences.meaningLanguage }, set: { coordinator.selectMeaningLanguage($0) })) {
                    ForEach(MeaningLanguages.all, id: \.self) { Text($0).tag($0) }
                } label: {
                    Label("Langue de traduction", systemImage: "character.book.closed")
                }
                .pickerStyle(.menu)
            }
            
            Picker(selection: Binding(get: { store.preferences.correctionLevel }, set: { val in store.updatePreferences { $0.correctionLevel = val } })) {
                Text("Strict (corrige chaque phrase)").tag("high")
                Text("Équilibré (naturel)").tag("medium")
                Text("Fluide (erreurs clés)").tag("low")
            } label: {
                Label("Niveau de correction", systemImage: "checkmark.seal")
            }
            .pickerStyle(.menu)
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Centres d'intérêt", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.ink)
                TextField("Ex: médecine, voyages, philosophie...", text: Binding(get: { store.preferences.interests }, set: { value in store.updatePreferences { $0.interests = String(value.prefix(500)) } }))
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.secondary)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Apprentissage")
        }
    }
    
    @ViewBuilder
    private var audioSection: some View {
        Section {
            Picker(selection: Binding(get: { store.preferences.speechRate }, set: { val in store.updatePreferences { $0.speechRate = val } })) {
                Text("Lente (0.8x)").tag(Float(0.40))
                Text("Normale (1.0x)").tag(Float(0.50))
                Text("Rapide (1.2x)").tag(Float(0.60))
            } label: {
                Label("Vitesse vocale", systemImage: "gauge.with.dots.needle.50percent")
            }
            .pickerStyle(.menu)
            
            Picker(selection: Binding(get: { store.preferences.selectedVoiceIdentifier }, set: { val in store.updatePreferences { $0.selectedVoiceIdentifier = val } })) {
                Text("Automatique").tag("")
                ForEach(availableVoices, id: \.identifier) { v in
                    let qualityStr = v.quality == .premium ? " (HD)" : ""
                    Text("\(v.name)\(qualityStr)").tag(v.identifier)
                }
            } label: {
                Label("Accent & Timbre", systemImage: "person.wave.2")
            }
            .pickerStyle(.menu)
            
            Button {
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
            } label: {
                Label("Écouter un extrait audio", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
            }
        } header: {
            Text("Voix & Audio")
        }
    }
    
    @ViewBuilder
    private var notificationSection: some View {
        Section {
            NavigationLink {
                NotificationSettingsSubView()
            } label: {
                HStack {
                    Label("Rappels & Notifications", systemImage: "bell.badge.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(FluenceColor.secondary)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Recevez des rappels matin et soir avec vos mots de vocabulaire FSRS à réviser.")
        }
    }
    
    @ViewBuilder
    private var aiSection: some View {
        Section {
            Picker(selection: Binding(get: { store.preferences.providerID }, set: { val in store.updatePreferences { $0.providerID = val } })) {
                Text("Auto (Sélection Intelligente & Fallback)").tag("auto")
                Text("OpenAI (ChatGPT / GPT-4o)").tag("openai")
                Text("Anthropic (Claude 3.5)").tag("anthropic")
                Text("Google Gemini (2.0 Flash)").tag("google")
                Text("Groq Cloud (Llama 3.3 / Ultra-Rapide)").tag("groq")
                Text("DeepSeek (V3 / R1)").tag("deepseek")
                Text("Mistral AI (Large / Small)").tag("mistral")
                Text("OpenRouter (100+ Modèles)").tag("openrouter")
                Text("Serveur Personnalisé (Ollama / LocalAI)").tag("custom")
                Text("Hermes VPS Personnel").tag("hermes_vps")
            } label: {
                Label("Moteur actif", systemImage: "cpu")
            }
            .pickerStyle(.menu)
            
            NavigationLink {
                AISettingsSubView(coordinator: coordinator)
            } label: {
                Label("Clés API & Modèles avancés", systemImage: "slider.horizontal.2.square")
            }
        } header: {
            Text("Intelligence Artificielle")
        } footer: {
            Text("En mode Auto, Fluence bascule automatiquement sur le meilleur modèle disponible sans interruption.")
        }
    }
    
    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button {
                do { backup = BackupDocument(data: try store.exportData()); exporting = true }
                catch { message = error.localizedDescription }
            } label: {
                Label("Exporter mes données", systemImage: "square.and.arrow.up")
            }
            
            Button {
                importing = true
            } label: {
                Label("Importer une sauvegarde", systemImage: "square.and.arrow.down")
            }
            .disabled(coordinator.isRunning)
            
            Button(role: .destructive) {
                deleting = true
            } label: {
                Label("Réinitialiser l'apprentissage", systemImage: "trash")
            }
            .disabled(coordinator.isRunning)
        } header: {
            Text("Données & Sauvegarde")
        }
    }
    
    @ViewBuilder
    private var aboutSection: some View {
        Section {
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text("2.0 (Fluence)")
                    .foregroundStyle(FluenceColor.secondary)
            }
            
            Link(destination: URL(string: "https://fluence.chat/privacy/")!) {
                Label("Politique de confidentialité", systemImage: "lock.shield")
            }
            
            Button {
                notices = true
            } label: {
                Label("Mentions légales open-source", systemImage: "doc.plaintext")
            }
        } header: {
            Text("À propos")
        }
    }
}

// MARK: - Dedicated Clean AI Subpage
@MainActor
struct AISettingsSubView: View {
    let coordinator: ConversationCoordinator
    @State private var groqKey = ""
    @State private var hasGroqKey = KeychainHelper.shared.hasKey(for: .groq)
    @State private var openaiKey = ""
    @State private var hasOpenAIKey = KeychainHelper.shared.hasKey(for: .openai)
    @State private var anthropicKey = ""
    @State private var hasAnthropicKey = KeychainHelper.shared.hasKey(for: .anthropic)
    @State private var deepseekKey = ""
    @State private var hasDeepseekKey = KeychainHelper.shared.hasKey(for: .deepseek)
    @State private var mistralKey = ""
    @State private var hasMistralKey = KeychainHelper.shared.hasKey(for: .mistral)
    @State private var openrouterKey = ""
    @State private var hasOpenrouterKey = KeychainHelper.shared.hasKey(for: .openrouter)
    @State private var message: String?
    
    private var store: LearningStore { coordinator.store }
    
    var body: some View {
        Form {
            Group {
                openaiSection
                anthropicSection
                geminiSection
                groqSection
            }
            Group {
                deepseekSection
                mistralSection
                openrouterSection
                customServerSection
                vpsSection
            }
        }
        .navigationTitle("Fournisseurs d'IA")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Information", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
    
    @ViewBuilder
    private var openaiSection: some View {
        Section {
            Picker("Modèle OpenAI", selection: Binding(get: { store.preferences.openaiModel }, set: { val in store.updatePreferences { $0.openaiModel = val } })) {
                Text("GPT-4o mini (Rapide & Économique)").tag("gpt-4o-mini")
                Text("GPT-4o (Complet)").tag("gpt-4o")
                Text("o3-mini (Raisonnement)").tag("o3-mini")
                Text("o1 (Raisonnement Avancé)").tag("o1")
                Text("GPT-4 Turbo").tag("gpt-4-turbo")
            }
            .pickerStyle(.menu)
            
            SecureField(hasOpenAIKey ? "Clé enregistrée (remplacer)" : "Clé API OpenAI (sk-...)", text: $openaiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !openaiKey.isEmpty {
                Button("Sauvegarder la clé OpenAI") {
                    do {
                        try KeychainHelper.shared.save(openaiKey, for: .openai)
                        store.updatePreferences { $0.openaiAPIKey = openaiKey }
                        openaiKey = ""
                        hasOpenAIKey = true
                        message = "Clé OpenAI enregistrée dans le Keychain."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé API OpenAI", destination: URL(string: "https://platform.openai.com/api-keys")!)
        } header: {
            Label("OpenAI (ChatGPT / GPT-4o)", systemImage: "brain.head.profile")
        }
    }
    
    @ViewBuilder
    private var anthropicSection: some View {
        Section {
            Picker("Modèle Claude", selection: Binding(get: { store.preferences.anthropicModel }, set: { val in store.updatePreferences { $0.anthropicModel = val } })) {
                Text("Claude 3.5 Sonnet (Recommandé)").tag("claude-3-5-sonnet-20241022")
                Text("Claude 3.5 Haiku (Ultra-Rapide)").tag("claude-3-5-haiku-20241022")
                Text("Claude 3 Opus (Créatif)").tag("claude-3-opus-20240229")
            }
            .pickerStyle(.menu)
            
            SecureField(hasAnthropicKey ? "Clé enregistrée (remplacer)" : "Clé API Claude (sk-ant-...)", text: $anthropicKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !anthropicKey.isEmpty {
                Button("Sauvegarder la clé Anthropic") {
                    do {
                        try KeychainHelper.shared.save(anthropicKey, for: .anthropic)
                        store.updatePreferences { $0.anthropicAPIKey = anthropicKey }
                        anthropicKey = ""
                        hasAnthropicKey = true
                        message = "Clé Anthropic enregistrée."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé API Anthropic", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
        } header: {
            Label("Anthropic Claude", systemImage: "sparkles")
        }
    }
    
    @ViewBuilder
    private var geminiSection: some View {
        Section {
            Picker("Modèle Gemini", selection: Binding(get: { store.preferences.geminiModel }, set: { val in store.updatePreferences { $0.geminiModel = val } })) {
                Text("Gemini 2.0 Flash (Recommandé)").tag("gemini-2.0-flash")
                Text("Gemini 2.0 Lite").tag("gemini-2.0-flash-lite")
                Text("Gemini 1.5 Pro").tag("gemini-1.5-pro")
                Text("Gemini 1.5 Flash").tag("gemini-1.5-flash")
            }
            .pickerStyle(.menu)
            
            SecureField("Clé API Gemini (AIzaSy...)", text: Binding(get: { store.preferences.googleAPIKey }, set: { val in store.updatePreferences { $0.googleAPIKey = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            Link("Obtenir une clé Gemini gratuite", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
        } header: {
            Label("Google Gemini API", systemImage: "sparkle")
        }
    }
    
    @ViewBuilder
    private var groqSection: some View {
        Section {
            Picker("Modèle Groq", selection: Binding(get: { store.preferences.groqModel }, set: { val in store.updatePreferences { $0.groqModel = val } })) {
                Text("Llama 3.3 70B (Optimal)").tag("llama-3.3-70b-versatile")
                Text("GPT-OSS 120B").tag("openai/gpt-oss-120b")
                Text("Qwen 3.8 27B").tag("qwen/qwen3.8-27b")
                Text("Llama 3.1 8B (Ultra-Rapide)").tag("llama-3.1-8b-instant")
            }
            .pickerStyle(.menu)
            
            SecureField(hasGroqKey ? "Clé enregistrée (remplacer)" : "Clé API Groq (gsk_...)", text: $groqKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !groqKey.isEmpty {
                Button("Sauvegarder la clé Groq") {
                    do {
                        try KeychainHelper.shared.save(groqKey, for: .groq)
                        try KeychainHelper.shared.save(groqKey, for: .owner)
                        groqKey = ""
                        hasGroqKey = true
                        message = "Clé Groq enregistrée."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé Groq gratuite", destination: URL(string: "https://console.groq.com/keys")!)
        } header: {
            Label("Groq Cloud API", systemImage: "bolt.fill")
        }
    }
    
    @ViewBuilder
    private var deepseekSection: some View {
        Section {
            Picker("Modèle DeepSeek", selection: Binding(get: { store.preferences.deepseekModel }, set: { val in store.updatePreferences { $0.deepseekModel = val } })) {
                Text("DeepSeek V3 (Chat)").tag("deepseek-chat")
                Text("DeepSeek R1 (Raisonnement)").tag("deepseek-reasoner")
            }
            .pickerStyle(.menu)
            
            SecureField(hasDeepseekKey ? "Clé enregistrée (remplacer)" : "Clé API DeepSeek (sk-...)", text: $deepseekKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !deepseekKey.isEmpty {
                Button("Sauvegarder la clé DeepSeek") {
                    do {
                        try KeychainHelper.shared.save(deepseekKey, for: .deepseek)
                        store.updatePreferences { $0.deepseekAPIKey = deepseekKey }
                        deepseekKey = ""
                        hasDeepseekKey = true
                        message = "Clé DeepSeek enregistrée."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé API DeepSeek", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
        } header: {
            Label("DeepSeek AI", systemImage: "magnifyingglass.circle")
        }
    }
    
    @ViewBuilder
    private var mistralSection: some View {
        Section {
            Picker("Modèle Mistral", selection: Binding(get: { store.preferences.mistralModel }, set: { val in store.updatePreferences { $0.mistralModel = val } })) {
                Text("Mistral Small (Rapide)").tag("mistral-small-latest")
                Text("Mistral Large 2 (Complet)").tag("mistral-large-latest")
                Text("Codestral (Spécialisé Code)").tag("codestral-latest")
            }
            .pickerStyle(.menu)
            
            SecureField(hasMistralKey ? "Clé enregistrée (remplacer)" : "Clé API Mistral", text: $mistralKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !mistralKey.isEmpty {
                Button("Sauvegarder la clé Mistral") {
                    do {
                        try KeychainHelper.shared.save(mistralKey, for: .mistral)
                        store.updatePreferences { $0.mistralAPIKey = mistralKey }
                        mistralKey = ""
                        hasMistralKey = true
                        message = "Clé Mistral enregistrée."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé API Mistral", destination: URL(string: "https://console.mistral.ai/api-keys/")!)
        } header: {
            Label("Mistral AI", systemImage: "wind")
        }
    }
    
    @ViewBuilder
    private var openrouterSection: some View {
        Section {
            Picker("Modèle OpenRouter", selection: Binding(get: { store.preferences.openrouterModel }, set: { val in store.updatePreferences { $0.openrouterModel = val } })) {
                Text("Llama 3.3 70B (Gratuit)").tag("meta-llama/llama-3.3-70b-instruct:free")
                Text("Claude 3.5 Sonnet").tag("anthropic/claude-3.5-sonnet")
                Text("GPT-4o").tag("openai/gpt-4o")
                Text("DeepSeek V3").tag("deepseek/deepseek-chat")
            }
            .pickerStyle(.menu)
            
            SecureField(hasOpenrouterKey ? "Clé enregistrée (remplacer)" : "Clé API OpenRouter (sk-or-...)", text: $openrouterKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            if !openrouterKey.isEmpty {
                Button("Sauvegarder la clé OpenRouter") {
                    do {
                        try KeychainHelper.shared.save(openrouterKey, for: .openrouter)
                        store.updatePreferences { $0.openrouterAPIKey = openrouterKey }
                        openrouterKey = ""
                        hasOpenrouterKey = true
                        message = "Clé OpenRouter enregistrée."
                    } catch { message = error.localizedDescription }
                }
            }
            
            Link("Obtenir une clé OpenRouter", destination: URL(string: "https://openrouter.ai/keys")!)
        } header: {
            Label("OpenRouter (100+ Modèles)", systemImage: "network")
        }
    }
    
    @ViewBuilder
    private var customServerSection: some View {
        Section {
            TextField("URL Endpoint (ex: http://192.168.1.50:11434/v1/chat/completions)", text: Binding(get: { store.preferences.customEndpoint }, set: { val in store.updatePreferences { $0.customEndpoint = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            TextField("Identifiant du modèle (ex: llama3, mistral)", text: Binding(get: { store.preferences.customModel }, set: { val in store.updatePreferences { $0.customModel = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            SecureField("Clé API / Bearer Token (Facultatif)", text: Binding(get: { store.preferences.customAPIKey }, set: { val in store.updatePreferences { $0.customAPIKey = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Label("Serveur Personnalisé (Ollama / LM Studio / Local)", systemImage: "desktopcomputer")
        } footer: {
            Text("Compatible avec tout serveur local ou distant exposant une API compatible OpenAI.")
        }
    }
    
    @ViewBuilder
    private var vpsSection: some View {
        Section {
            TextField("URL Endpoint VPS", text: Binding(get: { store.preferences.vpsEndpoint }, set: { val in store.updatePreferences { $0.vpsEndpoint = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            SecureField("Token VPS (Facultatif)", text: Binding(get: { store.preferences.vpsAPIKey }, set: { val in store.updatePreferences { $0.vpsAPIKey = val } }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            Picker("Modèle VPS", selection: Binding(get: { store.preferences.vpsModel }, set: { val in store.updatePreferences { $0.vpsModel = val } })) {
                Text("Hermes Auto (OmniRoute)").tag("auto/best-coding")
                Text("Hermes 3 (8B Local)").tag("NousResearch/Hermes-3-Llama-3.1-8B")
                Text("Hermes Vocal VPS").tag("hermes-agent-vps")
            }
            .pickerStyle(.menu)
        } header: {
            Label("Agent VPS Personnel Hermes", systemImage: "server.rack")
        } footer: {
            Text("Connexion directe à votre instance Oracle Cloud VPS.")
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

// MARK: - Notification Settings Subview (Apple Compliant)

@MainActor
struct NotificationSettingsSubView: View {
    @State private var settings: NotificationSettings = NotificationManager.shared.settings
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testSent = false
    
    private var morningDateBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.morningHour
                components.minute = settings.morningMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.morningHour = components.hour ?? 9
                settings.morningMinute = components.minute ?? 0
                NotificationManager.shared.saveSettings(settings)
            }
        )
    }
    
    private var eveningDateBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.eveningHour
                components.minute = settings.eveningMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.eveningHour = components.hour ?? 19
                settings.eveningMinute = components.minute ?? 30
                NotificationManager.shared.saveSettings(settings)
            }
        )
    }
    
    var body: some View {
        Form {
            // Permission Banner (if not authorized)
            if authStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Notifications désactivées")
                                .font(.headline)
                        }
                        Text("Les alertes sont bloquées dans les réglages système d'iOS. Activez-les pour recevoir vos rappels de cours et de vocabulaire.")
                            .font(.caption)
                            .foregroundStyle(FluenceColor.secondary)
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Ouvrir les Réglages de l'iPhone")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .padding(.vertical, 4)
                }
            } else if authStatus == .notDetermined {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundStyle(.blue)
                            Text("Autorisation requise")
                                .font(.headline)
                        }
                        Text("Conformément aux règles de confidentialité d'Apple, Fluence demande votre accord avant d'envoyer des rappels d'étude.")
                            .font(.caption)
                            .foregroundStyle(FluenceColor.secondary)
                        
                        Button {
                            Task {
                                let granted = await NotificationManager.shared.requestAuthorization()
                                authStatus = await NotificationManager.shared.checkAuthorizationStatus()
                                if granted {
                                    settings.isEnabled = true
                                    NotificationManager.shared.saveSettings(settings)
                                }
                            }
                        } label: {
                            Text("Autoriser les notifications")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // Scheduling Options
            Section {
                Toggle(isOn: Binding(
                    get: { settings.isEnabled },
                    set: { val in
                        settings.isEnabled = val
                        NotificationManager.shared.saveSettings(settings)
                        if val && authStatus != .authorized {
                            Task {
                                _ = await NotificationManager.shared.requestAuthorization()
                                authStatus = await NotificationManager.shared.checkAuthorizationStatus()
                            }
                        }
                    }
                )) {
                    Label("Rappels quotidiens d'allemand", systemImage: "bell.fill")
                }
                
                if settings.isEnabled {
                    Picker(selection: Binding(
                        get: { settings.notificationsPerDay },
                        set: { val in
                            settings.notificationsPerDay = val
                            NotificationManager.shared.saveSettings(settings)
                        }
                    )) {
                        Text("1 fois par jour").tag(1)
                        Text("2 fois par jour (Matin & Soir)").tag(2)
                    } label: {
                        Label("Fréquence", systemImage: "repeat")
                    }
                    .pickerStyle(.menu)
                    
                    DatePicker(
                        selection: morningDateBinding,
                        displayedComponents: .hourAndMinute
                    ) {
                        Label("Rappel du Matin", systemImage: "sun.max.fill")
                    }
                    
                    if settings.notificationsPerDay >= 2 {
                        DatePicker(
                            selection: eveningDateBinding,
                            displayedComponents: .hourAndMinute
                        ) {
                            Label("Rappel du Soir", systemImage: "moon.stars.fill")
                        }
                    }
                }
            } header: {
                Text("Planification")
            } footer: {
                Text("Les notifications intègrent vos vrais mots de vocabulaire FSRS en attente de révision pour stimuler votre mémoire.")
            }
            
            // Test Notification Section
            if authStatus == .authorized {
                Section {
                    Button {
                        Task {
                            await NotificationManager.shared.sendTestNotification()
                            testSent = true
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            testSent = false
                        }
                    } label: {
                        HStack {
                            Label("Envoyer une notification test (dans 3s)", systemImage: "paperplane.fill")
                            Spacer()
                            if testSent {
                                Text("Envoyé !")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Text("Test")
                } footer: {
                    Text("Touchez ce bouton puis verrouillez votre iPhone ou revenez à l'écran d'accueil pour voir la bannière et la nouvelle icône 3D Fluence.")
                }
            }
        }
        .navigationTitle("Rappels & Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authStatus = await NotificationManager.shared.checkAuthorizationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                authStatus = await NotificationManager.shared.checkAuthorizationStatus()
            }
        }
    }
}

// MARK: - Kids Settings SubView
struct KidsSettingsSubView: View {
    var coordinator: ConversationCoordinator
    @State private var showingGuidedAccessTutorial = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { coordinator.store.preferences.isKidsModeActive },
                    set: { val in
                        coordinator.store.updatePreferences {
                            $0.isKidsModeActive = val
                            if val {
                                $0.pedagogicalMode = "kids"
                            } else {
                                $0.pedagogicalMode = "teacher"
                            }
                        }
                    }
                )) {
                    Label("Activer le Mode Enfant", systemImage: "face.smiling.fill")
                        .foregroundStyle(FluenceColor.ink)
                }
                
                if !coordinator.store.preferences.isKidsModeActive {
                    Button {
                        coordinator.store.updatePreferences {
                            $0.isKidsModeActive = true
                            $0.pedagogicalMode = "kids"
                        }
                        dismiss()
                    } label: {
                        HStack {
                            Label("Lancer la session Enfant maintenant", systemImage: "play.circle.fill")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.indigo)
                }
            } header: {
                Text("État du Mode")
            } footer: {
                Text("Lorsque le Mode Enfant est activé, l'interface se simplifie en un espace vocal magique et tous les réglages et comptes sont masqués derrière votre code PIN.")
            }
            
            Section {
                Picker(selection: Binding(
                    get: { coordinator.store.preferences.kidsTargetLanguageID },
                    set: { val in
                        coordinator.store.updatePreferences {
                            $0.kidsTargetLanguageID = val
                            $0.learningLanguageID = val
                        }
                    }
                )) {
                    ForEach(LanguageRegistry.all) { lang in
                        Text("\(lang.flag) \(lang.settingsTitle)").tag(lang.id)
                    }
                } label: {
                    Label("Langue pour l'enfant", systemImage: "globe")
                }
                .pickerStyle(.menu)
                
                HStack {
                    Label("Prénom de l'enfant", systemImage: "person.fill")
                    Spacer()
                    TextField("Prénom", text: Binding(
                        get: { coordinator.store.preferences.kidsChildName },
                        set: { val in
                            coordinator.store.updatePreferences { $0.kidsChildName = val }
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(FluenceColor.secondary)
                }
                
                Stepper(value: Binding(
                    get: { coordinator.store.preferences.kidsChildAge },
                    set: { val in
                        coordinator.store.updatePreferences { $0.kidsChildAge = val }
                    }
                ), in: 3...15) {
                    Label("Âge : \(coordinator.store.preferences.kidsChildAge) ans", systemImage: "calendar")
                }
                
                Picker(selection: Binding(
                    get: { coordinator.store.preferences.kidsTheme },
                    set: { val in
                        coordinator.store.updatePreferences { $0.kidsTheme = val }
                    }
                )) {
                    Text("🐾 Animaux rigolos").tag("animals")
                    Text("🎨 Couleurs & Nombres").tag("colors")
                    Text("🔢 Chiffres & Magie").tag("numbers")
                    Text("🪄 Contes de fées").tag("magic")
                    Text("🚀 Super-Héros & Espace").tag("heroes")
                } label: {
                    Label("Thème préféré", systemImage: "sparkles")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Profil de l'Enfant")
            }
            
            Section {
                HStack {
                    Label("Code PIN Parental", systemImage: "lock.fill")
                    Spacer()
                    SecureField("Entrez le code PIN", text: Binding(
                        get: { coordinator.store.preferences.kidsParentalPIN },
                        set: { val in
                            coordinator.store.updatePreferences { $0.kidsParentalPIN = String(val.prefix(4)) }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                }
            } header: {
                Text("Sécurité Parentale")
            } footer: {
                Text("Code à 4 chiffres nécessaire pour déverrouiller et quitter le Mode Enfant.")
            }
            
            Section {
                Button {
                    showingGuidedAccessTutorial = true
                } label: {
                    HStack {
                        Label("Activer l'Accès Restreint (Accès Guidé iOS)", systemImage: "lock.shield.fill")
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(FluenceColor.secondary)
                    }
                }
            } header: {
                Text("Verrouillage Système de l'iPhone")
            } footer: {
                Text("Grâce à l'Accès Guidé iOS, verrouillez votre iPhone sur Fluence (3 clics sur le bouton latéral) pour empêcher votre enfant d'ouvrir d'autres applications.")
            }
        }
        .navigationTitle("Mode Enfant & Sécurité")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingGuidedAccessTutorial) {
            GuidedAccessHelpSheet(isPresented: $showingGuidedAccessTutorial)
        }
    }
}

// MARK: - StoreKit Manager & Paywall

import StoreKit

@MainActor
public class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs = Set<String>()
    private var transactionListener: Task<Void, Error>?
    public var isPremium: Bool { !purchasedProductIDs.isEmpty }
    private init() {
        transactionListener = listenForTransactions()
        Task { await updatePurchasedProducts(); await fetchProducts() }
    }
    deinit { transactionListener?.cancel() }
    public func fetchProducts() async {
        do {
            self.products = try await Product.products(for: ["com.fluence.premium.monthly", "com.fluence.premium.yearly"]).sorted(by: { $0.price < $1.price })
        } catch { print("Product fetch failed: \(error)") }
    }
    public func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updatePurchasedProducts()
            await transaction.finish()
        case .userCancelled, .pending: break
        @unknown default: break
        }
    }
    public func updatePurchasedProducts() async {
        var ids = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { ids.insert(t.productID) }
        }
        purchasedProductIDs = ids
    }
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result { case .unverified: throw StoreError.failedVerification; case .verified(let s): return s }
    }
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { for await result in Transaction.updates { do { let t = try await self.checkVerified(result); await self.updatePurchasedProducts(); await t.finish() } catch { print("TX failed: \(error)") } } }
    }
    public func restorePurchases() async { try? await AppStore.sync(); await self.updatePurchasedProducts() }
}

public enum StoreError: Error { case failedVerification }

public struct PaywallView: View {
    @StateObject private var storeKit = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    public init() {}
    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#120B24"), Color(hex: "#1A0F3D"), Color(hex: "#241842")], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        ZStack { Circle().fill(LinearGradient(colors: [Color(hex: "#9F7AEA"), Color(hex: "#63B3ED")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 84, height: 84).opacity(0.15).blur(radius: 8); Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(LinearGradient(colors: [.white, Color(hex: "#A3BFFA")], startPoint: .top, endPoint: .bottom)) }.padding(.top, 24)
                        Text("Fluence Premium").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("Libérez votre plein potentiel linguistique").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        PremiumFeatureRow(icon: "waveform.path", title: "Conversations Vocales Illimitées", subtitle: "Plus aucune limite de temps ou d'usage quotidien.")
                        PremiumFeatureRow(icon: "wand.and.stars", title: "Moteurs d'IA Avancés & HD", subtitle: "Accès prioritaire à Claude-3.5, GPT-4o et voix studio ultra-réalistes.")
                        PremiumFeatureRow(icon: "face.smiling", title: "Mode Enfant Premium", subtitle: "Suivi intelligent de la progression et histoires immersives pour vos enfants.")
                        PremiumFeatureRow(icon: "globe", title: "Plus de 25 Langues", subtitle: "Basculez librement d'une langue à l'autre instantanément.")
                    }
                    .padding(20).background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 1)))
                    .padding(.horizontal, 20)
                    if storeKit.products.isEmpty { ProgressView().tint(.white).padding(.vertical, 20) }
                    else { VStack(spacing: 14) { ForEach(storeKit.products, id: \.id) { p in PremiumProductCard(product: p, isSelected: true) { Task { await purchaseProduct(p) } } } }.padding(.horizontal, 20) }
                    if let e = errorMessage { Text(e).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal, 32) }
                    HStack(spacing: 24) {
                        Button("Restaurer les achats") { Task { await storeKit.restorePurchases(); if storeKit.isPremium { dismiss() } } }
                        Text("•").foregroundStyle(.secondary)
                        Link("Conditions", destination: URL(string: "https://fluence-agent.nousresearch.com/terms")!)
                        Text("•").foregroundStyle(.secondary)
                        Link("Confidentialité", destination: URL(string: "https://fluence-agent.nousresearch.com/privacy")!)
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 10).padding(.bottom, 32)
                }
            }
            VStack { HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.3)).padding(20) } }; Spacer() }
        }
    }
    private func purchaseProduct(_ p: Product) async { isPurchasing = true; errorMessage = nil; do { try await storeKit.purchase(p); if storeKit.isPremium { dismiss() } } catch { errorMessage = "Échec du paiement. Veuillez réessayer." }; isPurchasing = false }
}

struct PremiumFeatureRow: View {
    let icon: String; let title: String; let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) { Image(systemName: icon).font(.system(size: 20)).foregroundStyle(LinearGradient(colors: [Color(hex: "#9F7AEA"), Color(hex: "#63B3ED")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 28, height: 28); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white); Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) } }
    }
}

struct PremiumProductCard: View {
    let product: Product; let isSelected: Bool; let action: () -> Void
    var isYearly: Bool { product.id.contains("yearly") }
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { HStack(spacing: 8) { Text(product.displayName).font(.headline).foregroundStyle(.white); if isYearly { Text("ÉCONOMIE 50%").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color(hex: "#48BB78")).cornerRadius(4).foregroundStyle(.white) } }; Text(product.description).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) { Text(product.displayPrice).font(.title3.bold()).foregroundStyle(.white); Text(isYearly ? "/ an" : "/ mois").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(18).background(RoundedRectangle(cornerRadius: 20).fill(isYearly ? Color(hex: "#9F7AEA").opacity(0.12) : Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 20).stroke(isYearly ? Color(hex: "#9F7AEA").opacity(0.6) : Color.white.opacity(0.15), lineWidth: isYearly ? 2 : 1)))
        }
    }
}
