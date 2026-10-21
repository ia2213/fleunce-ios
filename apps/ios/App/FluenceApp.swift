import SwiftUI

@main struct FluenceApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?
    init() {
        do { _store = State(initialValue: try LearningStore(inMemory: ProcessInfo.processInfo.arguments.contains("--preview") || AudioVerification.requested)) }
        catch { _startupError = State(initialValue: "Fluence n’a pas pu ouvrir vos données d’apprentissage. Vos données existantes n'ont pas été écrasées.") }
    }
    
    private var colorScheme: ColorScheme? {
        guard let store else { return nil }
        switch store.preferences.appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil // System default
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let store {
                RootView(store: store)
                    .preferredColorScheme(colorScheme)
                    .task {
                        _ = await NotificationManager.shared.requestAuthorization()
                    }
                    .onOpenURL { url in
                        Task {
                            do {
                                _ = try await AnkiGoogleDriveManager.shared.importBatch(from: [url], store: store)
                            } catch {
                                print("Error opening shared file/folder:", error)
                            }
                        }
                    }
            }
            else {
                ContentUnavailableView("Réessayer", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError ?? "Le registre d'apprentissage n'est pas disponible."))
                    .preferredColorScheme(colorScheme)
            }
        }
    }
}
