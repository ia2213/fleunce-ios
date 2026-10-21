import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import FluenceCore

// MARK: - Camera Picker Representable
struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
        } else {
            picker.sourceType = .photoLibrary
        }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Folder Picker Representable (iOS UIDocumentPickerViewController for Folders)
struct FolderPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FolderPickerView
        init(_ parent: FolderPickerView) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - Main Study Hub View
struct StudyHubView: View {
    @Bindable var coordinator: ConversationCoordinator
    @State private var lessons: [AssimilLesson] = []
    @State private var documents: [StudyDocument] = []
    @State private var fsrsDueItems: [FSRSItem] = []
    @State private var selectedLevelFilter: StudyLevel = .all
    
    @State private var showScanner = false
    @State private var showDocImporter = false
    @State private var showFolderImporter = false
    @State private var showFSRSVoiceSession = false
    @State private var showNotificationSettings = false
    @State private var activeAssimilLesson: AssimilLesson?
    @State private var activeDocument: StudyDocument?
    @State private var activeFolderSession: FolderStudySession?
    
    private let storeManager = StudyStoreManager.shared
    private let fsrsStore = FSRSStoreManager.shared

    init(coordinator: ConversationCoordinator) {
        self.coordinator = coordinator
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                quickActionsSection
                
                // FSRS Spaced Repetition & Daily Notification Hub
                fsrsVoiceSection
                
                // Level filter pills
                levelFilterBar
                
                // Folder groups (documents grouped by folder)
                folderGroupsSection
                
                // Assimil Lessons
                assimilSection
                
                // Individual documents
                documentsSection
                
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(FluenceColor.background)
        .navigationTitle("Professeur & Assimil")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedFSRSIfNeeded()
            reloadContent()
        }
        .sheet(isPresented: $showScanner, onDismiss: { reloadContent() }) {
            AssimilScannerView(coordinator: coordinator) { newLesson in
                storeManager.saveLesson(newLesson)
                reloadContent()
                activeAssimilLesson = newLesson
            }
        }
        .sheet(isPresented: $showDocImporter, onDismiss: { reloadContent() }) {
            DocumentImportView(coordinator: coordinator) { newDocs in
                storeManager.saveDocuments(newDocs)
                reloadContent()
                if newDocs.count == 1 {
                    activeDocument = newDocs.first
                }
            }
        }
        .sheet(isPresented: $showFolderImporter) {
            FolderPickerView { folderURL in
                importFolder(folderURL)
            }
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsSheet()
        }
        .fullScreenCover(isPresented: $showFSRSVoiceSession, onDismiss: { reloadContent() }) {
            FSRSVoiceReviewSessionView(coordinator: coordinator)
        }
        .fullScreenCover(item: $activeAssimilLesson, onDismiss: { reloadContent() }) { lesson in
            AssimilTeacherSessionView(lesson: lesson, coordinator: coordinator)
        }
        .fullScreenCover(item: $activeDocument, onDismiss: { reloadContent() }) { doc in
            DocumentTeacherSessionView(document: doc, coordinator: coordinator)
        }
        .fullScreenCover(item: $activeFolderSession, onDismiss: { reloadContent() }) { session in
            FolderCourseSessionView(session: session, coordinator: coordinator)
        }
    }
    
    private func reloadContent() {
        var loadedLessons = storeManager.loadLessons()
        if loadedLessons.isEmpty {
            let defaultLessons = DefaultGermanCurriculum.seedLessons()
            for lesson in defaultLessons {
                storeManager.saveLesson(lesson)
            }
            loadedLessons = defaultLessons
        }
        lessons = loadedLessons
        documents = storeManager.loadDocuments()
        fsrsDueItems = fsrsStore.getDueItems(for: coordinator.language.id)
    }
    
    private func seedFSRSIfNeeded() {
        let existing = fsrsStore.loadItems(for: "de")
        if existing.isEmpty || existing.count < 10 {
            let seeds = DefaultGermanCurriculum.seedVocabulary()
            fsrsStore.saveItems(seeds)
        }
    }
    
    private func importFolder(_ folderURL: URL) {
        Task {
            do {
                let docs = try await DocumentImportManager.shared.importFolder(
                    from: folderURL,
                    targetLanguageID: coordinator.store.preferences.learningLanguageID
                )
                await MainActor.run {
                    storeManager.saveDocuments(docs)
                    reloadContent()
                    
                    // Auto-open folder course session
                    let folderName = folderURL.lastPathComponent
                    let folderDocs = docs.filter { $0.folderName == folderName }
                    if !folderDocs.isEmpty {
                        activeFolderSession = FolderStudySession(
                            id: UUID(),
                            folderName: folderName,
                            documents: folderDocs,
                            detectedLevel: StudyLevel.detect(from: folderName).rawValue
                        )
                    }
                }
            } catch {
                print("Folder import error: \(error.localizedDescription)")
            }
        }
    }
    
    private var filteredDocuments: [StudyDocument] {
        if selectedLevelFilter == .all {
            return documents
        }
        return documents.filter { $0.level == selectedLevelFilter.rawValue }
    }
    
    /// Group documents by folder name
    private var folderGroups: [(String, [StudyDocument])] {
        let grouped = Dictionary(grouping: filteredDocuments.filter { $0.folderName != nil }) { $0.folderName! }
        return grouped.sorted { $0.key < $1.key }
    }
    
    private var ungroupedDocuments: [StudyDocument] {
        filteredDocuments.filter { $0.folderName == nil }
    }

    // MARK: - Sections
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "graduationcap.fill")
                    .font(.title)
                    .foregroundStyle(FluenceColor.orange)
                Text("Professeur Particulier")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(FluenceColor.ink)
            }
            Text("Importez un **dossier entier** de cours par niveau (A1→C1), ou des fichiers individuels (PDF, Word, images, texte…). L'IA lit le contenu en ligne et vous fait cours en questions interactives.")
                .font(.subheadline)
                .foregroundStyle(FluenceColor.secondary)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }

    // MARK: - FSRS Spaced Repetition & Notification Card
    private var fsrsVoiceSection: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(FluenceColor.orange)
                    Text("Mémoire FSRS & Répétition Vocale")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(FluenceColor.ink)
                }
                Spacer()
                Button {
                    showNotificationSettings = true
                } label: {
                    Image(systemName: "bell.badge.fill")
                        .font(.title3)
                        .foregroundStyle(FluenceColor.orange)
                }
            }
            
            Text("L'algorithme FSRS s'auto-adapte à votre mémoire au fil du temps. Les révisions se font **100% en vocal** (sans écrit) au cours d'une conversation fluide avec l'IA.")
                .font(.caption)
                .foregroundStyle(FluenceColor.secondary)
                .lineSpacing(2)
            
            // Due terms preview
            if !fsrsDueItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("À réactiver aujourd'hui (\(fsrsDueItems.count)) :")
                        .font(.caption2.bold())
                        .foregroundStyle(FluenceColor.ink)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(fsrsDueItems.prefix(6)) { item in
                                let r = Int(item.retrievability() * 100)
                                HStack(spacing: 4) {
                                    Text(item.term)
                                        .font(.caption.bold())
                                    Text("\(r)%")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(r < 70 ? .red : .orange)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(FluenceColor.cream, in: Capsule())
                            }
                        }
                    }
                }
            }
            
            // Primary Action Button (100% Voice session)
            Button {
                showFSRSVoiceSession = true
            } label: {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.headline)
                    Text("Lancer la Révision 100% Vocale (FSRS)")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [FluenceColor.orange, Color(red: 0.95, green: 0.45, blue: 0.2)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: FluenceColor.orange.opacity(0.3), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)
    }
    
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Scanner Assimil
                Button {
                    showScanner = true
                } label: {
                    quickActionCard(
                        icon: "camera.viewfinder",
                        iconColor: FluenceColor.orange,
                        bgColor: Color(red: 1.0, green: 0.92, blue: 0.82),
                        title: "Scanner Assimil",
                        subtitle: "Photo de livre & OCR"
                    )
                }
                .buttonStyle(.plain)

                // Single file
                Button {
                    showDocImporter = true
                } label: {
                    quickActionCard(
                        icon: "doc.badge.plus",
                        iconColor: Color.blue,
                        bgColor: Color(red: 0.88, green: 0.94, blue: 1.0),
                        title: "Fichier",
                        subtitle: "PDF, Word, Image, Texte…"
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Full folder import (primary CTA)
            Button {
                showFolderImporter = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.85, green: 0.95, blue: 0.85))
                            .frame(width: 48, height: 48)
                        Image(systemName: "folder.fill.badge.plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Importer un dossier entier de cours")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(FluenceColor.ink)
                        Text("Google Drive, iCloud, ou fichiers locaux — tous les niveaux (A1→C1)")
                            .font(.caption2)
                            .foregroundStyle(FluenceColor.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(FluenceColor.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func quickActionCard(icon: String, iconColor: Color, bgColor: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle()
                    .fill(bgColor)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(FluenceColor.ink)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(FluenceColor.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
    
    // MARK: - Level Filter Bar
    private var levelFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudyLevel.allCases) { level in
                    Button {
                        selectedLevelFilter = level
                    } label: {
                        Text(level.shortLabel)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedLevelFilter == level ? FluenceColor.orange : FluenceColor.cream,
                                in: Capsule()
                            )
                            .foregroundStyle(selectedLevelFilter == level ? .white : FluenceColor.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Folder Groups Section
    private var folderGroupsSection: some View {
        Group {
            if !folderGroups.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Dossiers de Cours", systemImage: "folder.fill")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(FluenceColor.ink)
                    
                    ForEach(folderGroups, id: \.0) { (folderName, docs) in
                        Button {
                            let level = StudyLevel.detect(from: folderName).rawValue
                            activeFolderSession = FolderStudySession(
                                id: UUID(),
                                folderName: folderName,
                                documents: docs,
                                detectedLevel: level
                            )
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green.opacity(0.12))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.green)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(folderName)
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .foregroundStyle(FluenceColor.ink)
                                        .lineLimit(1)
                                    HStack(spacing: 8) {
                                        let level = StudyLevel.detect(from: folderName)
                                        Text(level.displayName)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.15), in: Capsule())
                                        Text("\(docs.count) fichier(s)")
                                            .font(.caption2)
                                            .foregroundStyle(FluenceColor.secondary)
                                        let types = Set(docs.map(\.fileType))
                                        Text(types.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(FluenceColor.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                VStack(spacing: 2) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.green)
                                    Text("Cours")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.green)
                                }
                            }
                            .padding(14)
                            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var assimilSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Leçons Assimil Scannées", systemImage: "book.pages")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(FluenceColor.ink)
                Spacer()
                Text("\(lessons.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(FluenceColor.butter.opacity(0.8), in: Capsule())
            }

            if lessons.isEmpty {
                emptyPlaceholder(
                    icon: "camera.badge.ellipsis",
                    title: "Aucune leçon scannée",
                    subtitle: "Prenez en photo une page de votre méthode Assimil pour démarrer."
                )
            } else {
                ForEach(lessons) { lesson in
                    Button {
                        activeAssimilLesson = lesson
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(FluenceColor.orange.opacity(0.15))
                                    .frame(width: 46, height: 46)
                                Text(lesson.lessonNumber.map { "\($0)" } ?? "📖")
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .foregroundStyle(FluenceColor.orange)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lesson.title)
                                    .font(.system(.body, design: .rounded, weight: .medium))
                                    .foregroundStyle(FluenceColor.ink)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text("\(lesson.dialogue.count) répliques")
                                    Text("•")
                                    Text("\(lesson.exercises.count) exercices")
                                }
                                .font(.caption2)
                                .foregroundStyle(FluenceColor.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(FluenceColor.secondary)
                        }
                        .padding(14)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            storeManager.deleteLesson(id: lesson.id)
                            reloadContent()
                        } label: {
                            Label("Supprimer cette leçon", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Documents Individuels", systemImage: "doc.text")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(FluenceColor.ink)
                Spacer()
                Text("\(ungroupedDocuments.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15), in: Capsule())
            }

            if ungroupedDocuments.isEmpty {
                emptyPlaceholder(
                    icon: "doc.badge.plus",
                    title: "Aucun document individuel",
                    subtitle: "Importez un fichier (PDF, Word, image, texte) depuis Google Drive ou vos fichiers."
                )
            } else {
                ForEach(ungroupedDocuments) { doc in
                    Button {
                        activeDocument = doc
                    } label: {
                        documentRow(doc)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            storeManager.deleteDocument(id: doc.id)
                            reloadContent()
                        } label: {
                            Label("Supprimer ce document", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
    
    private func documentRow(_ doc: StudyDocument) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: iconForFileType(doc.fileType))
                    .font(.system(size: 20))
                    .foregroundStyle(Color.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(FluenceColor.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(doc.fileType)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                    Text(doc.level)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    Text(doc.source)
                        .font(.caption2)
                        .foregroundStyle(FluenceColor.secondary)
                    Text("• \(doc.pageCount) p.")
                        .font(.caption2)
                        .foregroundStyle(FluenceColor.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(FluenceColor.secondary)
        }
        .padding(14)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.02), radius: 4, y: 1)
    }
    
    private func iconForFileType(_ type: String) -> String {
        switch type.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc", "word": return "doc.text"
        case "image (ocr)", "image / ocr": return "photo"
        case "epub": return "book"
        case "html", "htm": return "globe"
        case "pptx", "powerpoint": return "rectangle.split.3x3"
        case "xlsx", "csv": return "tablecells"
        default: return "doc.plaintext"
        }
    }

    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(FluenceColor.secondary.opacity(0.7))
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(FluenceColor.ink)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(FluenceColor.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Folder Study Session Model
struct FolderStudySession: Identifiable, Equatable {
    let id: UUID
    let folderName: String
    let documents: [StudyDocument]
    let detectedLevel: String
    
    static func == (lhs: FolderStudySession, rhs: FolderStudySession) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Folder Course Session View (Interactive Q&A Teacher across all docs in a folder)
struct FolderCourseSessionView: View {
    let session: FolderStudySession
    let coordinator: ConversationCoordinator
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDocIndex: Int = 0
    @State private var teacherMessage: String = ""
    @State private var userReply: String = ""
    @State private var isThinking = false
    @State private var conversationHistory: [[String: String]] = []
    @State private var showDocContent = false
    
    private let synthesizer = NativeSynthesizer()
    
    private var currentDoc: StudyDocument? {
        guard selectedDocIndex >= 0 && selectedDocIndex < session.documents.count else { return nil }
        return session.documents[selectedDocIndex]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top: folder info + doc selector
                folderHeader
                
                // Main chat
                ScrollView {
                    VStack(spacing: 16) {
                        FluenceAura(energy: isThinking ? 0.8 : 0.3, listening: false, active: true)
                            .frame(width: 120, height: 120)
                            .padding(.top, 6)
                        
                        // Teacher card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TUTEUR FLUENCE — \(session.detectedLevel)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.green)
                                Spacer()
                                Button {
                                    speakTeacher()
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Color.green)
                                }
                            }
                            
                            Text(teacherMessage.isEmpty ? "Bienvenue dans le dossier « \(session.folderName) » ! Je vais vous faire cours sur ces \(session.documents.count) fichier(s). Prêt ?" : teacherMessage)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(FluenceColor.ink)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                        
                        // Show/hide document content (read inline)
                        if let doc = currentDoc {
                            DisclosureGroup(isExpanded: $showDocContent) {
                                ScrollView {
                                    Text(doc.rawContent)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(FluenceColor.secondary)
                                        .textSelection(.enabled)
                                        .padding(12)
                                }
                                .frame(maxHeight: 300)
                                .background(FluenceColor.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("Lire le contenu : « \(doc.title) » (\(doc.fileType) • \(doc.pageCount) p.)")
                                        .lineLimit(1)
                                }
                                .font(.caption.bold())
                                .foregroundStyle(Color.blue)
                            }
                            .padding(12)
                            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(20)
                }
                
                // Input bar
                inputBar
            }
            .background(FluenceColor.background)
            .navigationTitle("Cours : \(session.folderName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        synthesizer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startFolderCourse()
            }
        }
    }
    
    private var folderHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(session.documents.enumerated()), id: \.element.id) { (idx, doc) in
                    Button {
                        selectedDocIndex = idx
                        switchToDocument(doc)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedDocIndex == idx ? "doc.fill" : "doc")
                                .font(.caption2)
                            Text(doc.title)
                                .font(.caption2.bold())
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedDocIndex == idx ? Color.green : Color.white,
                            in: Capsule()
                        )
                        .foregroundStyle(selectedDocIndex == idx ? .white : FluenceColor.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(FluenceColor.surface)
    }
    
    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Répondre au professeur…", text: $userReply)
                .padding(12)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20))
            
            Button {
                sendReply()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.green)
            }
            .disabled(userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
        }
        .padding(12)
        .background(FluenceColor.background)
    }
    
    private func startFolderCourse() {
        guard let doc = currentDoc else { return }
        isThinking = true
        
        let prompt = CourseQAPolicy.socraticCoursePrompt(
            document: doc,
            level: session.detectedLevel,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        conversationHistory = [
            ["role": "user", "content": "Commence le cours interactif en questions sur ce document. Présente brièvement le sujet et pose une première question à l'élève."]
        ]
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    teacherMessage = result.text
                    conversationHistory.append(["role": "assistant", "content": result.text])
                    isThinking = false
                    speakTeacher()
                }
            } catch {
                await MainActor.run {
                    teacherMessage = "Prêt pour le cours ! Dites « Commence » pour démarrer."
                    isThinking = false
                }
            }
        }
    }
    
    private func switchToDocument(_ doc: StudyDocument) {
        isThinking = true
        showDocContent = false
        
        let prompt = CourseQAPolicy.socraticCoursePrompt(
            document: doc,
            level: session.detectedLevel,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        conversationHistory.append(["role": "user", "content": "L'élève passe maintenant au fichier « \(doc.title) ». Continue le cours avec ce nouveau contenu. Pose une question."])
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    teacherMessage = result.text
                    conversationHistory.append(["role": "assistant", "content": result.text])
                    isThinking = false
                    speakTeacher()
                }
            } catch {
                await MainActor.run {
                    teacherMessage = "Passons au document « \(doc.title) ». Que souhaitez-vous travailler ?"
                    isThinking = false
                }
            }
        }
    }
    
    private func sendReply() {
        guard !userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let doc = currentDoc else { return }
        let text = userReply
        userReply = ""
        isThinking = true
        
        conversationHistory.append(["role": "user", "content": text])
        
        let prompt = CourseQAPolicy.socraticCoursePrompt(
            document: doc,
            level: session.detectedLevel,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    teacherMessage = result.text
                    conversationHistory.append(["role": "assistant", "content": result.text])
                    isThinking = false
                    speakTeacher()
                }
            } catch {
                await MainActor.run {
                    teacherMessage = "Bien reçu ! Continuons."
                    isThinking = false
                }
            }
        }
    }
    
    private func speakTeacher() {
        guard !teacherMessage.isEmpty else { return }
        synthesizer.speak(
            text: teacherMessage,
            languageCode: "de-DE",
            rate: coordinator.store.preferences.speechRate
        )
    }
}

