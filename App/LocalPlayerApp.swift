import SwiftUI
import SwiftData

@main
struct LocalPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            Text("LocalPlayer")
        }
        .modelContainer(for: Song.self)
    }
}