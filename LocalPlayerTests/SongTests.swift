import Foundation
import Testing

@testable import LocalPlayer

struct SongTests {
    @Test
    func storesImportedSongMetadata() {
        let song = Song(
            contentHash: "abc123",
            storageFileName: "abc123.mp3",
            title: "Test Song",
            artist: "Test Artist",
            durationSeconds: 180.0,
            artworkData: nil,
            importedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(song.contentHash == "abc123")
        #expect(song.storageFileName == "abc123.mp3")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.durationSeconds == 180.0)
        #expect(song.artworkData == nil)
    }

    @Test
    func rejectsFilesThatAreNotMP3() async {
        let importer = MP3ImportService()
        let textFileURL = URL(fileURLWithPath: "/not-a-song.txt")

        do {
            _ = try await importer.importMP3(
                from: textFileURL,
                existingContentHashes: Set<String>()
            )
            Issue.record("Expected the importer to reject a non-MP3 file.")
        } catch MP3ImportError.unsupportedFileType {
            // Expected outcome.
        } catch {
            Issue.record("Expected unsupportedFileType, got \(error).")
        }
    }
}
