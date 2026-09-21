import SwiftUI
import FleunceCore

@main struct FleunceApp: App {
    @State private var store: LearningStore?
    
    var body: some Scene {
        WindowGroup {
            if let store = store {
                RootView(store: store)
                    .preferredColorScheme(.light)
            } else {
                ProgressView("Initializing Fleunce...")
                    .task {
                        do {
                            // Heavy init moved to task
                            store = try LearningStore(inMemory: false)
                        } catch {
                            print("Failed to init store: \(error)")
                        }
                    }
            }
        }
    }
}
