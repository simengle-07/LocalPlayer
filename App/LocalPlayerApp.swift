import SwiftUI
import SwiftData

@main
struct LocalPlayerApp: App {
    @StateObject private var audioPlayer = AudioPlayerService()
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Song.self,
                migrationPlan: LocalPlayerMigrationPlan.self
            )
        } catch {
            fatalError("无法打开本地音乐资料库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(audioPlayer)
        }
        .modelContainer(modelContainer)
    }
}
