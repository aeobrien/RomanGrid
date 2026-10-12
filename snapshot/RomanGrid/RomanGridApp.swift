import SwiftUI
import SwiftData

@main
struct RomanGridApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self,
            SectionBlueprint.self,
            SectionInstance.self,
            ChordEvent.self,
            LyricsSection.self,
            LyricsLine.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If migration fails, try to create a fresh container
            print("Could not create ModelContainer, attempting fresh start: \(error)")
            let freshConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            // Delete the old store if it exists
            let url = freshConfiguration.url
            try? FileManager.default.removeItem(at: url)
            
            do {
                return try ModelContainer(for: schema, configurations: [freshConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even with fresh start: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