// MARK: - Assimil Multi-Photo Scanner View
struct AssimilScannerView: View {
    let coordinator: ConversationCoordinator
    let onSave: (AssimilLesson) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImages: [UIImage] = []
    @State private var newlyCapturedImage: UIImage?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var errorMessage: String?
    
    @State private var parsedLesson: AssimilLesson?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let parsedLesson = parsedLesson {
                        lessonPreviewSection(parsedLesson)
                    } else if !capturedImages.isEmpty {
                        multiImagePreviewSection
                    } else {
                        captureOptionsSection
                    }
                }
                .padding(20)
            }
            .background(FluenceColor.background)
            .navigationTitle("Scanner Assimil (Multi-Pages)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if let lesson = parsedLesson {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            onSave(lesson)
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPickerView(selectedImage: $newlyCapturedImage)
            }
            .onChange(of: newlyCapturedImage) { _, newImg in
                if let newImg {
                    capturedImages.append(newImg)
                    newlyCapturedImage = nil
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let img = UIImage(data: data) {
                            await MainActor.run {
                                self.capturedImages.append(img)
                            }
                        }
                    }
                    await MainActor.run {
                        self.selectedPhotoItems = []
                    }
                }
            }
        }
    }

    private var captureOptionsSection: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(FluenceColor.orange)
                .padding(.top, 20)
            
            Text("Photographiez les pages Assimil")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(FluenceColor.ink)
            
            Text("Vous pouvez prendre **plusieurs photos** (ex: page gauche du dialogue et page droite de traduction/grammaire/exercices).")
                .font(.subheadline)
                .foregroundStyle(FluenceColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Prendre une photo", systemImage: "camera.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(FluenceColor.orange, in: RoundedRectangle(cornerRadius: 14))
                }
                
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images) {
                    Label("Choisir plusieurs photos (Galerie)", systemImage: "photo.stack")
                        .font(.headline)
                        .foregroundStyle(FluenceColor.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var multiImagePreviewSection: some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(capturedImages.count) page(s) scannée(s)")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Button("Tout effacer") {
                    capturedImages = []
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            // Thumbnail Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 14) {
                ForEach(Array(capturedImages.enumerated()), id: \.offset) { (idx, img) in
                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("Page \(idx + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(FluenceColor.ink)
                                .padding(.horizontal, 4)
                        }
                        
                        Button {
                            capturedImages.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .padding(6)
                    }
                    .padding(8)
                    .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                }
            }

            // Add more pages buttons
            HStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Ajouter page", systemImage: "camera.badge.plus")
                        .font(.caption.bold())
                        .foregroundStyle(FluenceColor.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(FluenceColor.orange.opacity(0.12), in: Capsule())
                }
                
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                    Label("Ajouter galerie", systemImage: "photo.badge.plus")
                        .font(.caption.bold())
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
            }

            if isProcessing {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(FluenceColor.orange)
                    Text(processingStatus)
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                }
                .padding(.vertical, 10)
            } else {
                Button {
                    processMultipleImages()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyser les \(capturedImages.count) page(s) (Gemini Vision)")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(FluenceColor.orange, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: FluenceColor.orange.opacity(0.3), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func lessonPreviewSection(_ lesson: AssimilLesson) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Leçon \(lesson.lessonNumber.map(String.init) ?? "1") • \(lesson.dialogue.count) phrases")
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                }
                Spacer()
                Button("Re-scanner") {
                    parsedLesson = nil
                    capturedImages = []
                }
                .font(.caption)
            }

            Divider()

            Text("Dialogue Extrait")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(lesson.dialogue) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text("\(line.lineIndex).")
                                .font(.caption.bold())
                                .foregroundStyle(FluenceColor.orange)
                            Text(line.targetText)
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(FluenceColor.ink)
                            Spacer()
                        }
                        Text(line.nativeTranslation)
                            .font(.caption)
                            .foregroundStyle(FluenceColor.secondary)
                            .padding(.leading, 18)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FluenceColor.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            if !lesson.grammarNotes.isEmpty {
                Divider()
                Text("Remarques & Grammaire")
                    .font(.headline)
                ForEach(lesson.grammarNotes, id: \.self) { note in
                    Text("• " + note)
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func processMultipleImages() {
        guard !capturedImages.isEmpty else { return }
        isProcessing = true
        errorMessage = nil
        processingStatus = "Analyse multimodale de \(capturedImages.count) page(s)..."

        Task {
            do {
                let targetLang = coordinator.language.name
                let lesson: AssimilLesson
                
                let googleKey = coordinator.store.preferences.googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !googleKey.isEmpty {
                    await MainActor.run { processingStatus = "Analyse Gemini 2.0 Flash multimodale (\(capturedImages.count) pages)..." }
                    lesson = try await VisionOCRManager.shared.extractAndParseWithGemini(
                        images: capturedImages,
                        apiClient: coordinator.apiClient,
                        preferences: coordinator.store.preferences,
                        targetLanguage: targetLang
                    )
                } else {
                    await MainActor.run { processingStatus = "OCR Apple Vision (\(capturedImages.count) pages)..." }
                    lesson = try await VisionOCRManager.shared.extractAndParseWithGemini(
                        images: capturedImages,
                        apiClient: coordinator.apiClient,
                        preferences: coordinator.store.preferences,
                        targetLanguage: targetLang
                    )
                }
                
                await MainActor.run {
                    self.parsedLesson = lesson
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}

// MARK: - Document Import View (Google Drive & Local Files — single file + paste)
struct DocumentImportView: View {
    let coordinator: ConversationCoordinator
    let onSave: ([StudyDocument]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var isProcessing = false
    @State private var processingStatus = ""
    @State private var errorMessage: String?
    
    @State private var pastedTitle = ""
    @State private var pastedContent = ""
    @State private var selectedDocs: [StudyDocument] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !selectedDocs.isEmpty {
                        docsPreviewSection
                    } else {
                        importOptionsSection
                    }
                }
                .padding(20)
            }
            .background(FluenceColor.background)
            .navigationTitle("Importer un Fichier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if !selectedDocs.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            onSave(selectedDocs)
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    .pdf, .plainText, .text, .data, .image,
                    .init(filenameExtension: "docx") ?? .data,
                    .init(filenameExtension: "doc") ?? .data,
                    .init(filenameExtension: "rtf") ?? .data,
                    .init(filenameExtension: "md") ?? .data,
                    .init(filenameExtension: "epub") ?? .data,
                    .init(filenameExtension: "csv") ?? .data,
                    .html
                ],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    private var importOptionsSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.blue)
                
                Text("Tous types de fichiers")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(FluenceColor.ink)
                
                Text("PDF, Word (.docx), images (OCR auto), texte, Markdown, ePub, CSV, HTML… Sélectionnez un ou plusieurs fichiers.")
                    .font(.subheadline)
                    .foregroundStyle(FluenceColor.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Choisir des fichiers", systemImage: "arrow.down.doc.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(22)
            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))

            // Paste text option
            VStack(alignment: .leading, spacing: 12) {
                Text("Ou coller un texte de cours :")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(FluenceColor.ink)
                
                TextField("Titre du cours / leçon", text: $pastedTitle)
                    .padding(12)
                    .background(FluenceColor.cream, in: RoundedRectangle(cornerRadius: 10))
                
                TextField("Collez le texte du cours ici...", text: $pastedContent, axis: .vertical)
                    .lineLimit(4...8)
                    .padding(12)
                    .background(FluenceColor.cream, in: RoundedRectangle(cornerRadius: 10))
                
                Button {
                    createFromPastedText()
                } label: {
                    Text("Valider ce texte")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(FluenceColor.ink, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(pastedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))

            if isProcessing {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.blue)
                    Text(processingStatus)
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var docsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(selectedDocs.count) fichier(s) importé(s)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Button("Réinitialiser") {
                    selectedDocs = []
                }
                .font(.caption)
            }
            
            ForEach(selectedDocs) { doc in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(doc.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Spacer()
                        Text(doc.fileType)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                        Text(doc.level)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                    }
                    
                    Text(doc.summary)
                        .font(.caption)
                        .foregroundStyle(FluenceColor.secondary)
                        .lineSpacing(2)
                    
                    if !doc.keyConcepts.isEmpty {
                        Text("Concepts : \(doc.keyConcepts.map(\.term).joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(FluenceColor.ink.opacity(0.7))
                    }
                }
                .padding(14)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isProcessing = true
            errorMessage = nil
            processingStatus = "Import de \(urls.count) fichier(s)…"
            Task {
                var imported: [StudyDocument] = []
                for url in urls {
                    do {
                        var doc = try await DocumentImportManager.shared.importFile(
                            from: url,
                            targetLanguageID: coordinator.store.preferences.learningLanguageID
                        )
                        await MainActor.run { processingStatus = "Analyse IA de « \(doc.title) »…" }
                        try await DocumentImportManager.shared.analyzeDocument(
                            document: &doc,
                            apiClient: coordinator.apiClient,
                            preferences: coordinator.store.preferences
                        )
                        imported.append(doc)
                    } catch {
                        print("Skip file \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                await MainActor.run {
                    if imported.isEmpty {
                        errorMessage = "Aucun fichier n'a pu être importé."
                    } else {
                        selectedDocs = imported
                    }
                    isProcessing = false
                }
            }
        case .failure(let error):
            self.errorMessage = error.localizedDescription
        }
    }

    private func createFromPastedText() {
        let title = pastedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Notes de cours" : pastedTitle
        var doc = StudyDocument(
            title: title,
            source: "Texte / Note",
            rawContent: pastedContent,
            targetLanguageID: coordinator.store.preferences.learningLanguageID
        )
        isProcessing = true
        errorMessage = nil
        processingStatus = "Analyse pédagogique…"
        Task {
            do {
                try await DocumentImportManager.shared.analyzeDocument(
                    document: &doc,
                    apiClient: coordinator.apiClient,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.selectedDocs = [doc]
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}

// MARK: - Assimil Teacher Session View (Interactive Tutor)
struct AssimilTeacherSessionView: View {
    let lesson: AssimilLesson
    let coordinator: ConversationCoordinator
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: String = "dialogue"
    @State private var selectedLineIndex: Int = 0
    
    @State private var teacherMessage: String = ""
    @State private var userReply: String = ""
    @State private var isListening = false
    @State private var isThinking = false
    @State private var conversationHistory: [[String: String]] = []
    
    private let synthesizer = NativeSynthesizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepPickerBar
                
                ScrollView {
                    VStack(spacing: 16) {
                        FluenceAura(energy: isThinking ? 0.8 : (isListening ? 0.6 : 0.2), listening: isListening, active: true)
                            .frame(width: 140, height: 140)
                            .padding(.top, 10)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TUTEUR FLUENCE")
                                    .font(.caption.bold())
                                    .foregroundStyle(FluenceColor.orange)
                                Spacer()
                                Button {
                                    speakTeacherMessage()
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(FluenceColor.orange)
                                }
                            }
                            
                            Text(teacherMessage.isEmpty ? "Bonjour ! Je suis votre professeur pour cette leçon Assimil. Choisissez une étape pour commencer." : teacherMessage)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(FluenceColor.ink)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

                        if currentStep == "dialogue" {
                            dialogueStepView
                        } else if currentStep == "grammar" {
                            grammarStepView
                        } else if currentStep == "exercises" {
                            exercisesStepView
                        }
                    }
                    .padding(20)
                }

                bottomControlBar
            }
            .background(FluenceColor.background)
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        synthesizer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startStep("dialogue")
            }
        }
    }

    private var stepPickerBar: some View {
        HStack(spacing: 8) {
            stepButton(id: "dialogue", title: "1. Dialogue", icon: "bubble.left.and.bubble.right")
            stepButton(id: "grammar", title: "2. Grammaire", icon: "character.book.closed")
            stepButton(id: "exercises", title: "3. Exercices", icon: "pencil.and.list.clipboard")
            stepButton(id: "conversation", title: "4. Pratique", icon: "waveform")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(FluenceColor.surface)
    }

    private func stepButton(id: String, title: String, icon: String) -> some View {
        Button {
            currentStep = id
            startStep(id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(currentStep == id ? FluenceColor.orange : FluenceColor.cream, in: Capsule())
            .foregroundStyle(currentStep == id ? .white : FluenceColor.ink)
        }
        .buttonStyle(.plain)
    }

    private var dialogueStepView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lignes du Dialogue")
                .font(.headline)
            
            ForEach(Array(lesson.dialogue.enumerated()), id: \.element.id) { (idx, line) in
                Button {
                    selectedLineIndex = idx
                    teachDialogueLine(line)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(line.lineIndex). \(line.targetText)")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(selectedLineIndex == idx ? FluenceColor.orange : FluenceColor.ink)
                            Text(line.nativeTranslation)
                                .font(.caption2)
                                .foregroundStyle(FluenceColor.secondary)
                        }
                        Spacer()
                        Image(systemName: "speaker.wave.1")
                            .foregroundStyle(FluenceColor.orange)
                    }
                    .padding(10)
                    .background(selectedLineIndex == idx ? FluenceColor.accent.opacity(0.15) : FluenceColor.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grammarStepView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes de Grammaire & Vocabulaire")
                .font(.headline)
            
            ForEach(lesson.grammarNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(FluenceColor.orange)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(FluenceColor.ink)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var exercisesStepView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercices de la Leçon")
                .font(.headline)
            
            ForEach(lesson.exercises) { ex in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ex.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(FluenceColor.ink)
                    ForEach(ex.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Q\(item.itemIndex): \(item.prompt)")
                                .font(.caption.bold())
                            Text("Solution : \(item.expectedAnswer)")
                                .font(.caption2)
                                .foregroundStyle(FluenceColor.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FluenceColor.cream.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var bottomControlBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                TextField("Répondre au professeur...", text: $userReply)
                    .padding(12)
                    .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20))
                
                Button {
                    sendUserReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(FluenceColor.orange)
                }
                .disabled(userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            }
        }
        .padding(12)
        .background(FluenceColor.background)
    }

    private func startStep(_ step: String) {
        isThinking = true
        let prompt = AssimilTeacherPolicy.systemPrompt(
            lesson: lesson,
            step: step,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        let introText = "Commence l'étape '\(step)' avec l'élève. Salue-le et lance la première consigne interactive."
        conversationHistory = [
            ["role": "user", "content": introText]
        ]
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.teacherMessage = result.text
                    self.conversationHistory.append(["role": "assistant", "content": result.text])
                    self.isThinking = false
                    speakTeacherMessage()
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Prêt pour l'étape \(step) ! Posez-moi vos questions ou écoutez le dialogue."
                    self.isThinking = false
                }
            }
        }
    }

    private func teachDialogueLine(_ line: AssimilLine) {
        synthesizer.speak(text: line.targetText, languageCode: "de-DE", rate: coordinator.store.preferences.speechRate)
        teacherMessage = "Phrase \(line.lineIndex) : « \(line.targetText) »\n(Traduction : \(line.nativeTranslation))\n\nRépétez la phrase à l'oral ou écrivez-la ci-dessous."
    }

    private func sendUserReply() {
        guard !userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = userReply
        userReply = ""
        isThinking = true
        
        conversationHistory.append(["role": "user", "content": text])
        let prompt = AssimilTeacherPolicy.systemPrompt(
            lesson: lesson,
            step: currentStep,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.teacherMessage = result.text
                    self.conversationHistory.append(["role": "assistant", "content": result.text])
                    self.isThinking = false
                    speakTeacherMessage()
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Bien reçu ! Continuons."
                    self.isThinking = false
                }
            }
        }
    }

    private func speakTeacherMessage() {
        guard !teacherMessage.isEmpty else { return }
        synthesizer.speak(
            text: teacherMessage,
            languageCode: "de-DE",
            rate: coordinator.store.preferences.speechRate,
            voiceIdentifier: coordinator.store.preferences.selectedVoiceIdentifier
        )
    }
}

// MARK: - Document Teacher Session View (Single Document Interactive)
struct DocumentTeacherSessionView: View {
    let document: StudyDocument
    let coordinator: ConversationCoordinator
    
    @Environment(\.dismiss) private var dismiss
    @State private var teacherMessage: String = ""
    @State private var userReply: String = ""
    @State private var isThinking = false
    @State private var conversationHistory: [[String: String]] = []
    @State private var showRawContent = false
    
    private let synthesizer = NativeSynthesizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        FluenceAura(energy: isThinking ? 0.8 : 0.3, listening: false, active: true)
                            .frame(width: 140, height: 140)
                            .padding(.top, 10)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("TUTEUR — \(document.fileType) • \(document.level)")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.blue)
                                Spacer()
                                Button {
                                    speakTeacherMessage()
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(Color.blue)
                                }
                            }
                            
                            Text(teacherMessage.isEmpty ? "Bonjour ! J'ai lu votre document « \(document.title) ». Que souhaitez-vous travailler ?" : teacherMessage)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(FluenceColor.ink)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                        
                        // Inline document reader
                        DisclosureGroup(isExpanded: $showRawContent) {
                            ScrollView {
                                Text(document.rawContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(FluenceColor.secondary)
                                    .textSelection(.enabled)
                                    .padding(12)
                            }
                            .frame(maxHeight: 300)
                            .background(FluenceColor.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("Lire le contenu du document (\(document.pageCount) page(s))")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(Color.blue)
                        }
                        .padding(12)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 12))

                        // Quick Quiz Cards
                        if !document.quizQuestions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Questions d'entraînement")
                                    .font(.headline)
                                ForEach(document.quizQuestions) { q in
                                    Button {
                                        userReply = "Réponds à la question : \(q.question)"
                                        sendUserReply()
                                    } label: {
                                        Text("❓ " + q.question)
                                            .font(.caption.bold())
                                            .foregroundStyle(FluenceColor.ink)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                // Input bar
                HStack(spacing: 12) {
                    TextField("Poser une question sur le document...", text: $userReply)
                        .padding(12)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    
                    Button {
                        sendUserReply()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.blue)
                    }
                    .disabled(userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
                .padding(12)
                .background(FluenceColor.background)
            }
            .background(FluenceColor.background)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quitter") {
                        synthesizer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startDocumentTutoring()
            }
        }
    }

    private func startDocumentTutoring() {
        isThinking = true
        let prompt = CourseQAPolicy.socraticCoursePrompt(
            document: document,
            level: document.level,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        let intro = "Présente brièvement le sujet du document et pose une première question de réflexion à l'élève."
        conversationHistory = [
            ["role": "user", "content": intro]
        ]
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.teacherMessage = result.text
                    self.conversationHistory.append(["role": "assistant", "content": result.text])
                    self.isThinking = false
                    speakTeacherMessage()
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Document prêt ! Quelle notion souhaitez-vous travailler ?"
                    self.isThinking = false
                }
            }
        }
    }

    private func sendUserReply() {
        guard !userReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = userReply
        userReply = ""
        isThinking = true
        
        conversationHistory.append(["role": "user", "content": text])
        let prompt = CourseQAPolicy.socraticCoursePrompt(
            document: document,
            level: document.level,
            correctionLevel: coordinator.store.preferences.correctionLevel
        )
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.teacherMessage = result.text
                    self.conversationHistory.append(["role": "assistant", "content": result.text])
                    self.isThinking = false
                    speakTeacherMessage()
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Merci pour votre réponse. Poursuivons !"
                    self.isThinking = false
                }
            }
        }
    }

    private func speakTeacherMessage() {
        guard !teacherMessage.isEmpty else { return }
        synthesizer.speak(
            text: teacherMessage,
            languageCode: "de-DE",
            rate: coordinator.store.preferences.speechRate
        )
    }
}

