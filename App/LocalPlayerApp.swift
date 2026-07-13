import SwiftUI
import SwiftData

@main
struct LocalPlayerApp: App {
    @StateObject private var audioPlayer = AudioPlayerService()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(audioPlayer)
        }
        .modelContainer(for: Song.self)
    }
}
