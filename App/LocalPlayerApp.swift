import SwiftUI
import SwiftData

@main
struct LocalPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: Song.self)
    }
}