// MARK: - FSRS 100% Voice Review Session View (Hands-Free Oral Mastery)
struct FSRSVoiceReviewSessionView: View {
    let coordinator: ConversationCoordinator
    
    @Environment(\.dismiss) private var dismiss
    @State private var dueItems: [FSRSItem] = []
    @State private var currentItemIndex: Int = 0
    @State private var teacherMessage: String = ""
    @State private var userSpokenReply: String = ""
    @State private var isListening = false
    @State private var isThinking = false
    @State private var conversationHistory: [[String: String]] = []
    @State private var sessionStats: (reviewed: Int, mastered: Int) = (0, 0)
    
    private let synthesizer = NativeSynthesizer()
    private let fsrsStore = FSRSStoreManager.shared

    private var currentItem: FSRSItem? {
        guard currentItemIndex >= 0 && currentItemIndex < dueItems.count else { return nil }
        return dueItems[currentItemIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                if !dueItems.isEmpty {
                    HStack {
                        Text("Item \(currentItemIndex + 1) / \(dueItems.count)")
                            .font(.caption.bold())
                            .foregroundStyle(FluenceColor.secondary)
                        Spacer()
                        if let item = currentItem {
                            Text("Rétention: \(Int(item.retrievability() * 100))%")
                                .font(.caption.bold())
                                .foregroundStyle(FluenceColor.orange)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                ScrollView {
                    VStack(spacing: 18) {
                        // Interactive Orb
                        FluenceAura(energy: isThinking ? 0.85 : (isListening ? 0.6 : 0.25), listening: isListening, active: true)
                            .frame(width: 150, height: 150)
                            .padding(.top, 12)
                        
                        // Teacher Oral Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("PROFESSEUR VOCAL FSRS")
                                    .font(.caption.bold())
                                    .foregroundStyle(FluenceColor.orange)
                                Spacer()
                                Button {
                                    speakTeacher()
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(FluenceColor.orange)
                                }
                            }
                            
                            Text(teacherMessage.isEmpty ? "Démarrage de la séance vocale..." : teacherMessage)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(FluenceColor.ink)
                                .lineSpacing(3)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                        // Quick action rating badges (auto or manual touch)
                        if let item = currentItem {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notion étudiée : « \(item.term) »")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(FluenceColor.ink)
                                Text(item.meaning)
                                    .font(.caption)
                                    .foregroundStyle(FluenceColor.secondary)
                                if let ex = item.example {
                                    Text("Exemple : \(ex)")
                                        .font(.caption2.italic())
                                        .foregroundStyle(FluenceColor.secondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FluenceColor.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(20)
                }

                // Bottom voice bar (Hands-Free Oral or Quick Reply)
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        TextField("Parler ou taper votre réponse...", text: $userSpokenReply)
                            .padding(12)
                            .background(FluenceColor.surface, in: RoundedRectangle(cornerRadius: 20))
                        
                        Button {
                            sendOralReply()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(FluenceColor.orange)
                        }
                        .disabled(userSpokenReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                    }
                    
                    // FSRS Rating buttons
                    HStack(spacing: 8) {
                        ForEach(FSRSRating.allCases, id: \.self) { rating in
                            Button {
                                recordRating(rating)
                            } label: {
                                Text(rating.label)
                                    .font(.caption2.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(colorForRating(rating).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(colorForRating(rating))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(14)
                .background(FluenceColor.background)
            }
            .background(FluenceColor.background)
            .navigationTitle("Révision Vocale FSRS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Terminer") {
                        synthesizer.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                startFSRSSession()
            }
        }
    }

    private func startFSRSSession() {
        dueItems = fsrsStore.getDueItems(for: coordinator.language.id, limit: 8)
        guard !dueItems.isEmpty else {
            teacherMessage = "Bravo ! Vous êtes à jour sur vos révisions FSRS. N'hésitez pas à lancer une conversation libre pour découvrir de nouvelles expressions !"
            return
        }
        currentItemIndex = 0
        promptNextItem()
    }

    private func promptNextItem() {
        guard let item = currentItem else {
            teacherMessage = "Super séance ! Vous avez révisé \(sessionStats.reviewed) notion(s). Votre mémoire FSRS est consolidée !"
            speakTeacher()
            return
        }
        
        isThinking = true
        let prompt = """
        Tu es le Professeur Fluence d'Allemand. Tu animes une révision 100% VOCALE basée sur l'algorithme FSRS.
        L'élément à réviser est : « \(item.term) » (\(item.meaning)).
        Exemple de contexte : \(item.example ?? "")
        Niveau visé : \(item.level)
        
        MISSION VOCALE :
        1. Ne donne pas directement la réponse !
        2. Pose une question naturelle et vivante à l'élève à l'oral pour lui faire utiliser ou traduire ce terme.
        3. Reste concis (1 à 2 phrases).
        """
        
        conversationHistory = [["role": "user", "content": "Lance la question orale pour réviser « \(item.term) »."]]
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                await MainActor.run {
                    self.teacherMessage = result.text
                    self.conversationHistory.append(["role": "assistant", "content": result.text])
                    self.isThinking = false
                    speakTeacher()
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Comment utilisez-vous « \(item.term) » dans une phrase en allemand ?"
                    self.isThinking = false
                    speakTeacher()
                }
            }
        }
    }

    private func sendOralReply() {
        guard !userSpokenReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let item = currentItem else { return }
        let text = userSpokenReply
        userSpokenReply = ""
        isThinking = true
        
        conversationHistory.append(["role": "user", "content": text])
        
        let prompt = """
        Tu es le Professeur Fluence d'Allemand.
        L'élève répond à la question sur « \(item.term) » (\(item.meaning)).
        Sa réponse est : « \(text) »
        
        MISSION :
        1. Évalue brièvement et oralement sa réponse avec bienveillance en français.
        2. Donne la formulation modèle exacte en allemand.
        3. Inclus à la fin une note FSRS sous la forme : `[RATING: 1|2|3|4]` (1=Again, 2=Hard, 3=Good, 4=Easy).
        """
        
        Task {
            do {
                let result = try await coordinator.apiClient.respondHistory(
                    instructions: prompt,
                    history: conversationHistory,
                    preferences: coordinator.store.preferences
                )
                
                var cleanText = result.text
                var detectedRating: FSRSRating = .good
                
                if cleanText.contains("[RATING: 1]") { detectedRating = .again }
                else if cleanText.contains("[RATING: 2]") { detectedRating = .hard }
                else if cleanText.contains("[RATING: 3]") { detectedRating = .good }
                else if cleanText.contains("[RATING: 4]") { detectedRating = .easy }
                
                cleanText = cleanText.replacingOccurrences(of: "\\[RATING: \\d\\]", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                await MainActor.run {
                    self.teacherMessage = cleanText
                    self.conversationHistory.append(["role": "assistant", "content": cleanText])
                    self.isThinking = false
                    speakTeacher()
                    
                    // Record review in FSRS
                    fsrsStore.recordReview(itemId: item.id, rating: detectedRating, duration: 6)
                    sessionStats.reviewed += 1
                    
                    // Schedule next item after 4 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                        self.currentItemIndex += 1
                        self.promptNextItem()
                    }
                }
            } catch {
                await MainActor.run {
                    self.teacherMessage = "Bien reçu ! Passons à la suite."
                    self.isThinking = false
                }
            }
        }
    }

    private func recordRating(_ rating: FSRSRating) {
        guard let item = currentItem else { return }
        fsrsStore.recordReview(itemId: item.id, rating: rating, duration: 4)
        sessionStats.reviewed += 1
        currentItemIndex += 1
        promptNextItem()
    }

    private func colorForRating(_ rating: FSRSRating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .blue
        case .easy: return .green
        }
    }

    private func speakTeacher() {
        guard !teacherMessage.isEmpty else { return }
        synthesizer.speak(
            text: teacherMessage,
            languageCode: "de-DE",
            rate: coordinator.store.preferences.speechRate
        )
    }
}

// MARK: - Daily Notification Settings Sheet
struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: NotificationSettings = NotificationManager.shared.settings
    @State private var morningDate: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? .now
    @State private var eveningDate: Date = Calendar.current.date(from: DateComponents(hour: 19, minute: 30)) ?? .now
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Rappels Quotidiens Vocaux")) {
                    Toggle("Activer les notifications quotidiennes", isOn: $settings.isEnabled)
                    
                    if settings.isEnabled {
                        Picker("Fréquence journalière", selection: $settings.notificationsPerDay) {
                            Text("1 fois par jour").tag(1)
                            Text("2 fois par jour (Matin & Soir)").tag(2)
                        }
                        
                        DatePicker("Rappel du matin", selection: $morningDate, displayedComponents: .hourAndMinute)
                        
                        if settings.notificationsPerDay >= 2 {
                            DatePicker("Rappel du soir", selection: $eveningDate, displayedComponents: .hourAndMinute)
                        }
                    }
                }
                
                Section(header: Text("Style des messages")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Messages presque humains & motivants :")
                            .font(.caption.bold())
                        Text("« Hé oh ! C'est l'heure de réviser 😉 Tu te rappelles comment on dit ... en allemand ? Viens me dire ça en vocal ! »")
                            .font(.caption2.italic())
                            .foregroundStyle(FluenceColor.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button {
                        testNotification()
                    } label: {
                        Label("Tester une notification immédiatement", systemImage: "paperplane.fill")
                            .font(.subheadline)
                    }
                }
                
                if let status = statusMessage {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Color.green)
                    }
                }
            }
            .navigationTitle("Notifications Journalières")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                let cal = Calendar.current
                morningDate = cal.date(from: DateComponents(hour: settings.morningHour, minute: settings.morningMinute)) ?? morningDate
                eveningDate = cal.date(from: DateComponents(hour: settings.eveningHour, minute: settings.eveningMinute)) ?? eveningDate
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        settings.morningHour = cal.component(.hour, from: morningDate)
        settings.morningMinute = cal.component(.minute, from: morningDate)
        settings.eveningHour = cal.component(.hour, from: eveningDate)
        settings.eveningMinute = cal.component(.minute, from: eveningDate)
        NotificationManager.shared.saveSettings(settings)
    }

    private func testNotification() {
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            NotificationManager.shared.scheduleNotifications()
            await MainActor.run {
                statusMessage = "Notification programmée ! Vous recevrez vos rappels aux heures choisies."
            }
        }
    }
}

