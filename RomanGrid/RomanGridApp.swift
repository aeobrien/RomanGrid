import SwiftUI
import SwiftData

@main
struct RomanGridApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Song.self, SectionBlueprint.self, SectionInstance.self, ChordEvent.self])
    }
}
